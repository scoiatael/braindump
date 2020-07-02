+++
title = "Things Puppet won't tell you about Deferred"
author = ["Lukasz Czaplinski"]
tags = ["puppet"]
categories = ["rants"]
draft = false
+++

You might've heard about one of Puppet 6's <span class="underline">fresh</span> features: [Deferred](https://puppet.com/docs/puppet/latest/deferring%5Ffunctions.html#deferred-function-example). It basically allows you to run code on agent during execution, instead of only on master during compilation.

It's awesome for many reasons; you can:

-   [retrieve secrets on agents](https://puppet.com/docs/puppet/latest/integrating%5Fsecrets%5Fand%5Fretrieving%5Fagent-side%5Fdata.html),
-   [implement lazy execution and macros](http://puppet-on-the-edge.blogspot.com/2018/10/the-topic-is-deferred.html),

But it has one big problem. Let me show what's wrong.


## Usage {#usage}

Try writing an example code with Deferred:

```puppet
# manifest.pp
$args = {
    now_on_master => new(TimeStamp),
    shadow_contents => Deferred('file', ['/etc/puppet_time.txt']),
}

file { "/etc/puppet_time.txt":
  content => inline_epp('compile time - <%= $now_on_master %>', $args)
}

file { "/etc/puppet_time_shadow.txt":
  content => Deferred('inline_epp', ['compile time - <%= $now_on_master %>, shadow: <%= $shadow_contents %>', $args]),
  require  => File['/etc/puppet_time.txt']
}
```

and run it with `puppet apply manifest.pp`.

Solution like this wouldn't be possible without `Deferred`: contents of 2nd file dynamically depend on things created by previous `file`.

Now, it can apply to any resources being created as side-effect of Puppet commands.


## Problem {#problem}

Now let's try integrating Deferred into some of our classes:

```puppet
class foo(
  String $bar,
  String $shadow,
) {
    file { "/etc/puppet_time.txt":
        content => $bar
    }

    file { "/etc/puppet_time_shadow.txt":
        content => $shadow,
        require  => File['/etc/puppet_time.txt']
    }
}

$args = {
    now_on_master => new(TimeStamp),
    shadow_contents => Deferred('file', ['/etc/puppet_time.txt']),
}

class { 'foo':
    bar => inline_epp('compile time - <%= $now_on_master %>', $args),
    shadow => Deferred('inline_epp', ['compile time - <%= $now_on_master %>, shadow: <%= $shadow_contents %>', $args]),
}
```

...and it breaks:

> Error: Evaluation Error: Error while evaluating a Resource Statement, Class[Foo]: parameter 'shadow' expects a String value, got Deferred (file: /srv/puppet/manifest2.pp, line: 20, column: 1) on node 5ff8d7eef4ad

Oops, looks like Deferred is a new data type, that's only briefly mentioned in the documentation, and suddenly all build-in resources know how to deal with it.

But not any of resources you build, nor anyone else. So you can't integrate it with any of your code, can you?


## Solution? {#solution}

Thankfully, there's a solution to that problem: `call` function. It'll evaluate `Deferred` before it's passed to your class:

```puppet
class foo(
  String $bar,
  String $shadow,
) {
    file { "/etc/puppet_time.txt":
        content => $bar
    }

    file { "/etc/puppet_time_shadow.txt":
        content => $shadow,
        require  => File['/etc/puppet_time.txt']
    }
}

$args = {
    now_on_master => new(TimeStamp),
    shadow_contents => Deferred('file', ['/etc/puppet_time.txt']),
}

class { 'foo':
    bar => inline_epp('compile time - <%= $now_on_master %>', $args),
    shadow => call(Deferred('inline_epp', ['compile time - <%= $now_on_master %>, shadow: <%= $shadow_contents %>', $args])),
}
```

But we are back at square one: `call` will execute code **during compilation**. So any benefits granted to us by `Deferred` are lost and this code doesn't work:

> Error: Evaluation Error: Error while evaluating a Function Call, Could not find any files from /etc/puppet\_time.txt (file: /srv/puppet/manifest3.pp, line: 22, column: 15) on node 5ff8d7eef4ad
