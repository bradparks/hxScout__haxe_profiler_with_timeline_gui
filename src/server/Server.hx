package;

import sys.net.Socket;
import amf.io.Amf3Reader;
import cpp.vm.Thread;

typedef Timing = {
  var delta:Int;
  var span:Int;
  var self_time:Int;
  var prev:Timing;
}

class Server {
  static function main() {
		var reader = Thread.create(FLMReader.start);
		reader.sendMessage(Thread.current());

    var s = new Socket();
    s.bind(new sys.net.Host("localhost"),7935); // hxScout client port
    s.listen(2);

    var policy = "<policy-file-request/>";
    var policy_idx = 0;

    while( true ) {
      trace("Waiting for client on 7935...");
      var client_socket : Socket = s.accept();
      trace("-- Connected on 7935, waiting for data");
      while (true) {
        var data = client_socket.input.readByte();

        if (policy.charCodeAt(policy_idx)==data) { // <policy-file-request/>
          policy_idx++;
          if (policy_idx==policy.length && client_socket.input.readByte()==0) {
            trace("Got policy file req on 7935");
            send_policy_file(client_socket); // closes socket
            break;
          }
        } else {
          policy_idx = 0;
        }
      }
    }
  }

  public static function send_policy_file(s:Socket)
  {
		s.output.writeString('<cross-domain-policy><site-control permitted-cross-domain-policies="master-only"/><allow-access-from domain="*" to-ports="7934,7935"/></cross-domain-policy>');
		s.output.writeByte(0);
    s.close();
  }

}

class FLMReader {

  static public function start()
  {
    var main = Thread.readMessage(true);

    var frames:Array<Frame> = [];
    var cur_frame = new Frame(0);
    var delta:Int = 0;
    var first_enter = true;
    var next_is_as = false;
    var stack_strings:Array<String> = ["1-indexed"];

    trace("Starting FLM listener...");
    var s = new Socket();
    s.bind(new sys.net.Host("localhost"),7934); // Default Scout port
    s.listen(2);

    while( true ) {
      trace("Waiting for FLM on 7934...");
      var flm_socket : Socket = s.accept();
      trace(" --- Client connected ---");
      var r = new Amf3Reader(flm_socket.input);
      var connected = true;
      while( connected ) {

        // Read next event blob. TODO: r.eof? socket.eof? instead of try/catch
        var data:Map<String, Dynamic> = null;
        try {
          data = r.read();
        } catch( e:Dynamic )  {
          // Handle EOF
          if (Type.getClass(e)==haxe.io.Eof) {
            connected = false;
            flm_socket.close();
            break;
          }
          // Handle flash requests for policy file
          if ((e+"").indexOf("type-marker: 60")>0) {
            trace("Got flash policy file request, writing response...");
            flm_socket.input.readUntil(0);
            Server.send_policy_file(flm_socket);
            break;
          }
          // Other errors, rethrow
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
                //trace("  -- does not include ("+tref.delta+"), dropping lookback to "+(lookback-tref.delta));
              }
              lookback -= tref.delta;
              tref = tref.prev;
            }
            t.prev = cur_frame.timing;
            t.self_time = self_time;
            cur_frame.timing = t;

            //trace("  -- Final self time: "+self_time);
            if (self_time<0) throw "Umm, can't have negative self time!!";

            //trace("  -- "+name+": "+self_time);

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
              //  trace(i+": "+stack_strings[i]);
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
              frames.push(cur_frame);
              cur_frame = new Frame(cur_frame.id+1);
            }
          }
        }
      }
    }
  }
}

class Frame {
  public var id:Int;
  public var duration:Dynamic;
  public var mem:Map<String, Int>;
  public var samples:Array<Dynamic>;
  //public var events:Array<Dynamic>;
  #if DEBUG_UNKNOWN
    public var unknown_names:Array<String>;
  #end
  public var timing:Timing;

  public function new(frame_id:Int) {
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

