+++
title = "Building a distributed database that never goes down"
author = ["Lukasz Czaplinski"]
tags = ["elixir"]
categories = ["tutorials"]
draft = false
+++

## Preface {#preface}

One of the most important qualities off a programmer is the amount of patterns known.
They correspond to a number of solutions available for solving a given problem.
In this blogpost I'd like to showcase some distributed elixir communication patterns by building a simple geo-replicated in-memory database.

It is structured into three parts. If you are familiar with Elixir and Phoenix, feel free to skip to section "There can only one". If you want to know why it might not the best idea in production skip to "Here be dragons."

## Domain {#domain}

Let's imagine we need to build a note-taking app.
Each note will have a text and children (other notes). For some reason we decided to neither use a traditional database like Postgres nor a key value store like Redis.
We can implement it in Elixir using GenServer:

```elixir
defmodule Alcmaeon.Script do
  use GenServer

  @initial %{root: [children: []]}
  @name Alcmaeon.Script

  def start_link(opts) do
    GenServer.start_link(
      __MODULE__,
      Keyword.get(opts, :initial, @initial),
      name: Keyword.get(opts, :name, @name)
    )
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_cast({:add, parent, id, text}, state) do
    new_state =
      state
      |> Map.put(id, children: [], text: text)
      |> Map.update!(
        parent,
        &Keyword.update!(&1, :children, fn list ->
          [id | list] |> Enum.filter(fn child -> child == id || Map.has_key?(state, child) end)
        end)
      )

    PubSub.broadcast(Alcmaeon.PubSub, topic(), {:notes, new_state})
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:remove, id}, state) do
    # NOTE: Compaction in :add takes care of obsolete children. Is it sound?
    new_state = Map.delete(state, id)

    PubSub.broadcast(Alcmaeon.PubSub, topic(), {:notes, new_state})
    {:noreply, new_state}
  end
end
```

