package;

import sys.net.Socket;
import amf.io.Amf3Reader;
import cpp.vm.Thread;
import haxe.io.*;
import haxe.ds.StringMap;
import haxe.ds.IntMap;

class ActivityData {
  public var self_time:Int;
  public var total_time:Int;
  public var count:Int;
  public var children:IntMap<ActivityData>;
  public function new() { self_time = 0; total_time = 0; count = 0; children = new IntMap<ActivityData>(); }

  public function ensure_child(hidx:Int):ActivityData {
    if (!children.exists(hidx)) {
      children.set(hidx, new FLMListener.ActivityData());
    }
    return children.get(hidx);
  }

  public static function merge_timing(src:FLMListener.ActivityData, tgt:FLMListener.ActivityData):Void {
    tgt.self_time += src.self_time;
    tgt.count += src.count;
    tgt.total_time = 0;
    for (hidx in src.children.keys()) {
      merge_timing(src.children.get(hidx), tgt.ensure_child(hidx));
    }
  }

  public static function calc_totals(hd:FLMListener.ActivityData, hidx:Int, timing_strings:Array<String>):Int {
    var name = timing_strings[hidx];
    var total:Int = hd.self_time;
    var nc:Int = 0;
    hd.total_time = hd.self_time;
    for (hidx in hd.children.keys()) {
      var time = calc_totals(hd.children.get(hidx), hidx, timing_strings);
      hd.total_time += time;
      nc++;
    }
    return hd.total_time;
  }

  static public function trace_hd(display_hd:FLMListener.ActivityData, hidx:Int, depth:Int, timing_strings:Array<String>) {
    var name:String = timing_strings[hidx];
    var sp:String = ""; for (i in 0...depth) { sp += "|  "; }
    trace(sp+name+": [self="+display_hd.self_time+", total="+display_hd.total_time+"]");
    for (hidx in display_hd.children.keys()) {
      trace_hd(display_hd.children.get(hidx), hidx, depth+1, timing_strings);
    }
  }

}

typedef FrameTiming = {
  var delta:Int;
  var span:Int;
  var self_time:Int;
  var prev:FrameTiming;
}

typedef NewAlloc = { // aka struct
  var size:Int;
  var type:Int;
  var stackid:Int;
  var id:Int;
  var guid:Int;
}

typedef DelAlloc = { // aka struct
  var id:Int;
  var guid:Int;
}

typedef ReAlloc = { // aka struct
  var old_id:Int;
  var new_id:Int;
  var new_size:Int;
}

typedef SampleRaw = { // aka struct
  var numticks:Int;
  var callstack:Array<Int>;
}

class FLMListener {

