package;

import sys.net.Socket;
import amf.io.Amf3Reader;
import cpp.vm.Thread;
import haxe.io.*;

typedef Timing = {
  var delta:Int;
  var span:Int;
  var self_time:Int;
  var prev:Timing;
}

class Server {
  static public function main() {
    trace("hxScout");

		var listener = Thread.create(FLMListener.start);
		listener.sendMessage(Thread.current());

    var s = new Socket();
    s.bind(new sys.net.Host("0.0.0.0"),7933); // hxScout client port
    s.listen(2);
    s.setBlocking(true);

    var policy = "<policy-file-request/>";
    var policy_idx = 0;

    while( true ) {
      trace("Waiting for client on 7933...");
      var client_socket : Socket = s.accept();
      trace("-- Connected on 7933, waiting for data");
      client_socket.setBlocking(false);
      while (true) {
        var data = 0;
        try {
          data = client_socket.input.readByte();
          //trace(ts()+"Read data from client: "+data);
        } catch (e:Dynamic) {
          if (Type.getClass(e)==haxe.io.Eof) {
            trace("Client disconnected!");
            client_socket.close();
            break;
          }
          else if (e=="Blocked") {
						// no data from client
					}
          else {
            // Unknown exception, rethrow
            throw e;
          }
        }

        if (policy.charCodeAt(policy_idx)==data) { // <policy-file-request/>
          policy_idx++;
          if (policy_idx==policy.length && client_socket.input.readByte()==0) {
            trace("Got policy file req on 7933");
            send_policy_file(client_socket); // closes socket
            break;
          }
        } else {
          policy_idx = 0;
        }

        var frame_data = Thread.readMessage(false);
        if (frame_data!=null) {
          var b = Bytes.ofString(frame_data);
          trace("Writing frame_data length="+b.length);
          client_socket.output.writeInt32(b.length);
          client_socket.output.writeBytes(b, 0, b.length);
        } else {
          // No frame data, sleep for a bit
          Sys.sleep(0.033);
        }
      }
    }
  }

  static var t0:Float = Date.now().getTime();
  static function ts():String {
    var t:Float = (Date.now().getTime()-t0)/1000.0;
    return (t)+" s: ";
  }

  public static function send_policy_file(s:Socket)
  {
		s.output.writeString('<cross-domain-policy><site-control permitted-cross-domain-policies="master-only"/><allow-access-from domain="*" to-ports="7934,7933"/></cross-domain-policy>');
		s.output.writeByte(0);
    s.close();
  }

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
		// var listener = Thread.create(FLMListener.start);
		// listener.sendMessage(client_writer);

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
			} catch( e:Dynamic )	{
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
					Server.send_policy_file(cast(flm_socket));
					break;
				}
				// Other errors, rethrow
        trace("Uh oh, rethrowing: "+e);
				throw e;
			}
 
			if (data!=null) {
				//trace(data);
				var name:String = cast(data['name'], String);
 
				// - - - - - - - - - - - -
				// Timing / Span / Delta
				// - - - - - - - - - - - -
				if (data['delta']!=null) {
					// Delta without a span implies span = 0 ?
					var t:Timing = { delta:data['delta'], span:data['span']==null?0:data['span'], prev:null, self_time:0 };
 
					cur_frame.duration.total += t.delta;
 
					if (t.span>cur_frame.duration.total) {
						if (name!='.network.localconnection.idle') {
							trace("Event larger ("+t.span+") than current frame ("+cur_frame.duration.total+"): "+data);
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
				// Memory
				// - - - - - - - - - - - -
				if (name.indexOf(".mem.")==0 && data["value"]!=null) {
					var type:String = name.substr(5);
					//if (cur_frame.mem[type]==null) cur_frame.mem[type] = 0;
					cur_frame.mem[type] = data["value"];
				}
 
				// - - - - - - - - - - - -
				// Sampler
				// - - - - - - - - - - - -
				if (name.indexOf(".sampler.")==0) {
					if (name==".sampler.methodNameMap") {
						var bytes = cast(data["value"], haxe.io.Bytes);
						var start=0;
						for (i in 0...bytes.length) {
							var b = bytes.get(i);
							if (b==0) {
								stack_strings.push(bytes.getString(start, i-start));
								start = i+1;
							}
						}
						//trace("Stack strings now: "+stack_strings.length);
						//for (i in 0...stack_strings.length) {
						//	trace(i+": "+stack_strings[i]);
						//}
					}
					else if (name==".sampler.sample") {
						var value:Map<String,Dynamic> = data["value"];
						cur_frame.samples.push(value);
					}
				}
 
				if (data['name']==".enter") {
					if (first_enter) {
						first_enter = false;
					} else {
						cur_frame.timing = null; // release timing events
						Sys.stdout().writeString(cur_frame.to_json()+",\n");
						client_writer.sendMessage(cur_frame.to_json());
						frames.push(cur_frame);
						cur_frame = new Frame(cur_frame.id+1, inst_id);
					}
				}
			}
		}
	}
}

class Frame {
  public var inst_id:Int;
  public var id:Int;
  public var duration:Dynamic;
  public var mem:Map<String, Int>;
  public var samples:Array<Dynamic>;
  //public var events:Array<Dynamic>;
  #if DEBUG_UNKNOWN
    public var unknown_names:Array<String>;
  #end
  public var timing:Timing;

  public function new(frame_id:Int, instance_id:Int) {
    inst_id = instance_id;
    id = frame_id;
    duration = {};
    duration.total = 0;
    duration.as = 0;
    duration.gc = 0;
    duration.other = 0;
    duration.rend = 0;
    duration.swf = 0;
    duration.unknown = 0;
    mem = new Map<String, Int>();
    samples = [];
    #if DEBUG_UNKNOWN
      unknown_names = [];
    #end
    //events = [];
  }

  public function to_json():String
  {
    return haxe.Json.stringify({
      id:id,
      inst_id:inst_id,
      #if DEBUG_UNKNOWN
          unknown_names:unknown_names,
      #end
      duration:duration,
      samples:samples,
      mem:mem
    });
  }
}

// Naming Notes (in Activity Sequence):
// {"name":".player.abcdecode"} --> Preparing ActionScript ByteCode
// {"name":".network.loadmovie","value":"app:/Main.swf"} --> Loading SWF: app:/Main.swf

