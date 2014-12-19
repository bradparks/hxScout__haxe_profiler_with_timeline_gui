package;

import sys.net.Socket;
import amf.io.Amf3Reader;
import cpp.vm.Thread;
import haxe.io.*;
import haxe.ds.StringMap;

typedef Timing = {
  var delta:Int;
  var span:Int;
  var self_time:Int;
  var prev:Timing;
}


class FLMListener {

  static private var next_inst_id:Int = 0;
  static public function start()
  {
    var client_writer = Thread.readMessage(true);

    trace("Starting FLM listener...");
    var s = new Socket();
    s.bind(new sys.net.Host("0.0.0.0"),7934); // Default Scout port
    s.listen(8);

    trace("Waiting for FLM on 7934...");
    var flm_socket : Socket = s.accept();
    var inst_id:Int = (next_inst_id++);

    // Launch next listener
    s.close();
    var listener = Thread.create(FLMListener.start);
    listener.sendMessage(client_writer);

    trace("Starting FLMReader["+inst_id+"]...");

    var frames:Array<Frame> = [];
    var cur_frame = new Frame(0, inst_id);
    var delta:Int = 0;
    var first_enter = true;
    var next_is_as = false;
    var stack_strings:Array<String> = ["1-indexed"];

    var r = new Amf3Reader(flm_socket.input);
    var connected = true;
    while( connected ) {

      // Read next event blob.
      var data:Map<String, Dynamic> = null;
      try {
        data = r.read();
      } catch( e:Dynamic) {
        // Handle EOF gracefully
        if (Type.getClass(e)==haxe.io.Eof) {
          trace("FLMReader["+inst_id+"] closing...");
          connected = false;
          flm_socket.close();
          trace("TODO: do we need to kill this thread somehow? Should be no external references...");
          break;
        }
        // Handle flash requests for policy file
        if ((e+"").indexOf("type-marker: 60")>0) {
          trace("Got flash policy file request, writing response...");
          flm_socket.input.readUntil(0);
          FLMUtil.send_policy_file(cast(flm_socket));
          break;
        }
        // Other errors, rethrow
        trace("Uh oh, rethrowing: "+e);
        throw e;
      }

      if (data!=null) {
        //trace(data);
        var name:String = cast(data['name'], String);

        //if (name.indexOf('::')>0) {
        //  //trace(data);
        //  //trace(" -- Stack:");
        //  //trace(data['name']);
        //  //trace(Type.getClass(data['name']));
        //  //trace(Reflect.fields(data['name']));
        // 
        //  var bytes = haxe.io.Bytes.ofString(data["name"]);
        //  var msg = "";
        //  for (i in 0...bytes.length) {
        //    var b = bytes.get(i);
        //    if (b>=32 && b<=126) msg += String.fromCharCode(b); else msg += "%"+StringTools.hex(b, 2);
        //  }
        //  trace(msg);
        //}

        if (name=='.swf.name') {
          client_writer.sendMessage(haxe.Json.stringify({session_name:data['value'], inst_id:inst_id}));
        }

        // - - - - - - - - - - - -
        // Timing / Span / Delta
        // - - - - - - - - - - - -
        if (data['delta']!=null) {
          // Delta without a span implies span = 0 ?
          var t:Timing = { delta:data['delta'], span:data['span']==null?0:data['span'], prev:null, self_time:0 };

          cur_frame.duration.total += t.delta;

          if (t.span>cur_frame.duration.total) {
            if (name!='.network.localconnection.idle' &&
                name!='.rend.screen') {
              trace("??? Event larger ("+t.span+") than current frame ("+cur_frame.duration.total+"): "+data);
            }
          }

          var self_time = t.span;
          var lookback = t.span-t.delta;
          //trace("- Considering: "+data+", self="+self_time+", lookback="+lookback+" -- t="+t);
          var tref:Timing = cur_frame.timing;
          while (lookback>0 && tref!=null) {
            if (lookback>=tref.delta) {
              self_time -= tref.delta;
            } else if (lookback>=tref.span) {
              self_time -= tref.span;
            } else {
              //trace("	 -- does not include ("+tref.delta+"), dropping lookback to "+(lookback-tref.delta));
            }
            lookback -= tref.delta;
            tref = tref.prev;
          }
          t.prev = cur_frame.timing;
          t.self_time = self_time;
          cur_frame.timing = t;

          //trace("	 -- Final self time: "+self_time);
          if (self_time<0) throw "Umm, can't have negative self time!!";

          //trace("	 -- "+name+": "+self_time);

          //if (next_is_as) trace("next_is_as on: "+name);

          if (next_is_as || name.indexOf(".as.")==0) cur_frame.duration.as += self_time;
          else if (name.indexOf(".gc.")==0) cur_frame.duration.gc += self_time;
          else if (name.indexOf(".exit")==0) cur_frame.duration.other += self_time;
          else if (name.indexOf(".rend.")==0) cur_frame.duration.rend += self_time;
          else if (name.indexOf(".swf.")==0) cur_frame.duration.other += self_time;
          else if (name.indexOf(".network.")==0) cur_frame.duration.net += self_time;
          else {
            cur_frame.duration.other += self_time;
            cur_frame.duration.unknown += self_time;
#if DEBUG_UNKNOWN
            var debug:String = data['name']+":"+self_time;
            cur_frame.unknown_names.push(debug);
#end
            //if (cur_frame.unknown_names.indexOf(data['name'])<0) cur_frame.unknown_names.push(data['name']);
          }

          // not sure should do it this way, maybe a list of event names instead?
          next_is_as = name=='.as.event';

        } else {
          // Span shouldn't occur without a delta
          if (data['span']!=null) throw( "Span without a delta on: "+data);
        }

        // - - - - - - - - - - - -
        // Memory summary
        // - - - - - - - - - - - -
        if (name.indexOf(".mem.")==0 && data["value"]!=null) {
          var type:String = name.substr(5);
          //if (cur_frame.mem[type]==null) cur_frame.mem[type] = 0;
          cur_frame.mem[type] = data["value"];
        }

        // - - - - - - - - - - - -
        // CPU
        // - - - - - - - - - - - -
        if (name.indexOf(".player.cpu")==0) {
          cur_frame.cpu = data["value"];
        }

        // - - - - - - - - - - - -
        // Object allocations
        // - - - - - - - - - - - -
        if (name.indexOf(".memory.")==0) {
          var type:String = name.substr(8);

          if (type=="stackIdMap") {
            var maps:Array<Int> = data["value"]; // len, val, val, val, len, val, ...
            if (cur_frame.push_stack_maps==null) cur_frame.push_stack_maps = new Array<Array<Int>>();
            //trace("Push maps: "+maps);
            var len = maps[0];
            cur_frame.push_stack_maps.push(new Array<Int>());
            for (i in 1...maps.length) {
              if (len-- == 0) {
                len = maps[i];
                cur_frame.push_stack_maps.push(new Array<Int>());
              } else {
                cur_frame.push_stack_maps[cur_frame.push_stack_maps.length-1].push(maps[i]);
              }
            }
            //trace(cur_frame.push_stack_maps);
          } else {
            // newObject, deleteObject, updateObject
            if (!cur_frame.alloc.exists(type)) cur_frame.alloc.set(type, new Array<Dynamic>());
            cur_frame.alloc.get(type).push(data["value"]);
          }
        }

        // - - - - - - - - - - - -
        // Sampler
        // - - - - - - - - - - - -
        if (name.indexOf(".sampler.")==0) {
          if (name==".sampler.methodNameMap") {
            if (cur_frame.push_stack_strings==null) cur_frame.push_stack_strings = [];
            var bytes = cast(data["value"], haxe.io.Bytes);
            var start=0;
            for (i in 0...bytes.length) {
              var b = bytes.get(i);
              if (b==0) {
                var stack_string:String = bytes.getString(start, i-start);
                cur_frame.push_stack_strings.push(stack_string);
                stack_strings.push(stack_string);
                start = i+1;
              }
            }
            //trace("Frame "+cur_frame.inst_id+", Stack strings now: "+stack_strings.length);
            //for (i in 0...stack_strings.length) {
            //  trace(i+": "+stack_strings[i]);
            //}
          }
          else if (name==".sampler.sample") {
            var value:Map<String,Dynamic> = data["value"];
            if (cur_frame.samples==null) cur_frame.samples = [];
            cur_frame.samples.push(value);
            //trace(value);
          }
        }

        if (data['name']==".enter") {
          if (first_enter) {
            first_enter = false;
          } else {
            var offset = cur_frame.offset + cur_frame.duration.total;
            cur_frame.timing = null; // release timing events
            //Sys.stdout().writeString(cur_frame.to_json()+",\n");
            client_writer.sendMessage(cur_frame.to_json());
            frames.push(cur_frame);
            cur_frame = new Frame(cur_frame.id+1, inst_id, offset);
          }
        }
      }
    }
  }
}

