hxScout
=======

A free, cross-platform and open source alternative to Adobe Scout, hxScout is a profiling tool for SWF (and soon Haxe*) applications that displays frame timing, memory usage, and profiling information.

Visit [hxscout.com](http://hxscout.com) to download for Windows, OSX, or Linux.

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

Beta - hxscout basically works, displaying some telemetry data in a manner similar to Adobe Scout,
though with far fewer features at the moment. hxScout displays timing, profiling and memory allocation data. hxScout does not support rendering or Stage3D profiling, and it doesn't currently have all the UI options that Scout does (sorting information, top-down and bottom-up options, customizable panes, etc.)

The goal is not to replicate every feature of Scout, but to provide a tool that supports the highest ROI profiling functions, free for all developers on all platforms, that supports the Flash Platform and beyond.

Details
-------

hxScout code is organized as a server app/thread and a client app/thread.

The server is a vanilla Haxe project that receives telemetry (aka FLM) data on port 7934 from Flash/AIR,
processes it some, and passes frame data to the client app over another socket.

The client is an OpenFL project that attaches to the server thread, and displays the telemetry
data in a GUI.  When built for CPP the client includes a server thread, so it operates just like the
Scout app.  When built for Flash/Neko (semi-working), the client attaches to a separate standalone server app.

Currently frame timing data, memory usage, and the sampling profiler data are pretty well figured out.
Object allocation telemetry is basically working in progress. None yet support the various modes of
display such as top down / bottom up.

There are a number of utilities in the [util directory](https://github.com/jcward/hxScout/tree/master/util)
for capturing, storing, piping, and converting FLM data to readable text. Some may only work in Linux (or if
you have netcat installed on OSX.)

Progress / Goal
---------------

See my list of issues to get a glimpse of what's on my radar and what I'm working on.

FLM Exploration
---------------

I've setup a number of [flm_exploration](https://github.com/jcward/hxScout/tree/master/flm_exploration) testcases that run various AS3 AIR app tests, capturing the .flm output with a variety of telemetry configuration options (basic, sampler, cpu, allocations, etc). These allow me to poke at the FLM format, and try to figure out what various telemetry messages mean. I can also open the .flm files in Scout to compare with hxScout.

# ![hxScout client alpha](https://raw.githubusercontent.com/jcward/hxScout/master/hxscout.gif)

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
