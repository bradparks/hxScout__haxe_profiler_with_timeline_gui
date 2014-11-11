package;

import flash.display.*;
import flash.events.*;

import openfl.net.Socket;
import haxe.ds.StringMap;

class Main extends Sprite {

  private var fps:openfl.display.FPS;
  private var flm_sessions:StringMap<FLMSession> = new StringMap<FLMSession>();
  private var gui:HXScoutClientGUI;

  public function new()
  {
    super();

    setup_stage();
    setup_server_socket(function(s) {
      trace("Got socket: "+s);
      addChild(gui = new HXScoutClientGUI());
      center();
      setup_frame_data_receiver(s);
    });
  }

  function setup_server_socket(callback)
  {
    var lbl = Util.make_label("Attach to hxScout server at: ", 17);
    var inp:Dynamic = null;
    inp = Util.make_input(200, 17, 0xaaaaaa, "localhost:7935",
                          function(hostname) {
                            var s:Socket = null;
                            function success() {
                              Util.fade_away(lbl);
                              Util.fade_away(inp.cont).then(function() {
                                inp.cont.parent.removeChild(inp.cont);
                                callback(s);
                              });
                            }
                            function err() {
                              Util.shake(inp.cont);
                            }
                            var host = hostname;
                            var port:Int = 7935;
                            if (~/:\d+$/.match(host)) {
                              host = ~/:\d+$/.replace(hostname, "");
                              port = Std.parseInt(~/.*:(\d+)/.replace(hostname, "$1"));
                            }
                            trace("Connecting to host="+host+", port="+port);
                            s = setup_socket(host, port, success, err);
                          });

    // BUG: trace(inp.cont.width);  returns null in neko

    lbl.x = -(lbl.width + inp.bug)/2;
    lbl.y = -lbl.height/2;
    inp.cont.x = lbl.x + lbl.width;
    inp.cont.y = lbl.y;
    addChild(lbl);
    addChild(inp.cont);
  }

  function center(e=null) {
    this.x = stage.stageWidth/2;
    this.y = stage.stageHeight/2;
    fps.x = -this.x;
    fps.y = -this.y;
    if (gui!=null) gui.resize(stage.stageWidth, stage.stageHeight);
  }

  function setup_stage()
  {
    fps = new openfl.display.FPS(0,0,0xffffff);
    addChild(fps);
    center();
    stage.addEventListener(flash.events.Event.RESIZE, center);
  }

  function setup_socket(host, port, on_success, on_cannot_connect)
  {
    var s = new Socket();

    var cleanup = null;

    function error(e) {
      trace("Error, connect failed!");
      cleanup();
      on_cannot_connect();
    }
    function connect(e) {
      trace("Socket connect succeeded!");
      cleanup();
      on_success();
    }

    cleanup = function() {
      s.removeEventListener(IOErrorEvent.IO_ERROR, error);
      s.removeEventListener(Event.CONNECT, connect);
    }

    s.addEventListener(IOErrorEvent.IO_ERROR, error);
    s.addEventListener(Event.CONNECT, connect);
    s.connect(host, port);

    return s;
  }

  function setup_frame_data_receiver(server:Socket) {
    var frame_data_length:UInt = 0;

    // Probably not necessary, meh
    var keepalive = GlobalTimer.setInterval(function() {
      server.writeInt(0); // FYI, sends 4 bytes
    }, 2000);

    function on_enter_frame(e:Event) {
      while (true) { // process multiple frame_data's per client frame
        server.endian = openfl.utils.Endian.LITTLE_ENDIAN;
        if (server.bytesAvailable>4 && frame_data_length==0) {
          frame_data_length = server.readInt();
        }
        if (server.bytesAvailable>=frame_data_length && frame_data_length>0) {
          var frame_data = haxe.Json.parse(server.readUTFBytes(frame_data_length));
          frame_data_length = 0;
          //trace(frame_data);
          var inst_id:String = frame_data.inst_id;
          if (!flm_sessions.exists(inst_id)) {
            flm_sessions.set(inst_id, new FLMSession(inst_id));
            gui.add_session(flm_sessions.get(inst_id));
          }
          flm_sessions.get(inst_id).receive_frame_data(frame_data);
        } else {
          break;
        }
      }
    }

    stage.addEventListener(Event.ENTER_FRAME, on_enter_frame);
  }

}