class Frame {
  public var inst_id:Int;
  public var id:Int;
  public var offset:Int;
  public var duration:Dynamic;
  public var mem:Map<String, Int>;
  public var samples:Array<Dynamic>;
  public var push_stack_strings:Array<String>;
  public var push_stack_maps:Array<Array<Int>>;
  public var cpu:Float;
  public var alloc:StringMap<Array<Dynamic>>;
  //public var events:Array<Dynamic>;
#if DEBUG_UNKNOWN
  public var unknown_names:Array<String>;
#end
  public var timing:Timing;

  public function new(frame_id:Int, instance_id:Int, offset:Int=0) {
    inst_id = instance_id;
    id = frame_id;
    this.offset = offset;
    duration = {};
    duration.total = 0;
    duration.as = 0;
    duration.gc = 0;
    duration.other = 0;
    duration.net = 0;
    duration.rend = 0;
    duration.swf = 0;
    duration.unknown = 0;
    mem = new Map<String, Int>();
    samples = null;
    push_stack_strings = null;
    push_stack_maps = null;
    cpu = 0;
    alloc = new StringMap<Array<Dynamic>>();
#if DEBUG_UNKNOWN
    unknown_names = [];
#end
  }

  public function to_json():String
  {
    return haxe.Json.stringify({
      id:id,
      inst_id:inst_id,
      offset:offset,
#if DEBUG_UNKNOWN
      unknown_names:unknown_names,
#end
      duration:duration,
      push_stack_strings:push_stack_strings,
      push_stack_maps:push_stack_maps,
      samples:samples,
      alloc:alloc,
      cpu:cpu,
      mem:mem
    });
  }
}

// Naming Notes (in Activity Sequence):
// {"name":".player.abcdecode"} --> Preparing ActionScript ByteCode
// {"name":".network.loadmovie","value":"app:/Main.swf"} --> Loading SWF: app:/Main.swf

