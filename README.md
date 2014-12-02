hxScout
=======

A Haxe Scout Alternative

[<img src="https://raw.githubusercontent.com/jcward/hxScout/master/hxscout.png" width=240>](https://raw.githubusercontent.com/jcward/hxScout/master/hxscout.png)

What
----
hxScout aims to be a free, cross-platform alternative to [Adobe Scout](http://wwwimages.adobe.com/content/dam/Adobe/en/devnet/flashruntimes/adobe-scout-getting-started/adobe-scout-getting-started-fig10.png) providing
much the same capability - that is, it will display telemetry, debug, and memory
usage data from a Flash Player runtime.

Why?
----
Because Adobe Scout is limited to Windows or OSX and requires a CC account,
and I'm a linux and OSS fan.  Well, and I wanted a project to play with Haxe and OpenFL. :)

Status
------

Alpha / heavy development - hxscout basically works, displaying limited telemetry data in a manner
similar to Adobe Scout, though with far fewer features. There is a client and a server project and a
number of FLM utilities and test cases.

The server is a vanilla Haxe project that receives telemetry (aka FLM) data on port 7934 from Flash/AIR,
processes it some, and passes frame data to the client app over another socket.

The client is an OpenFL project that attaches to a server, and receives and displays telemetry
data.  When built for CPP the client includes a server thread, so it operates just like the
Scout app.  When built for Flash/Neko, the client attaches to a server thread.

Currently frame timing data, memory usage, and the sampling profiler data are pretty well figured out.
The hxScout client GUI is functional but lacks many features, as seen in the screenshots on this page.

# ![hxScout client alpha](https://raw.githubusercontent.com/jcward/hxScout/master/src/client/hxscout.gif)

There are a number of utilities in the [util directory](https://github.com/jcward/hxScout/tree/master/util)
for capturing, storing, piping, and converting FLM data to readable text. Some may only work in Linux (or if
you have netcat installed.)

Progress / Goal
---------------

See my list of issues to get a glimpse of what's on my radar and what I'm working on. My goal is to create a
basic free profiling tool, so I likely won't get to things like Stage3D debugging.

FLM Exploration
---------------

I've setup a number of [flm_exploration](https://github.com/jcward/hxScout/tree/master/flm_exploration) testcases that run various AS3 AIR app tests, capturing the .flm output with a variety of telemetry configuration options (basic, sampler, cpu, allocations, etc). These allow me to poke at the FLM format, and try to figure out what various telemetry messages mean. I can also open the .flm files in Scout to help.

TODO / Help
-----------
Feel free to fork this project, tinker, file issues, or contact me ([@jeff__ward](https://twitter.com/jeff__ward) or various social links at [jcward.com](http://jcward.com/)) if you can help.

Resources
---------

Adobe Dev Articles:

http://www.adobe.com/devnet/scout/articles/adobe-scout-getting-started.html
http://www.adobe.com/devnet/scout/articles/adobe-scout-data.html
http://www.adobe.com/devnet/scout/articles/adobe-scout-custom-telemetry.html

https://github.com/claus/Pfadfinder - Claus Wahlers' similar project

http://renaun.com/blog/2012/12/enable-advanced-telemetry-on-flex-or-old-swfs-with-swf-scount-enabler/ - Renaun's AIR app to enable telemetry tag in SWFs

Haxe and OpenFL API docs:

http://api.haxe.org/
http://www.openfl.org/documentation/api/