class FLMSession {

  public var frames:Array<Dynamic> = [];
  public var inst_id:String;
  public var temp_mem:StringMap<Int>;

  public function new(iid:String)
  {
    inst_id = iid;
  }

  public function receive_frame_data(frame_data)
  {
    frames.push(frame_data);
  }

}

class HXScoutClientGUI extends Sprite
{
  private var sessions = [];
  private var timing_pane:Sprite;
  private var memory_pane:Sprite;
  private var active_session = -1;
  private var last_frame_drawn = -1;

  public function new()
  {
    super();

    timing_pane = new Sprite();
    memory_pane = new Sprite();

    addChild(timing_pane);
    addChild(memory_pane);

    addEventListener(Event.ENTER_FRAME, on_enter_frame);
  }

  private var layout = {
    PAD:2,
    TH:150
  }

  public function resize(w:Float, h:Float)
  {
    timing_pane.y = -h/2+layout.PAD;
    timing_pane.x = -w/2+layout.PAD;
    timing_pane.graphics.clear();
    timing_pane.graphics.lineStyle(1, 0x888888);
    timing_pane.graphics.beginFill(0x111111);
    timing_pane.graphics.drawRect(0,-layout.TH,w-2*layout.PAD,layout.TH);
    timing_pane.scrollRect = new flash.geom.Rectangle(0,-layout.TH,w-2*layout.PAD,layout.TH);

    memory_pane.y = timing_pane.y + layout.PAD*2 + layout.TH;
    memory_pane.x = timing_pane.x;
    memory_pane.graphics.clear();
    memory_pane.graphics.lineStyle(1, 0x888888);
    memory_pane.graphics.beginFill(0x111111);
    memory_pane.graphics.drawRect(0,-layout.TH,w-2*layout.PAD,layout.TH);
    memory_pane.scrollRect = new flash.geom.Rectangle(0,-layout.TH,w-2*layout.PAD,layout.TH);

  }

  public function add_session(flm_session:FLMSession)
  {
    trace("GUI got new session: "+flm_session.inst_id);
    sessions.push(flm_session);
    if (active_session<0) {
      set_active_session(sessions.length-1);
    }
  }

  public function set_active_session(n:Int)
  {
    if (n>=sessions.length) return;
    active_session = n;
    last_frame_drawn = -1;
    while (timing_pane.numChildren>0) timing_pane.removeChildAt(0);
    while (memory_pane.numChildren>0) memory_pane.removeChildAt(0);

    var session:FLMSession = sessions[active_session];
    session.temp_mem = new StringMap<Int>();
  }

  var mem_types = ["used","telemetry.overhead","managed.used","managed","total"];

  private function on_enter_frame(e:Event)
  {
    if (active_session<0) return;
    var i=0;
    var session:FLMSession = sessions[active_session];
    var hzoom = 6;
    var vzoom = 3;
    for (i in (last_frame_drawn+1)...session.frames.length) {
      var frame = session.frames[i];

      if (Reflect.hasField(frame, "mem")) {
        for (key in mem_types) {
          if (Reflect.hasField(frame.mem, key)) {
            session.temp_mem.set(key, Reflect.field(frame.mem, key));
          }
        }
      }

      trace(" -- Drawing "+session.inst_id+":"+frame.id);
      trace(frame);
      var s:Shape = new Shape();
      s.graphics.beginFill(0x444444);
      s.graphics.drawRect(0,0,hzoom-1,vzoom*frame.duration.total/1000);
      s.x = Std.parseInt(frame.id)*hzoom;
      s.y = -s.height;
      timing_pane.addChild(s);

      if (!session.temp_mem.exists("total")) continue;

      s = new Shape();
      s.graphics.beginFill(0x444444);
      s.graphics.drawRect(0,0,hzoom-1,vzoom*session.temp_mem.get("total")/500);
      s.x = Std.parseInt(frame.id)*hzoom;
      s.y = -s.height;
      memory_pane.addChild(s);

    }
    last_frame_drawn = session.frames.length-1;
  }

}
