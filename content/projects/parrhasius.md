+++
title = "Parrhasius"
date = 2020-01-06T17:38:00+01:00
tags = ["ruby", "go"]
categories = ["projects"]
draft = false
featured_image = "https://camo.githubusercontent.com/8f3c61ee4eb28f12c7e0ad935906ce41831ef785/68747470733a2f2f646c2e64726f70626f782e636f6d2f732f676f76637a6564756b78676b6f6e782f323031392d31322d30352d3134313633315f3139323078313038305f7363726f742e706e67"
+++

One day I found myself scrolling through [internet best source of wallpapers](https://4chan.org/wg) and found myself wishing for something to mass-download a whole thread.
Without a proper google search even, decided to write something on my own. Presto! A new project.


## Part 1: Good beginnings {#part-1-good-beginnings}

The basic part is easy enough: use [Nokogiri](https://nokogiri.org/) in Ruby to parse site HTML, extract image URLs:

```ruby
html = Nokogiri(open(link).read)

html.search('a')
  .select { |l|
  l.children.size == 1 &&
    l.children.first.to_s.match(/.*(jpg|png)$/)
}
```

and then download them:

```ruby
img_link = link.attributes['href']
File.write(
  SecureRandom.uuid + ext(img_link.value),
  open('https:' + img_link.value).read
)
```


## Part 2: Bad hashing {#part-2-bad-hashing}

Soon enough, the first problem becomes apparent: lots of these images are duplicates of one another.
Long story short, it's best to use some image hashing algorithm that takes similarities into account - as some might be duplicates, but transformed (e.g. converted from jpeg to png back and forth, cropped, resized...).

Initially, I tried to simply "normalize" images by converting to lowest quality level and then hashing resulting binary. Not only was this approach not very accurate, but very CPU-intensive. Even when using [concurrent-ruby](https://github.com/ruby-concurrency/concurrent-ruby) and all CPUs available, hashing was the slowest part of the process.
My second attempt used pure Golang and tried to hash image using histograms. This too, wasn't very accurate - but a lot faster.

After more research I stumbled upon [DHash](http://www.hackerfactor.com/blog/?/archives/529-Kind-of-Like-That.html).
Since I already had a support for calling Go I decided to use an implementation in this language: <https://github.com/devedge/imagehash>.

```go
src, err := imagehash.OpenImg(filename)
if err != nil {
  return "", err
}
hash, err := imagehash.Dhash(src, 8)

if err != nil {
  return "", err
}
return hex.EncodeToString(hash), nil
```


## Part 3: Ugly glue {#part-3-ugly-glue}

The ugliest part was calling external binary to calculate the hash. At one point I stumbled upon [Gist describing Ruby-Go glue](https://gist.github.com/schweigert/385cd8e2267140674b6c4818d8f0c373). This turned out to be a pretty simple task, with only one caveat: error handling.

Golang convention is to pass possible error as 2nd return value:

```go
type cstring *C.char

//export ExtHash
func ExtHash(filename cstring) (cstring, cstring)
```

This proves to be quite hard to decipher from Ruby unless you read [FFI docs](https://github.com/ffi/ffi) quite closely. If you don't, the following Ruby definition allows calling and checking for errors properly:

```ruby
class ExtHashReturn < FFI::Struct
  layout :value, :string,
         :error, :string
end

attach_function :ExtHash, [:string], ExtHashReturn.by_value
```


## Part 4: Bonus {#part-4-bonus}

Having the images downloaded and deduplicated, only one thing remains: browsing through them. This requires 2 things: having thumbnails generated and some simple GUI to show them (and link to original).
Former is easy with [minimagick](https://github.com/minimagick/minimagick):

```ruby
image = MiniMagick::Image.open(f.realpath)
image.resize '256x256'
image.write([dest, f.basename].join('/'))
```

and the latter can be quite simple with [React Photo Gallery](http://neptunian.github.io/react-photo-gallery/), [React Infinite Scroller](https://github.com/CassetteRocks/react-infinite-scroller#readme) and [React Simple Img](https://react-simple-img.now.sh/). This part still requires some cleanup (and maybe Redux), so I'll delay posting code until then.

Source code: <https://github.com/scoiatael/parrhasius><br />
