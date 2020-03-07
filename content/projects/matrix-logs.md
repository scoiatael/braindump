+++
title = "Idea: matrix log analyzer"
author = ["Lukasz Czaplinski"]
date = 2020-03-07T12:58:00+01:00
tags = ["monitoring"]
categories = ["projects"]
draft = false
featured_image = "https://raw.githubusercontent.com/wiki/akinomyoga/cxxmatrix/images/cxxmatrix-version01sA.gif"
+++

Recently I came upon an interesting project: [cxxmatrix](https://github.com/akinomyoga/cxxmatrix). It creates matrix-like animations
in your terminal. This prompted a train of thought: it's neat, but in the movie
it had a purpose. It was used like a `tail -f /var/log/messages`: a real-time
glimpse into what's currently happening inside the Matrix.

Can we somehow make it a _useful_ reality? My latest PITA has been exactly that:
looking into trails of logs in order to find patterns.

My debug flow consists more or less of:

-   Looking for new exceptions in tracker (like Sentry),
-   Reacting to alerts based on pre-defined checks,
-   Using metrics (Grafana, Influxdb) to understand current situation,
-   Grepping through logs on affected hosts to see more details of the situation,

The last step is one that could possibly benefit from a big improvement.


## Idea {#idea}

Ok, so what would be the solution?

Something that ingests logs much like `tail` or `grep`: through `stdin` or text file.
It then goes through them in real time and learns patterns, while outputting
current state.
I'd envision it consisting of 2 parts:

-   known patterns (list, along with simple statistics),
-   output buffer (essentially parsed and colorized input based on patterns)


## Algorithm {#algorithm}

Inputs is a stream of logs.
Output is, for each log line, currently known patterns and whether this line
matches any pattern.

State update should reasonably keep amount of used memory bounded by some upper
constant, so it has to make a decision which log lines should be kept to try and
match with future ones. For a good starting point, it could be pre-seeded with
some known patterns by operator.

A pattern could be represented as a "string of strings", with wildcards in
between. Each wildcard should match exactly one character. This way we can
quickly compare string to a pattern seeing how many characters match.

Current state is a list of patterns, along with hit count for each of them. We
should also keep a total number of lines seen in order to implement pattern
eviction.


## Possible problems {#possible-problems}

-   Multi-line logs. Certain loggers output multiple lines for one problem (e.g.
    stacktraces). Our implementation could coalesce logs based on timestamp -
    meaning we'd need to make some assumptions about input.
-   Output speed. In case of reading from file (or being fed one via `cat` or
    `grep`) it's possible that output would go too fast for a human to analyze. To
    solve this use-case we could either implement:
    -   slowing down input based on timestamps,
    -   paging - `less` style,
    -   non-interactive output - first analyze and spit out patterns, later allow
        operator to decide which patterns should be ignored. This requires us to
        make decisions in a deterministic fashion instead of using `rand` to help
        eviction strategy.


## Usability notes {#usability-notes}

Two distinct use-cases: online and offline. Online one would be easier to
implement first.

Essentially a TUI, `htop`-like.

Nice to have: state save and load, in order to later start with pre-seeded patterns.

Requires deterministic eviction strategy (maybe we could make a decision based
on `rand` seed being current input hash?).

Nice to have: simple charts for patterns [termgraph](https://github.com/mkaz/termgraph)-style.


## Implementation notes {#implementation-notes}


### Language {#language}

I'd envision Rust. Python/Ruby lose on the requirement to be speedy (real-time
ideally). Erlang/Elixir doesn't really work for CLIs. Go would be a nice choice,
but I shudder at the thought of implementing even semi-complex algorithm using
`interface{}`.


## Alternatives and inspirations {#alternatives-and-inspirations}

-   [goaccess](https://goaccess.io) - neat, looks like it uses a know set of patterns to apply to text,
-   termgraph, cxxmatrix, as mentioned,
-   [grok](https://www.elastic.co/guide/en/logstash/current/plugins-filters-grok.html) - my previous go-to tool for understanding logs,
-   various closed-source ones - I believe each service has their own way of doing
    it. I kinda enjoyed [Datadog](https://docs.datadoghq.com/logs/processing/processors/?tab=ui#grok-parser) in that matter.
-   [mtail](https://github.com/google/mtail) - a solution I looked into to solve exactly that problem. Sadly requires
    upfront definition of parsing rules.
