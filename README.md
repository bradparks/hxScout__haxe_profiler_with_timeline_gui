hxScout
=======

A Haxe Scout Alternative

What
----
hxScout aims to be a free, cross-platform alternative to Adobe Scout providing
much the same capability - that is, it will display telemetry, debug, and memory
usage data from a Flash Player runtime.

Why?
----
Because Adobe Scout is limited to Windows or OSX and requires a CC account,
and I'm a linux and OSS fan.

Status
------

Early-alpha - there is currently a client and a server project (as well as a separate
tool for simply dumping trace statements.) Telemetry data is piped all the way through
the apps and displayed in a rudimentary GUI.

The server is a vanilla Haxe project that receives telemetry (aka FLM) data on port 7934 from Flash/AIR,
processes it some, and passes frame data to the client app over another socket.

The client is an OpenFL project that attaches to a server, and receives and displays telemetry
data.  When built for CPP automatically starts a server thread, so it operates just like the
Scout app.

Currently frame timing data is pretty well figured out. Memory usage is mostly figured out. The AS3
sampler data is in-progress and will require some processing on the client side. The hxScout GUI
is a functional-but-not-yet-actually-usable prototype as seen below:

# ![hxScout client alpha](https://raw.githubusercontent.com/jcward/hxScout/master/src/client/hxscout.gif)

There are a number of utilities in the [util directory](https://github.com/jcward/hxScout/tree/master/util) for capturing, storing, piping, and converting
FLM data to readable text. Some may only work in Linux (or if you have netcat installed.)

Goal / Vision
-------------
The idea is to have the Haxe server read the Scout telemetry data stream,
store stateful data, and deliver that data to an OpenFL-based GUI.

FLM Exploration
---------------

I've also setup a number of [flm_exploration](https://github.com/jcward/hxScout/tree/master/flm_exploration) testcases
that run various AS3 AIR app tests, capturing the .flm output with a variety of telemetry
configuration options (basic, sampler, cpu, allocations, etc).

I've piped [a testcase](https://github.com/jcward/hxScout/tree/master/flm_exploration/test_wastealloc) output through the Server.hx to create a summary of
frames timing and memory usage, and I've hard-coded the output frame duration data into a now-retired [prototype web client
view](https://github.com/jcward/hxScout/tree/master/src/client/legacy) just for a visual sanity check.

TODO / Help
-----------
Figure out what all the telemetry info means so we can display useful
info similar to [Adobe Scout](http://wwwimages.adobe.com/content/dam/Adobe/en/devnet/flashruntimes/adobe-scout-getting-started/adobe-scout-getting-started-fig10.png).  Feel free to fork this project, tinker, file issues, 
or contact me ([@jeff__ward](https://twitter.com/jeff__ward) or various social links at [jcward.com](http://jcward.com/)) if you can help.

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
