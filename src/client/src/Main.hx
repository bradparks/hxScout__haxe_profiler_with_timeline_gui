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

    function on_server_connected(s:Socket) {
      trace("Got socket: "+s);
      addChildAt(gui = new HXScoutClientGUI(), 0);
      center();
      setup_frame_data_receiver(s);
    }

    // CPP, start server thread automatically, failover to request
    #if cpp
      var listener = cpp.vm.Thread.create(Server.main);
      var s:Socket = null;
      Sys.sleep(0.2);
      s = setup_socket("localhost", 7933,
                       function() {
                         on_server_connected(s);
                       },
                       function() {
                         ui_server_request(on_server_connected);
                       });
    #else
      ui_server_request(on_server_connected);
    #end

  }

  function ui_server_request(callback)
  {
    var lbl = Util.make_label("Attach to hxScout server at: ", 17);
    var inp:Dynamic = null;
    inp = Util.make_input(200, 17, 0xaaaaaa, "localhost:7933",
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
                            var port:Int = 7933;
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
          if (frame_data.session_name!=null) {
            gui.update_name(frame_data.session_name, frame_data.inst_id);
          }
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
  public var name:String;

  public function new(iid:String)
  {
    inst_id = iid;
    name = inst_id;
  }

  public function receive_frame_data(frame_data)
  {
    if (frame_data.session_name!=null) {
      name = frame_data.session_name;
    } else {
      frames.push(frame_data);
    }
  }

}

class HXScoutClientGUI extends Sprite
{
  private var sessions = [];
  private var nav_pane:Sprite;
  private var timing_pane:Sprite;
  private var memory_pane:Sprite;
  private var session_pane:Sprite;
  private var active_session = -1;
  private var last_frame_drawn = -1;

  public function new()
  {
    super();

    nav_pane = new Sprite();
    timing_pane = new Sprite();
    memory_pane = new Sprite();
    session_pane = new Sprite();

    //timing_pane.cacheAsBitmap = true;
    //memory_pane.cacheAsBitmap = true;

    addChild(nav_pane);
    addChild(timing_pane);
    addChild(memory_pane);
    addChild(session_pane);

    AEL.add(nav_pane, MouseEvent.MOUSE_DOWN, handle_nav_start);

    addEventListener(Event.ENTER_FRAME, on_enter_frame);
  }

  function handle_nav_start(e:Event)
  {
    stage.addEventListener(MouseEvent.MOUSE_MOVE, handle_nav_move);
    stage.addEventListener(MouseEvent.MOUSE_UP, handle_nav_stop);

    nav_to(nav_pane.mouseX);
  }

  function handle_nav_stop(e:Event)
  {
    stage.removeEventListener(MouseEvent.MOUSE_MOVE, handle_nav_move);
    stage.removeEventListener(MouseEvent.MOUSE_UP, handle_nav_stop);
  }

  function handle_nav_move(e:Event)
  {
    nav_to(nav_pane.mouseX);
  }

  function nav_to(x:Float)
  {
    trace("Nav to: "+x);
    timing_pane.scrollRect.x = -x;

    var r = new flash.geom.Rectangle();
    r.copyFrom(timing_pane.scrollRect);
    r.x = x*(layout.frame_width);
    timing_pane.scrollRect = r;
    memory_pane.scrollRect = r;
  }

  private var layout = {
    nav:{
      height:50,
    },
    timing:{
      height:150,
      scale:300
    },
    session:{
      width:200,
    },
    PAD:2,
    frame_width:6,
    MSCALE:100
  }

  public function resize(w:Float, h:Float)
  {
    var p = layout.PAD;

    var y = p;
    draw_pane(w, h, nav_pane,     layout.session.width+2*p, y, w-(layout.session.width+p*3), layout.nav.height,    0, false);
    y += p + layout.nav.height;
    draw_pane(w, h, timing_pane,  layout.session.width+2*p, y, w-(layout.session.width+p*3), layout.timing.height, 0);
    y += p + layout.timing.height;
    draw_pane(w, h, memory_pane,  layout.session.width+2*p, y, w-(layout.session.width+p*3), layout.timing.height, 0);
    draw_pane(w, h, session_pane, p,       p, (layout.session.width-p*2),   h-2*p,                0, false);

  }

  inline function draw_pane(stage_w:Float, stage_h:Float, pane:Sprite, x:Float, y:Float, w:Float, h:Float, scroll:Float, bottom_aligned:Bool=true)
  {
    pane.x = -stage_w/2 + x;
    pane.y = -stage_h/2 + y;
    if (bottom_aligned) {
      pane.graphics.drawRect(0,-h,w,h);
      pane.scrollRect = new flash.geom.Rectangle(0,-h,w,h);
    } else {
      pane.graphics.clear();
      pane.graphics.lineStyle(1, 0x888888);
      pane.graphics.beginFill(0x111111);
      pane.graphics.drawRect(0,0,w,h);
      pane.scrollRect = new flash.geom.Rectangle(0,0,w,h);
    }
  }

  public function update_name(name:String, inst_id:String)
  {
    trace("Set name: "+inst_id+", "+name);
    var lbl = Util.make_label(name, 15);
    var ses:Sprite = cast(session_pane.getChildAt(Std.parseInt(inst_id)));
    lbl.y = ses.height/2-lbl.height/2;
    ses.addChild(lbl);
  }

  public function add_session(flm_session:FLMSession)
  {
    trace("GUI got new session: "+flm_session.inst_id);
    sessions.push(flm_session);
    if (active_session<0) {
      set_active_session(sessions.length-1);
    }

    var s:Sprite = new Sprite();
    s.graphics.beginFill(0x444444);
    s.graphics.lineStyle(4, 0x555555);
    s.graphics.drawRect(0,0,layout.session.width-2*layout.PAD,46);
    s.buttonMode = true;
    AEL.add(s, MouseEvent.CLICK, function(e) { set_active_session(s.parent.getChildIndex(s)); });
    //s.x = layout.PAD;
    s.y = (sessions.length-1)*46;
    session_pane.addChild(s);
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

    reset_nav_pane();
    resize(stage.stageWidth, stage.stageHeight);
  }

  function reset_nav_pane()
  {
    // dispose?
    while (nav_pane.numChildren>0) nav_pane.removeChildAt(0);
    nav_pane.addChild(new Bitmap(new BitmapData(Std.int(nav_pane.width), Std.int(nav_pane.height), true, 0x0)));
  }

  var mem_types = ["used","telemetry.overhead","managed.used","managed","total"];

  private function on_enter_frame(e:Event)
  {
    if (active_session<0) return;
    var i=0;
    var session:FLMSession = sessions[active_session];
    for (i in (last_frame_drawn+1)...session.frames.length) {
      var frame = session.frames[i];

      if (Reflect.hasField(frame, "mem")) {
        for (key in mem_types) {
          if (Reflect.hasField(frame.mem, key)) {
            session.temp_mem.set(key, Reflect.field(frame.mem, key));
          }
        }
      }

      //trace(" -- Drawing ["+session.inst_id+"]:"+frame.id);
      //trace(frame);

      add_rect(i, timing_pane, frame.duration.total/layout.timing.scale, 0x444444, false);
      add_rect(i, timing_pane, frame.duration.gc/layout.timing.scale, 0xdd5522, true);
      add_rect(i, timing_pane, frame.duration.other/layout.timing.scale, 0xaa4488, true);
      add_rect(i, timing_pane, frame.duration.as/layout.timing.scale, 0x2288cc, true);
      add_rect(i, timing_pane, frame.duration.rend/layout.timing.scale, 0x66aa66, true);

      if (!session.temp_mem.exists("total")) continue;

      //trace(session.temp_mem);

      add_rect(i, memory_pane, session.temp_mem.get("total")/layout.MSCALE, 0x444444, false);
      add_rect(i, memory_pane, session.temp_mem.get("managed.used")/layout.MSCALE, 0x227788, true);
      add_rect(i, memory_pane, session.temp_mem.get("bitmap.display")/layout.MSCALE, 0x22aa99, true);

      //var s:Shape = new Shape();
      //s.graphics.beginFill(0x444444);
      //s.graphics.drawRect(0,0,layout.frame_width-1,session.temp_mem.get("total")/500);
      //s.x = Std.parseInt(frame.id)*layout.frame_width;
      //s.y = -s.height;
      //memory_pane.addChild(s);

    }
    last_frame_drawn = session.frames.length-1;
  }

  private var stack_y:Float = 0;
  private inline function add_rect(id:Int, pane:Sprite, value:Float, color:Int, stack:Bool) {
    if (!stack) stack_y = 0;
    var s:Shape = new Shape();
    s.graphics.beginFill(color);
    s.graphics.drawRect(0,0,layout.frame_width-1,value);
    s.x = id*layout.frame_width;
    s.y = -s.height-stack_y;
    pane.addChild(s);
    if (stack) stack_y += s.height;

    if (pane==timing_pane) {
      var m = new flash.geom.Matrix();
      m.translate(s.x, 0);
      m.scale(1/layout.frame_width, -0.5);
      m.translate(0, layout.nav.height);
      cast(nav_pane.getChildAt(0)).bitmapData.draw(s, m);
    }
  }

}