(<https://github.com/scoiatael/alcmaeon/blob/07606ab2dc1a39950b88045c4880576739bbf652/lib/alcmaeon/script.ex>)

- Mutations are implemented using casts, which are asynchronous and do not return a value.
- Tree of notes is kept in a flat hash map. It allows fast mutations but generates garbage and is not good for presentation.

## Presentation {#presentation}

Adding UI is pretty straightforward - all we need to add is a method for controllers to get data out of our Script.

```elixir
defmodule Alcmaeon.Script do
  @impl true
  def handle_call(:get, _from, state), do: {:reply, view(state), state}

  defp view(state), do: unfold(state, :root)[:children]

  defp unfold(state, id) do
    if Map.has_key?(state, id) do
      children = Keyword.get(state[id], :children, [])

      %{
        text: Keyword.get(state[id], :text),
        children: Enum.map(children, &unfold(state, &1)),
        id: id
      }
    else
      nil
    end
  end
end
```

Now we need to add feedback after adding or removing note. This can be done by broadcasting change after each mutation:

```elixir
defmodule Alcmaeon.Script do
  @impl true
  def handle_cast({:remove, id}, state) do
    # NOTE: Compaction in :add takes care of obsolete children. Is it sound?
    new_state = Map.delete(state, id)

    PubSub.broadcast(Alcmaeon.PubSub, topic(), {:notes, view(new_state)})
    {:noreply, new_state}
  end
end
```

(<https://github.com/scoiatael/alcmaeon/tree/09b0c881564b82678ed5dbc0e1e56472ae8fa9ef>)
Notice that computed tree is broadcasted - this saves work, as each client process gets ready to use value, but has some downsides, as we'll see later.

## Deployment {#deployment}

There are many options when it comes to deploying our application. Sadly not all platform-as-a-service providers support TCP connections between nodes required for Distributed Elixir to work. Let's use fly.io for this one. We can use [standard Phoenix Dockerfile](https://hexdocs.pm/phoenix/releases.html#containers), along with [custom libcluster strategy](https://github.com/scoiatael/alcmaeon/blob/master/lib/flyio%5Flibcluster/strategy.ex).
All we need is to adjust erlang OTP settings to support connecting to other nodes via IPv6 and enable private network in `fly.toml`:

```toml
[experimental]
private_network = true
```

## There can be only one {#there-can-be-only-one}

After scaling our deployment to multiple regions it's pretty obvious our application has a glaring bug. Each region has a separate database, but changes are broadcasted - so two users from different regions will fight over whose changes are visible. This is most likely <span class="underline">not</span> what we want.
We can fix it by making sure only one copy of database is running and that all writes are sent to it. As <https://jepsen.io/> proves it is not trivial in distributed scenario. For starters we can settle on static scenario: one node is designated as the primary. If it goes down permanently manual intervention is required.
We can use region to mark primary node on fly, but it's up to us to make sure there's only one node in primary region.

```elixir
defmodule Alcmaeon.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  def start(_type, _args) do
    children =
      [
        # Start the Ecto repository
        # Alcmaeon.Repo,
        # Start the Telemetry supervisor
        AlcmaeonWeb.Telemetry,
        # Start the PubSub system
        {Phoenix.PubSub, name: Alcmaeon.PubSub},
        # Start the Endpoint (http/https)
        AlcmaeonWeb.Endpoint,
        # Start a worker by calling: Alcmaeon.Worker.start_link(arg)
        FlyioLibcluster.Region,
        {Cluster.Supervisor,
         [
           Application.get_env(:libcluster, :topologies),
           [name: FlyioLibcluster.ClusterSupervisor]
         ]}
      ] ++ maybe_script() ++ [Alcmaeon.Stage]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Alcmaeon.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    AlcmaeonWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp maybe_script do
    if Application.get_env(:alcmaeon, :script_region) == FlyioLibcluster.Region.fly_region() do
      Logger.info("Application: starting Script as we are primary")
      [Alcmaeon.Script]
    else
      Logger.warn("Application: someone else is primary")
      []
    end
  end
end
```

Now we need to forward all writes to primary. This is pretty straightforward with `global` module.

```elixir
defmodule Alcmaeon.Script do
  @name {:global, Alcmaeon.Script}
end
```

(<https://github.com/scoiatael/alcmaeon/tree/f9928ff54e5df541abb2078d2aefa65ec4523226>)

## Read-only replicas {#read-only-replicas}

We've arrived at something comparable with using Redis.
All reads and writes go through single node.
By using the same broadcasting mechanism as before we can add streaming replication on all non-primary nodes.

```elixir
defmodule Alcmaeon.Stage do
  use GenServer
  require Logger

  alias Phoenix.PubSub

  @name Alcmaeon.Stage
  @script Alcmaeon.Script

  def start_link(opts) do
    GenServer.start_link(
      __MODULE__,
      nil,
      name: Keyword.get(opts, :name, @name)
    )
  end

  @impl true
  def init(_) do
    PubSub.subscribe(Alcmaeon.PubSub, Alcmaeon.Script.topic())

    {:ok, get_initial_state()}
  end

  @impl true
  def handle_info({:notes, notes}, _state) do
    {:noreply, notes}
  end

  @impl true
  def handle_call(:get, _from, :empty) do
    state = get_initial_state()

    {:reply, view(state), state}
  end

  @impl true
  def handle_call(:get, _from, state), do: {:reply, view(state), state}

  defp get_initial_state do
    {replies, bad_nodes} =
      GenServer.multi_call(Node.list([:this, :connected]), @script, :get, 4000)

    if Enum.empty?(replies) do
      Logger.warn("Stage: no primary state received; got bad replies from #{inspect(bad_nodes)}")
      :empty
    else
      Logger.info("Stage: received initial state: #{inspect(replies)}")
      [{_node, value} | _] = replies
      value
    end
  end

  def view(state), do: unfold(state, :root)[:children]

  defp unfold(state, id) do
    if Map.has_key?(state, id) do
      children = Keyword.get(state[id], :children, [])

      %{
        text: Keyword.get(state[id], :text),
        children: Enum.map(children, &unfold(state, &1)),
        id: id
      }
    else
      nil
    end
  end
end
```

## Never goes down {#never-goes-down}

This opens up a new possibility. Since we have a copy of state in remote nodes, we can query them when starting primary.
First, we have to modify replicas to keep a copy of real state, not tree used for presentation.

```elixir
defmodule Alcmaeon.Script do
  @impl true
  def handle_cast({:add, parent, id, text}, state) do
    new_state =
      state
      |> Map.put(id, children: [], text: text)
      |> Map.update!(
        parent,
        &Keyword.update!(&1, :children, fn list ->
          [id | list] |> Enum.filter(fn child -> child == id || Map.has_key?(state, child) end)
        end)
      )

    PubSub.broadcast(Alcmaeon.PubSub, topic(), {:notes, new_state})
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:remove, id}, state) do
    # NOTE: Compaction in :add takes care of obsolete children. Is it sound?
    new_state = Map.delete(state, id)

    PubSub.broadcast(Alcmaeon.PubSub, topic(), {:notes, new_state})
    {:noreply, new_state}
  end
end
```

And the last piece of puzzle

```elixir
defmodule Alcmaeon.Script do
  @impl true
  def init(initial_state) do
    # Required for multi_call in Stage.get_initial_state/0
    Process.register(self(), Alcmaeon.Script)

    {all_replies, bad_nodes} = GenServer.multi_call(Node.list(), Alcmaeon.Stage, :get, 5000)
    replies = Enum.filter(all_replies, fn {_, v} -> v != :empty end)

    state =
      if Enum.empty?(replies) do
        Logger.warn("""
        Script: no replica state received;
          got bad replies from #{inspect(bad_nodes)}
          and empty ones #{inspect(all_replies)}
        """)

        initial_state
      else
        Logger.info("Script: received initial state: #{inspect(replies)}")
        [{_node, value} | _] = replies
        value
      end

    {:ok, state}
  end
end
```

(<https://github.com/scoiatael/alcmaeon/tree/f9a76157d745308829dddde18cdbc9c77730094c>)

You can play with finished application on <https://floral-flower-8496.fly.dev>

## Here be dragons {#here-be-dragons}

Despite proving my point, the code is just proof of concept. Here are some points you might want to consider before running something similar on production.

### Distributed is a can of worms {#distributed-is-a-can-of-worms}

Most often your application con work just fine on single big box instead of two smaller - and it's easier to run this way.

### Databases are a thing for a reason {#databases-are-a-thing-for-a-reason}

Out of the box Postgres will scale better than your code. It also has more features than you can write in spare time and your product owner will thank you for not writing them when you could be writing "real" features.