  static private var next_inst_id:Int = 0;
  static public function start()
  {
    var client_writer = Thread.readMessage(true);
    var port = Thread.readMessage(true);
    var output_port:Int = Thread.readMessage(true);

    trace("Starting FLM listener...");
    var s = new Socket();
    s.bind(new sys.net.Host("0.0.0.0"), port); // Default Scout port
    s.listen(8);

    trace("Waiting for FLM on "+port+"...");
    var flm_socket : Socket = s.accept();
    var inst_id:Int = (next_inst_id++);

    var timing_strings:Array<String> = ["root"];
    var dur_lookup:StringMap<Int> = new StringMap<Int>();

    // Are we supposed to close the "parent" socket?
    s.close();
    s = null;

    // Optional hxt output
#if telemetry
    var hxts:Float = 0.0;
    var hxt:hxtelemetry.HxTelemetry = null;
    if (output_port>0) {
      trace("Will send bkg telemetry on port "+output_port);
      var cfg = new hxtelemetry.HxTelemetry.Config();
      //cfg.allocations = false;
      cfg.port = output_port;
      cfg.app_name = "HxScout-FLMListener-"+inst_id;
      cfg.singleton_instance = false;
      hxt = new hxtelemetry.HxTelemetry(cfg);
    }
#end

    // Launch next listener
    var listener = Thread.create(FLMListener.start);
    listener.sendMessage(client_writer);
    listener.sendMessage(port);
    listener.sendMessage(output_port);

    trace("Starting FLMListener["+inst_id+"]...");

    var cur_frame = new Frame(0, inst_id);
    var delta:Int = 0;
    var next_is_as = false;

    var amf_mode:Bool = true; //false;
    var reader = new Amf3Reader(flm_socket.input);
    var connected = true;

    PubSub.subscribe("stop_session", function(data:Dynamic):Void {
      if (data.inst_id == inst_id) connected = false;
    });

    function send_message(data:Dynamic)
    {
      client_writer.sendMessage(data);
    }

    function handle_data(data:Object<Dynamic>)
    {
			//trace(data);
			var name:String = cast(data['name'], String);

			// - - - - - - - - - - - -
			// Object allocations
			// - - - - - - - - - - - -
			if (name.indexOf(".memory.")==0) {
				var type:String = name.substr(8);

				switch(type) {
					case "stackIdMap": {
						var maps:Array<Int> = data["value"]; // len, val, val, val, len, val, ...
						if (cur_frame.push_stack_maps==null) cur_frame.push_stack_maps = new Array<Array<Int>>();
						//trace("Got new maps: "+maps);
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
					}
					case "newObject": {
						var n:NewAlloc = data["value"];
            trace("TODO, FLM, map data.type to Int, store, err, somewhere");
            trace("TODO, FLM, stackid -= 1 (hxt is 0-indexed, flm is 1-indexed)");
            // HXT type strings are stored in the stack_strings lookup, FLM,
            // we'll have to store them elsewhere.
						cur_frame.mem_alloc.push(n);
					}
					case "deleteObject": {
						var d:DelAlloc = data["value"];
						cur_frame.mem_dealloc.push(d);
					}
				}
				// newObject, deleteObject, updateObject
			} else {

				//if (name.indexOf('::')>0) {
				//	//trace(data);
				//	//trace(" -- Stack:");
				//	//trace(data['name']);
				//	//trace(Type.getClass(data['name']));
				//	//trace(Reflect.fields(data['name']));
				// 
				//	var bytes = haxe.io.Bytes.ofString(data["name"]);
				//	var msg = "";
				//	for (i in 0...bytes.length) {
				//		var b = bytes.get(i);
				//		if (b>=32 && b<=126) msg += String.fromCharCode(b); else msg += "%"+StringTools.hex(b, 2);
				//	}
				//	trace(msg);
				//}
	 
				if (name=='.swf.name') {
					send_message({non_frame:true, session_name:data['value'], inst_id:inst_id, amf_mode:amf_mode, "activity_descriptors":data['activity_descriptors']});
				}

				if (name=='.trace') {
          if (cur_frame.traces==null) cur_frame.traces = [];
          cur_frame.traces.push(data['value']);
        }

				// - - - - - - - - - - - -
				// FrameTiming / Span / Delta
				// - - - - - - - - - - - -
				if (data['delta']!=null) {
					// Delta without a span implies span = 0 ?
					var t:FrameTiming = { delta:data['delta'], span:data['span']==null?0:data['span'], prev:null, self_time:0 };
	 
					cur_frame.duration += t.delta;
          var count = data['count']==null ? 1 : data['count'];

					if (t.span>cur_frame.duration) {
						if (!amf_mode || (name!='.network.localconnection.idle' &&
                              name!='.rend.screen')) {
							trace("??? Event larger ("+t.span+") than current frame ("+cur_frame.duration+"): "+data);
						}
					}

					var self_time = t.span;
					var lookback = t.span-t.delta;
					//trace("- Considering: "+data+", self="+self_time+", lookback="+lookback+" -- t="+t);
					var tref:FrameTiming = cur_frame.timing;
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
	 
					//if (next_is_as) trace("next_is_as on: "+name);

          // Hierarchical timing
          var start_len = timing_strings.length;
          var nibs:Array<String> = name.split(".");
					var ptr:ActivityData = cur_frame.timing_data;
          if (amf_mode && next_is_as) nibs[1] = "as";
					for (i in 1...(amf_mode ? 2 : nibs.length)) {
						var nib:String = nibs[i];
						if (!dur_lookup.exists(nib)) {
							dur_lookup.set(nib, timing_strings.length);
							timing_strings.push(nib);
						}
						var nibi:Int = dur_lookup.get(nib);
						if (!ptr.children.exists(nibi)) {
							ptr.children.set(nibi, new ActivityData());
						}
						ptr = ptr.children.get(nibi);
						ptr.total_time += self_time;
						if (i==nibs.length-1) {
              ptr.self_time += self_time;
              ptr.count += count;
            }
					}
					if (timing_strings.length>start_len) {
						send_message({non_frame:true, timing_strings:timing_strings.slice(start_len), inst_id:inst_id});
					}

					// if (next_is_as || name.indexOf(".as.")==0) cur_frame.duration.as += self_time;
					// else if (name.indexOf(".gc.")==0) cur_frame.duration.gc += self_time;
					// else if (name.indexOf(".exit")==0) cur_frame.duration.other += self_time;
					// else if (name.indexOf(".rend.")==0) cur_frame.duration.rend += self_time;
					// else if (name.indexOf(".other.")==0) cur_frame.duration.other += self_time;
					// else if (name.indexOf(".swf.")==0) cur_frame.duration.other += self_time;
					// else if (name.indexOf(".network.")==0) cur_frame.duration.net += self_time;
					// else {
					//   cur_frame.duration.other += self_time;
					//   cur_frame.duration.unknown += self_time;
	#if DEBU// G_UNKNOWN
					//   var debug:String = data['name']+":"+self_time;
					//   cur_frame.unknown_names.push(debug);
	#end    //  
					//   //if (cur_frame.unknown_names.indexOf(data['name'])<0) cur_frame.unknown_names.push(data['name']);
					// }

					// not sure should do it this way, maybe a list of event names instead?
					next_is_as = (amf_mode && name=='.as.event');

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
				// Sampler
				// - - - - - - - - - - - -
				if (name.indexOf(".sampler.")==0) {
					if (name==".sampler.methodNameMapArray") {
						if (cur_frame.push_stack_strings==null) cur_frame.push_stack_strings = [];
						var names:Array<String> = cast(data["value"]);
						for (i in names) {
							cur_frame.push_stack_strings.push(i);
							//stack_strings.push(stack_string);
						}
					}
					else if (name==".sampler.methodNameMap") {
						if (cur_frame.push_stack_strings==null) cur_frame.push_stack_strings = [];
						var bytes = cast(data["value"], haxe.io.Bytes);
						var start=0;
						for (i in 0...bytes.length) {
							var b = bytes.get(i);
							if (b==0) {
								var stack_string:String = bytes.getString(start, i-start);
								cur_frame.push_stack_strings.push(stack_string);
								//stack_strings.push(stack_string);
								start = i+1;
							}
						}
						//trace("Frame "+cur_frame.inst_id+", Stack strings now: "+stack_strings.length);
						//for (i in 0...stack_strings.length) {
						//	trace(i+": "+stack_strings[i]);
						//}
					}
					else if (name==".sampler.sample") {
						var s:SampleRaw = data["value"];
						cur_frame.samples.push(s);
					}
				}

				if (name==".enter") {
					var offset = cur_frame.offset + cur_frame.duration;
					cur_frame.timing = null; // release timing events
					//Sys.stdout().writeString(cur_frame.to_json()+",\n");
					send_message(cur_frame);
					cur_frame = new Frame(cur_frame.id+1, inst_id, offset);
				}

			} // not .memory.
    }

    function read_ints(num:Int, report:Bool=false) {
      var r = "";
      while (num-->0) {
        var n:Int = flm_socket.input.readInt32();
        if (report) { r+=", "+n; }
      }
      if (report) trace(r);
    }

    var session_names:Array<String> = [];

    while( connected ) {

      // Read next event blob.
      var data:Object<Dynamic> = null;
      try {

        //trace("About to read data on inst "+inst_id);
        if (amf_mode) {
          var m:StringMap<Dynamic> = reader.read();
          if (m.exists("hxt") && m.get("hxt")) amf_mode = false;
          data = m;
        } else {
          var type:Int = flm_socket.input.readByte();
          switch(type) {
            case 1: { // serialized object
              var msg:String = flm_socket.input.readString(flm_socket.input.readInt32());
              data = haxe.Unserializer.run(msg);
              //trace("Got HXT ser data, length="+msg.length);
            }
            case 10: { // names
              if (cur_frame.push_stack_strings==null) cur_frame.push_stack_strings = [];
              var num:Int = flm_socket.input.readInt32();
              for (i in 0...num) {
                var name:String = flm_socket.input.readString(flm_socket.input.readInt32());
                cur_frame.push_stack_strings.push(name);
                session_names.push(name);
              }
            }
            case 11: { // samples
              var num:Int = flm_socket.input.readInt32();
              while (num>0) {
                var s:SampleRaw = {
                  numticks:0,
                  callstack:new Array<Int>()
                }
                var size:Int = flm_socket.input.readInt32();
                num -= size;
                while (size-->0) {
                  s.callstack.unshift(flm_socket.input.readInt32());
                }
                s.numticks = flm_socket.input.readInt32();
                num -= 2;
                cur_frame.samples.push(s);
              }
            }
            case 12: { // stacks
              var arr:Array<Int> = new Array<Int>();
              var num:Int = flm_socket.input.readInt32();
              while (num-->0) arr.push(flm_socket.input.readInt32());
              data = new Object<Dynamic>();
              data.set("name", ".memory.stackIdMap");
              data.set("value", arr);
              // handle_data is called below
            }
            case 13: { // allocation_data
              var num:Int = flm_socket.input.readInt32();
              while (num>0) {
                num--;
                var op:Int = flm_socket.input.readInt32();
                cur_frame.alloc_ops.push(op);  
                switch(op) {
                  case 0: { // allocation
                    num -= 4;
                    var n:NewAlloc = {
                      id:flm_socket.input.readInt32(),
                      type:(op!=1) ? flm_socket.input.readInt32() : 0,
                      size:(op!=1) ? flm_socket.input.readInt32() : 0,
                      stackid:(op==0) ? flm_socket.input.readInt32() : 0,
                      guid:0
                    }
                    cur_frame.mem_alloc.push(n);
                  }
                  case 1: { // collection
                    num -= 1;
                    var n:DelAlloc = {
                      id:flm_socket.input.readInt32(),
                      guid:0
                    }
                    cur_frame.mem_dealloc.push(n);
                  }
                  case 2: { // reallocation
                    num -= 3;
                    var n:ReAlloc = {
                      old_id:flm_socket.input.readInt32(),
                      new_id:flm_socket.input.readInt32(),
                      new_size:flm_socket.input.readInt32()
                    }
                    cur_frame.mem_realloc.push(n);
                  }
                }
              }
            }
            //case 14: { // collections
            //  var num:Int = flm_socket.input.readInt32();
            //  while (num>0) {
            //    var n:DelAlloc = {
            //      id:flm_socket.input.readInt32(),
            //      guid:0
            //    }
            //    cur_frame.mem_dealloc.push(n);
            //    num -= 1;
            //  }
            //}
            //case 15: { // reallocations
            //  var num:Int = flm_socket.input.readInt32();
            //  while (num>0) {
            //    var n:ReAlloc = {
            //      old_id:flm_socket.input.readInt32(),
            //      new_id:flm_socket.input.readInt32(),
            //      new_size:flm_socket.input.readInt32()
            //    }
            //    cur_frame.mem_realloc.push(n);
            //    num -= 3;
            //  }
            //}
          }
        }
      } catch( e:Dynamic) {
        // Handle EOF gracefully
        if (Type.getClass(e)==haxe.io.Eof) {
          trace("FLMListener["+inst_id+"] closing...");
          connected = false;
          flm_socket.close();
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

#if telemetry
      if (hxt!=null && openfl.Lib.getTimer()-hxts > 30) {
        hxts = openfl.Lib.getTimer();
        hxt.advance_frame();
      }
#end

      if (data!=null) handle_data(data);

    } // while (connected)

    flm_socket = null;
    client_writer = null;
    reader = null;

    PubSub.publish("flm_listener_closed", { inst_id: inst_id});

    trace("FLMListener["+inst_id+"] thread complete");
  }
}

class Frame {
  public var inst_id:Int;
  public var id:Int;
  public var offset:Int;
  public var duration:Int;
  public var mem:Map<String, Int>;
  public var samples:Array<SampleRaw>;
  public var push_stack_strings:Array<String>;
  public var push_stack_maps:Array<Array<Int>>;
  public var cpu:Float;
  //public var alloc:StringMap<Array<Dynamic>>;
  public var alloc_ops:Array<Int>;
  public var mem_alloc:Array<NewAlloc>;
  public var mem_dealloc:Array<DelAlloc>;
  public var mem_realloc:Array<ReAlloc>;
  //public var events:Array<Dynamic>;

  public var prof_top_down:Dynamic;
  public var alloc_bottom_up:Dynamic;

  public var traces:Array<String>;

#if DEBUG_UNKNOWN
  public var unknown_names:Array<String>;
#end
  public var timing:FrameTiming;
  public var timing_data:ActivityData;

  public function new(frame_id:Int, instance_id:Int, offset:Int=0) {
    inst_id = instance_id;
    id = frame_id;
    timing_data = new ActivityData();
    this.offset = offset;
    duration = 0;
    mem = new Map<String, Int>();
    samples = null;
    push_stack_strings = null;
    push_stack_maps = null;
    traces = null;
    cpu = 0;
    // TODO: conditional allocation based on enabled metrics
    samples = new Array<SampleRaw>();
    alloc_ops = new Array<Int>();
    mem_alloc = new Array<NewAlloc>();
    mem_dealloc = new Array<DelAlloc>();
    mem_realloc = new Array<ReAlloc>();
#if DEBUG_UNKNOWN
    unknown_names = [];
#end
  }

}

// Scout Naming Notes (in Activity Sequence):
// {"name":".player.abcdecode"} --> Preparing ActionScript ByteCode
// {"name":".network.loadmovie","value":"app:/Main.swf"} --> Loading SWF: app:/Main.swf

abstract Object<T>(Dynamic<T>) from Dynamic<T> {

    public inline function new() {
        this = {};
    }

    @:arrayAccess
    public inline function set(key:String, value:T):Void {
        Reflect.setField(this, key, value);
    }

    @:arrayAccess
    public inline function get(key:String):Null<T> {
        #if js
        return untyped this[key];
        #else
        return Reflect.field(this, key);
        #end
    }

    @:from static public inline function fromStringMap(m:StringMap<Dynamic>) {
      var data = new Object<Dynamic>();
      for (key in m.keys()) {
        data[key] = m.get(key);
        if (Type.getClass(data[key])==haxe.ds.StringMap) {
          data[key] = fromStringMap(m.get(key));
        }
      }
      return data;
    }

    @:from static public inline function fromDynamic(m:Dynamic) {
      var data = new Object<Dynamic>();
      for (key in Reflect.fields(m)) {
        data[key] = Reflect.field(m, key);
      }
      return data;
    }

    public inline function exists(key:String):Bool {
        return Reflect.hasField(this, key);
    }

    public inline function remove(key:String):Bool {
        return Reflect.deleteField(this, key);
    }

    public inline function keys():Array<String> {
        return Reflect.fields(this);
    }
}
