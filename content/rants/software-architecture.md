+++
title = "Software architecture"
date = 2020-01-07T14:46:00+01:00
tags = ["architecture"]
categories = ["rants"]
draft = false
+++

Recently I began to wonder why is building software _that_ interesting?
I quite enjoy computer and tabletop games, and somehow simply building software seems to be at least as challenging and in turn rewarding.


## The obvious answer: joy of creation {#the-obvious-answer-joy-of-creation}

Though I haven't done any research in that area, I'm quite sure that in general people like creating - and by that expressing themselves, and losing themselves in the process.
It seems a bit far-fetched to compare painting to writing code. But there is certainly a strong component of that in joy of development.
The problem is, it doesn't describe the challenge.


## Obvious parallel: <span class="underline">real</span> architecture {#obvious-parallel-architecture}

Let's compare software to a better known real-world profession. One that's even in the name of the challenge: architecture.
(Please excuse my simplified view on building houses, I'm quite sure there's more to it and alternative versions.)

There are 3 major phases: project, construction and finishing.
Major decisions are done in the first phase.
There is a process to ensure project is sound. There is a design language that makes plan as unambiguous as possible.

And that's how it was done at the beginning with software: design, write, installation.
But it turned out to be create broken products: either not fitting the client needs, getting too expensive to create or unmaintainable.

Turns out there is a real risk of missing the goal when going this way with software.
Hence all the Lean / Agile methodologies, Dev/Ops philosophies and a lot of good practices.
A lot has been written on this point, so let's go in different direction: how it affects decisions being made during development process?

In my experience, there are at least two viewpoints one has to keep in mind when programming:

1.  The system and its future
    How will what I'm writing evolve? What are the options I'm keeping open to tackle future challenges?
2.  Current set of abstractions
    What this part needs to accomplish? How do I ensure it does what it should? Can I prevent it breaking in the future?

This seems vaguely similar: one has to win current battle while still winning the whole war.


## Development: Total War {#development-total-war}

These concepts already have their names: strategy and tactics.
And so it seems the best parallel for programming might be battle games.
Weird conclusion, but one that certainly explains the satisfaction coming from it.
The fact that the challenge you solved wasn't described in terms of math task or campaign objective doesn't mean it wasn't as hard.

And most likely the cognitive path you had to go through was quite similar - maybe you simply didn't realize it.
