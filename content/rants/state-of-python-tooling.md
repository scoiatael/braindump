+++
title = "State of Python tooling"
date = 2020-01-19T21:39:00+01:00
tags = ["python"]
categories = ["rants"]
draft = false
+++

Recently I joined a team working mostly in Python. As usual, one of the first steps is getting development environment for the projects up and running.
The first part was quick and easy: download a couple of config files & secrets, `docker-compose up` and we are up and running.

Then came the hard part: getting local Python environment running for tests and code-completion.


## Preface {#preface}

I'm a big fan of [direnv](https://github.com/direnv/direnv) - having single `.envrc` file with all the environment variables and tool setup, shared by both terminal and editor is awesome.
You can even create `envrc.template` and simple instructions for fellow developers on how to obtain missing values. This allows quite painless onboarding and migration between tool versions.
Direnv also allows defining layouts for various programming languages - allowing easy setup of things like specific [Node](https://github.com/direnv/direnv/wiki/Node) or [Ruby](https://github.com/direnv/direnv/wiki/Ruby) versions.

This works quite well with ability to define different lists of dependencies for production & development/testing - via [Bundler groups](https://bundler.io/v1.12/groups.html) or [npm's devDependencies](https://docs.npmjs.com/specifying-dependencies-and-devdependencies-in-a-package-json-file).
As a new developer fill out `.envrc`, run `bundle install` and you are good to go.


## So what's wrong with Python? {#so-what-s-wrong-with-python}

Well, I remember learning about `virtualenv` at one point in 2014 and being in awe with what it brought to table: real isolation of dependencies between projects, (almost) fully automated.
All you had to do is `source venv/bin/activate && pip install -r requirements.txt` and start coding.

Fast forward to 2020 and somehow the same flow doesn't feel so good anymore. Why?

-   What is your Python version? What should it be? Which one is used on production? Which one will users of your library use?
-   Are you using private repository for Python packages? How are you authenticating?
-   What dependencies are needed for production setup? Which ones only for testing? And moreover, how do you update them?


## Possible solutions {#possible-solutions}

Over the years, couple of solutions started to grow. When setting up the project I tried the following:


### [venv/virtualenv](https://docs.python.org/3/library/venv.html) {#venv-virtualenv}

Virtualenv approach became popular enough for it to become part of stdlib in 3.3. Finally times of `pip install --user virtualenv && virtualenv venv && source venv/bin/activate && pip install -r requirements.txt` are over.

But it didn't evolve: it isolates dependencies for given project, but doesn't try to solve any other issues. While this is a good philosophy for a library, this means we need some extra layer to take care of Python versions, dependencies, etc.


### [pyenv](https://github.com/pyenv/pyenv) {#pyenv}

Pyenv aims to organize maintenance of several Python versions on one machine. It's based on [a Ruby counterpart](https://github.com/rbenv/rbenv) and therefore quite battle-tested.

Similar to `venv`, it solves just one thing and does it well. The downside is, you again have to coordinate tools on your own.
There are a couple of ways to achieve [the direnv integration](https://github.com/direnv/direnv/wiki/Python#pyenv), each with its own set of problems.
For tools like [tox](https://tox.readthedocs.io/en/latest/) to work, `pyenv` supports having multiple python versions enabled at the same time.
Now how should `virtualenv` behave? Do you want a separate env for each Python? Or just one, and let `tox` manage the rest?

There's also one more thing to consider: how do you manage development tools for each version? Do you want `black` or `flake8` installed for each version?

In the end I gave up on setting up `tox` in the project. I'll be running tests under just one Python and let CI test on different ones.


### [pipenv](https://github.com/pypa/pipenv) {#pipenv}

To answer some of the issues, a new project was created. One that was supposed to implement for Python what `bundler` does for Ruby.

Sadly, it looks weird: last release happened [over a year ago](https://github.com/pypa/pipenv/releases/tag/v2018.11.26), Google search for docs point over to [a fork(?)](https://pipenv-fork.readthedocs.io/en/latest/) instead of [the official ones](https://pipenv.kennethreitz.org/en/latest/), there are [weird rumors](https://github.com/pypa/pipenv/issues/4058) in the community.
Now, this wouldn't be <span class="underline">that</span> bad, if the project was mature and feature-complete - meaning I could trust it and start porting over project to it.

Sadly, that wasn't the case for me - most likely due to me not understanding `pip` enough - but that means there will be more issues down the road.
The specific problem I failed to overcome was using private repository for some packages when installing current package.
It'd either try to pull all packages from it (as if pip `--index-url` flag was set), or fail to use it at all.
That'd mean having to migrate all packages we were using to Pip at once, instead of doing it incrementally. A deal breaker for me.


### [poetry](https://python-poetry.org/) {#poetry}

Quite ironically, I noticed this project being advertised on one of `pipenv` Github issues.
It's promise is to be

> a single tool to manage my Python projects from start to finish.

It also pokes at `pip`'s issues with dependency resolution.

The only problem is that it uses its own Toml configuration file - meaning, again, having to port over all of our packages to this one tool.
Maybe at some point this effort will be worth it; certainly not as a part of setting it up for a single developer.


### [asdf](https://asdf-vm.com/#/) {#asdf}

In the end, I was committed to using `pyenv` + `pyenv-virtualenv` plugin with one of the more magical setups from `direnv`.
I remembered one more tool that came handy when working with Elixir: `asdf`.
It's a generalized version manager, supporting multiple languages.
It has both [a direnv plugin](https://github.com/asdf-community/asdf-direnv) and [python one](https://github.com/danhper/asdf-python), meaning most of the heavy lifting is already done.

In the end, my `.envrc` looks as following:

```shell
use asdf python 3.8.1
layout python
```

and achieves _almost_ what it was supposed to do; only victim was `tox` and testing for multiple Python versions.
