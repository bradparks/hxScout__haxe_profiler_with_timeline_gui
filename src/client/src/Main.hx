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
    Util.stage = stage;

    super();

    setup_stage();

    //cpp.vm.Profiler.start(); // requires HXCPP_STACK_TRACE in project.xml

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
    fps.mouseEnabled = false;
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

class SampleData {
  public var collapsed:Bool = false;
  public var total_time:Int = 0;
  public var self_time:Int = 0;
  public var children:haxe.ds.IntMap<SampleData> = new haxe.ds.IntMap<SampleData>();

  public function ensure_child(idx):Void
  {
    if (!children.exists(idx)) {
      var s = new SampleData();
      children.set(idx, s);
    }
  }

  public static function merge_sample_data(tgt:SampleData, source:SampleData, root:Bool=true):Void
  {
    tgt.total_time += source.total_time;
    var keys = source.children.keys();
    for (i in keys) {
      tgt.ensure_child(i);
      merge_sample_data(tgt.children.get(i), source.children.get(i), false);
    }
    if (root) tgt.calc_self_time();
  }

  public function calc_self_time():Void
  {
    self_time = total_time;
    var keys = children.keys();
    for (i in keys) {
      self_time -= children.get(i).total_time;
      children.get(i).calc_self_time();
    }
  }
}


class FLMSession {

  public var frames:Array<Dynamic> = [];
  public var inst_id:String;
  public var temp_running_mem:StringMap<Int>;
  public var name:String;
  public var stack_strings:Array<String> = ["1-indexed"];
  public var ses_tile:Sprite;

  public function new(iid:String)
  {
    inst_id = iid;
    name = inst_id;
  }

  public function receive_frame_data(frame_data)
  {
    if (frame_data.session_name!=null) {
      name = frame_data.session_name;
      return; // Not really frame data...
    }

    if (frame_data.push_stack_strings!=null) {
      var strings:Array<String> = frame_data.push_stack_strings;
      for (str in strings) {
        stack_strings.push(str);
      }
    }
    if (frame_data.samples!=null) {
      collate_sample_data(frame_data);
    }
    frames.push(frame_data);
  }

  private function collate_sample_data(frame_data:Dynamic):Void
  {
    //trace(haxe.Json.stringify(frame_data.samples, null, "  "));
    var samples:Array<Dynamic> = frame_data.samples;

    var top_down = new SampleData();
    frame_data.top_down = top_down;
    for (sample in samples) {
      var numticks:Int = sample.numticks;
      var callstack:Array<Int> = sample.callstack;
      var ptr:SampleData = top_down;
      var i:Int = callstack.length;
      while ((--i)>=0) {
        var idx = callstack[i];
        ptr.ensure_child(idx);
        ptr.children.get(idx).total_time += numticks;
        ptr = ptr.children.get(idx);
      }
    }
    top_down.calc_self_time();

    //trace("Top Down, frame "+(frames.length+1));
    //print_samples(frame_data.top_down);

    var bottom_up = new SampleData();
    frame_data.bottom_up = bottom_up;
    for (sample in samples) {
      var numticks:Int = sample.numticks;
      var callstack:Array<Int> = sample.callstack;
      var ptr:SampleData = bottom_up;
      var i:Int = -1;
      while ((++i)<callstack.length) {
        var idx = callstack[i];
        ptr.ensure_child(idx);
        ptr.children.get(idx).self_time += numticks;
        ptr = ptr.children.get(idx);
      }
    }

    //trace("Bottom Up, frame "+(frames.length+1));
    //print_samples(frame_data.bottom_up);
  }

  //private static var INDENT:String = "                                            ";
  //private function print_samples(ptr:SampleData, indent:Int=0):Void
  //{
  //  var keys = ptr.children.keys();
  //  for (i in keys) {
  //    trace(INDENT.substr(0,indent)+stack_strings[i]+" - "+ptr.children.get(i).self_time+", "+ptr.children.get(i).total_time);
  //    print_samples(ptr.children.get(i), indent+1);
  //  }
  //}

}

class HXScoutClientGUI extends Sprite
{
  private var sessions = [];

  private var nav_pane:Pane;
  private var summary_pane:Pane;
  private var timing_pane:Pane;
  private var memory_pane:Pane;
  private var session_pane:Pane;
  private var detail_pane:Pane;

  private var active_session = -1;
  private var last_frame_drawn = -1;
  private var nav_scalex:Float = 1;

  private var nav_ctrl:NavController;
  private var sel_ctrl:SelectionController;

  public function new()
  {
    super();

    nav_pane = new Pane();
    summary_pane = new Pane();
    timing_pane = new Pane(true);
    memory_pane = new Pane(true);
    session_pane = new Pane(false, false, true); // scrolly
    detail_pane = new Pane(false, false, true);  // scrolly

    addChild(session_pane);
    addChild(nav_pane);
    addChild(summary_pane);
    addChild(timing_pane);
    addChild(memory_pane);
    addChild(detail_pane);

    sel_ctrl = new SelectionController(nav_pane, timing_pane, memory_pane, detail_pane, summary_pane, layout, get_active_session);
    nav_ctrl = new NavController(nav_pane, timing_pane, memory_pane, sel_ctrl, function() { return layout.frame_width/nav_scalex; });

    addEventListener(Event.ENTER_FRAME, on_enter_frame);
  }

  private function get_active_session():FLMSession { return active_session<0 ? null : sessions[active_session]; }

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
    summary:{
      width:300,
    },
    frame_width:6,
    MSCALE:100
  }

  public function resize(w:Float=0, h:Float=0)
  {
    var y = 0;
    resize_pane(w, h, session_pane, 0,       0, (layout.session.width),   h);
    resize_pane(w, h, nav_pane,     layout.session.width, y, w-(layout.session.width), layout.nav.height);
    y += layout.nav.height;
    resize_pane(w, h, timing_pane,  layout.session.width, y, w-(layout.session.width+layout.summary.width), layout.timing.height);
    resize_pane(w, h, summary_pane, w-layout.summary.width, y, layout.summary.width, layout.timing.height*2);
    y += layout.timing.height;
    resize_pane(w, h, memory_pane,  layout.session.width, y, w-(layout.session.width+layout.summary.width), layout.timing.height);
    y += layout.timing.height;
    resize_pane(w, h, detail_pane,  layout.session.width, y, w-(layout.session.width), h-y);

    if (stage!=null) sel_ctrl.redraw();
  }

  inline function resize_pane(stage_w:Float, stage_h:Float, pane:Sprite, x:Float, y:Float, w:Float, h:Float)
  {
    pane.width = w;
    pane.height = h;
    pane.x = -stage_w/2 + x;
    pane.y = -stage_h/2 + y;
  }

  public function update_name(name:String, inst_id:String)
  {
    trace("Set name: "+inst_id+", "+name);
    var lbl = Util.make_label(name, 15);
    lbl.filters = [new flash.filters.DropShadowFilter(1, 120, 0x0, 0.8, 3, 3, 1, 2)];
    var ses:Sprite = cast(session_pane.cont.getChildAt(Std.parseInt(inst_id)));
    lbl.y = ses.height/2-lbl.height/2;
    lbl.x = 4;
    lbl.mouseEnabled = false;
    ses.addChild(lbl);
  }

  public function add_session(flm_session:FLMSession)
  {
    trace("GUI got new session: "+flm_session.inst_id);
    var s:Sprite = flm_session.ses_tile = new Sprite();
    s.alpha = 0.3;
    sessions.push(flm_session);
    if (active_session<0) {
      set_active_session(sessions.length-1);
    }

    var m:flash.geom.Matrix = new flash.geom.Matrix();
    m.createGradientBox(session_pane.innerWidth,42,Math.PI/180*(-90));
    s.graphics.beginGradientFill(openfl.display.GradientType.LINEAR,
                                 [0x444444, 0x535353],
                                 [1, 1],
                                 [0,255],
                                 m);
    s.graphics.lineStyle(2, 0x555555);
    s.graphics.drawRect(0,0,session_pane.innerWidth,42);
    s.buttonMode = true;
    AEL.add(s, MouseEvent.CLICK, function(e) { set_active_session(s.parent.getChildIndex(s)); });
    s.y = (sessions.length-1)*46;
    session_pane.cont.addChild(s);
  }

  public function set_active_session(n:Int)
  {
    for (i in 0...sessions.length) {
      sessions[i].ses_tile.alpha = i==n ? 1 : 0.3;
      if (sessions[i].ses_tile.numChildren>0) sessions[i].ses_tile.getChildAt(0).alpha = 1;
    }

    if (n>=sessions.length) return;
    active_session = n;
    last_frame_drawn = -1;
    sel_ctrl.start_sel = sel_ctrl.end_sel = -1;
    while (timing_pane.cont.numChildren>0) timing_pane.cont.removeChildAt(0);
    timing_pane.cont.graphics.clear();
    while (memory_pane.cont.numChildren>0) memory_pane.cont.removeChildAt(0);
    while (detail_pane.cont.numChildren>0) detail_pane.cont.removeChildAt(0);
    while (summary_pane.cont.numChildren>0) summary_pane.cont.removeChildAt(0);
    detail_pane.cont.graphics.clear();

    timing_shapes = [];
    memory_shapes = [];

    var session:FLMSession = sessions[active_session];
    session.temp_running_mem = new StringMap<Int>();

    reset_nav_pane();
    resize(stage.stageWidth, stage.stageHeight);
  }

  function reset_nav_pane()
  {
    if (nav_pane.cont.numChildren<1) {
      nav_pane.cont.addChild(new Bitmap(new BitmapData(2048, layout.nav.height, true, 0x0)));
    }
    var bd:BitmapData = cast(nav_pane.cont.getChildAt(0)).bitmapData;
    bd.fillRect(new flash.geom.Rectangle(0,0,2048,layout.nav.height), 0); // clear
  }

  var mem_types = ["used","telemetry.overhead","managed.used","managed","total","bitmap"];

  private function on_enter_frame(e:Event)
  {
    if (active_session<0) return;
    var i=0;
    var session:FLMSession = sessions[active_session];
    for (i in (last_frame_drawn+1)...session.frames.length) {
      var frame = session.frames[i];

      if (Reflect.hasField(frame, "mem")) {
        //trace(frame.mem); // mem debug
        for (key in mem_types) {
          if (Reflect.hasField(frame.mem, key)) {
            session.temp_running_mem.set(key, Reflect.field(frame.mem, key));
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

      var s = timing_shapes[Math.floor(i/16)];
      var m = new flash.geom.Matrix();
      //m.translate(0, 0);
      var sc:Float = nav_pane.innerHeight/timing_pane.innerHeight;
      m.scale(nav_scalex*1/layout.frame_width, sc);
      m.translate(0, nav_pane.innerHeight);

      cast(nav_pane.cont.getChildAt(0)).bitmapData.draw(s, m, null, openfl.display.BlendMode.LIGHTEN);
      cast(nav_pane.cont.getChildAt(0)).bitmapData.draw(s, m);
      cast(nav_pane.cont.getChildAt(0)).bitmapData.draw(s, m);

      if (!session.temp_running_mem.exists("total")) continue;

      // trace(session.temp_running_mem); // mem debug

      add_rect(i, memory_pane, session.temp_running_mem.get("total")/layout.MSCALE, 0x444444, false);             // Current Total Memory
      add_rect(i, memory_pane, session.temp_running_mem.get("telemetry.overhead")/layout.MSCALE, 0x667755, true); // In other?
      add_rect(i, memory_pane, session.temp_running_mem.get("bitmap")/layout.MSCALE, 0x22aa99, true);             // TODO: category
      add_rect(i, memory_pane, session.temp_running_mem.get("managed.used")/layout.MSCALE, 0x227788, true);       // ActionScript Objects
    }
    last_frame_drawn = session.frames.length-1;

    // display only those shapes in view
    var idx:Int = Math.floor(i/16);
    while (timing_pane.cont.numChildren>0) timing_pane.cont.removeChildAt(0);
    while (memory_pane.cont.numChildren>0) memory_pane.cont.removeChildAt(0);
    var i0 = Math.floor((timing_pane.cont.scrollRect.x)/(16*layout.frame_width));
    for (offset in 0...Math.ceil(timing_pane.innerWidth/(layout.frame_width*16))+1) {
      i = offset + i0;
      if (i>=0 && i<timing_shapes.length) timing_pane.cont.addChild(timing_shapes[i]);
      if (i>=0 && i<memory_shapes.length) memory_pane.cont.addChild(memory_shapes[i]);
    }

    // scale nav cont to fit
    if (last_frame_drawn*nav_scalex > nav_pane.innerWidth*0.97) {
      var rescale = 0.9;
      var bd:BitmapData = new BitmapData(2048, layout.nav.height, true, 0x0);
      var m = new flash.geom.Matrix();
      m.scale(rescale, 1);
      bd.draw(nav_pane.cont, m, null, null, null, true);
     
      cast(nav_pane.cont.getChildAt(0)).bitmapData.dispose();
      cast(nav_pane.cont.getChildAt(0)).bitmapData = bd;
      nav_scalex *= rescale;
    }
  }

  private var stack_y:Float = 0;
  private var timing_shapes:Array<Shape> = [];
  private var memory_shapes:Array<Shape> = [];
  private inline function add_rect(id:Int, pane:Pane, value:Float, color:Int, stack:Bool) {
    if (!stack) stack_y = 0;

    var idx:Int = Math.floor(id/16);
    var arr = (pane==timing_pane) ? timing_shapes : memory_shapes;
    while (arr.length<=idx) arr.push(new Shape());
    var s:Shape = arr[idx];

    s.graphics.beginFill(color);
    s.graphics.drawRect(id*layout.frame_width,-value-stack_y,layout.frame_width-1,value);
    s.graphics.endFill();

    if (stack) stack_y += value;
  }
}

class NavController {
  private var nav_pane:Pane;
  private var timing_pane:Pane;
  private var memory_pane:Pane;
  private var sel_ctrl:SelectionController;
  private var get_nav_factor:Void->Float;

  public function new (nav_pane, timing_pane, memory_pane, sel_ctrl, get_nav_factor):Void
  {
    this.nav_pane = nav_pane;
    this.timing_pane = timing_pane;
    this.memory_pane = memory_pane;
    this.sel_ctrl = sel_ctrl;
    this.get_nav_factor = get_nav_factor;

    AEL.add(nav_pane, MouseEvent.MOUSE_DOWN, handle_nav_start);
  }

  function handle_nav_start(e:Event)
  {
    nav_pane.stage.addEventListener(MouseEvent.MOUSE_MOVE, handle_nav_move);
    nav_pane.stage.addEventListener(MouseEvent.MOUSE_UP, handle_nav_stop);

    nav_to(nav_pane.mouseX);
  }

  function handle_nav_stop(e:Event)
  {
    nav_pane.stage.removeEventListener(MouseEvent.MOUSE_MOVE, handle_nav_move);
    nav_pane.stage.removeEventListener(MouseEvent.MOUSE_UP, handle_nav_stop);
  }

  function handle_nav_move(e:Event)
  {
    nav_to(nav_pane.mouseX);
  }

  function nav_to(x:Float)
  {
    //trace("Nav to: "+x);
    timing_pane.cont.scrollRect.x = -x;

    var r = new flash.geom.Rectangle();
    r.copyFrom(timing_pane.cont.scrollRect);
    r.x = x*get_nav_factor(); // layout.frame_width
    timing_pane.cont.scrollRect = r;
    memory_pane.cont.scrollRect = r;

    sel_ctrl.redraw();
  }
}

class SelectionController {
  private var nav_pane:Pane;
  private var timing_pane:Pane;
  private var memory_pane:Pane;
  private var detail_pane:Pane;
  private var summary_pane:Pane;
  private var layout:Dynamic;
  private var get_active_session:Void->FLMSession;

  private var selection:Shape;
  public var start_sel:Int;
  public var end_sel:Int;

  public function new (nav_pane, timing_pane, memory_pane, detail_pane, summary_pane, layout,
                       get_active_session):Void
  {
    this.nav_pane = nav_pane;
    this.timing_pane = timing_pane;
    this.memory_pane = memory_pane;
    this.detail_pane = detail_pane;
    this.summary_pane = summary_pane;
    this.layout = layout;
    this.get_active_session = get_active_session;

    AEL.add(timing_pane, MouseEvent.MOUSE_DOWN, handle_select_start);
    AEL.add(memory_pane, MouseEvent.MOUSE_DOWN, handle_select_start);

    selection = new Shape();
    memory_pane.addChild(selection);

    Util.stage.addEventListener(Event.ENTER_FRAME, handle_enter_frame);
  }

  function handle_select_start(e:Event)
  {
    selection.stage.addEventListener(MouseEvent.MOUSE_MOVE, handle_select_move);
    selection.stage.addEventListener(MouseEvent.MOUSE_UP, handle_select_stop);

    select_at(timing_pane.cont.mouseX, !cast(e).shiftKey);
  }

  function handle_select_stop(e:Event)
  {
    selection.stage.removeEventListener(MouseEvent.MOUSE_MOVE, handle_select_move);
    selection.stage.removeEventListener(MouseEvent.MOUSE_UP, handle_select_stop);
  }

  function handle_select_move(e:Event)
  {
    select_at(timing_pane.cont.mouseX, false);
  }

  function select_at(x:Float, start_selection:Bool=true)
  {
    var num:Int = 1+Math.floor((x-2)/layout.frame_width);
    //trace("Select at: "+x+" num="+num);
    if (start_selection) start_sel = num;
    end_sel = num;

    redraw();
  }

  private var invalid:Bool = false;
  public function redraw() { invalid = true; }
  private function handle_enter_frame(e:Event):Void
  {
    if (!invalid) return;
    invalid = false;

    var start = Std.int(Math.min(start_sel, end_sel));
    var end = Std.int(Math.max(start_sel, end_sel));

    selection.graphics.clear();
    while (detail_pane.cont.numChildren>0) detail_pane.cont.removeChildAt(0);
    while (summary_pane.cont.numChildren>0) summary_pane.cont.removeChildAt(0);
    detail_pane.cont.graphics.clear();

    var session:FLMSession = get_active_session();
    if (session==null) return;

    if (start<1) start=1;
    if (end>session.frames.length) end = session.frames.length;

    var frame:Dynamic = session.frames[start-1];
    var end_frame:Dynamic = session.frames[end-1];
    if (frame==null || end_frame==null) return;

    var num_frames:Int = end-start+1;

    var sy:Float = -layout.timing.height+2;
    selection.y = sy;
    selection.scrollRect = new flash.geom.Rectangle(0,sy,timing_pane.width,2*layout.timing.height-3);
    selection.graphics.lineStyle(1, 0xffffff, 0.5);
    selection.graphics.beginFill(0xffffff, 0.15);
    selection.graphics.drawRect(start*layout.frame_width - timing_pane.cont.scrollRect.x,
                                sy,
                                layout.frame_width*num_frames,
                                2*layout.timing.height-5);

    // Update summary, samples, etc
    //trace(frame);

    inline function each_frame(f:Dynamic->Void):Void {
      var idx;
      for (idx in start...end+1) f(session.frames[idx-1]);
    }

    // - - Summary pane - -
    if (frame.duration!=null) {
      var lbl = Util.make_label("Framerate", 12, 0x777777, -1, "DroidSans-Bold.ttf");
      lbl.y = 0;
      lbl.x = 0;
      summary_pane.cont.addChild(lbl);

      var total = 0;
      each_frame(function(f) { total += f.duration.total; });

      var unit:Int = Math.floor(num_frames*1000000/total);
      var dec:Int = Math.floor(num_frames*10000000/total)-10*unit;
      var fps = Util.make_label((unit+"."+dec+" fps"), 18, 0xeeeeee);
      fps.y = lbl.height;
      fps.x = 0;
      summary_pane.cont.addChild(fps);

      var flbl = Util.make_label("Frame"+(start==end?"":"s"), 12, 0x777777, -1, "DroidSans-Bold.ttf");
      flbl.y = 0;
      flbl.x = lbl.x + lbl.width*1.4;
      summary_pane.cont.addChild(flbl);

      var ftxt = Util.make_label(start+(start==end?"":" - "+end), 12, 0xeeeeee, -1, "DroidSans-Bold.ttf");
      ftxt.y = 0;
      ftxt.x = flbl.x + flbl.width*1.15;
      summary_pane.cont.addChild(ftxt);

      var tlbl = Util.make_label("Time", 12, 0x777777, -1, "DroidSans-Bold.ttf");
      tlbl.y = fps.y + fps.height - tlbl.height;
      tlbl.x = lbl.x + lbl.width*1.4;
      summary_pane.cont.addChild(tlbl);

      var t = time_format(frame.offset)+" - "+time_format(end_frame.offset+end_frame.duration.total);

      var ttxt = Util.make_label(t, 12, 0xeeeeee, -1, "DroidSans-Bold.ttf");
      ttxt.y = tlbl.y;
      ttxt.x = ftxt.x;
      summary_pane.cont.addChild(ttxt);

    }

    // - - Detail / Samples pane - -
    var top_down = new SampleData();
    each_frame(function(f) {
      if (f.top_down!=null) SampleData.merge_sample_data(top_down, f.top_down);
    });

    var total:Float = 0;
    each_frame(function(f) { total += f.duration.as/1000; });

    var y:Float = 0;
    var ping = true;
    function display_samples(ptr:SampleData, indent:Int=0):Void
    {
      var keys = ptr.children.keys();
      for (i in keys) {
        var sample = ptr.children.get(i);

        var lbl = Util.make_label(session.stack_strings[i], 12, 0x66aadd);
        lbl.y = y;
        lbl.x = indent*15;
        detail_pane.cont.addChild(lbl);

        ping = !ping;
        if (ping) {
          detail_pane.cont.graphics.beginFill(0xffffff, 0.02);
          detail_pane.cont.graphics.drawRect(0,y,detail_pane.innerWidth,lbl.height);
        }

        // I'd use round, but Scout seems to use floor
        var pct = Math.max(0, Math.min(100, Math.floor(100*sample.total_time/total)))+"%";
        var x:Float = detail_pane.innerWidth - 20;
        lbl = Util.make_label(pct, 12, 0xeeeeee);
        lbl.y = y;
        lbl.x = x - lbl.width;
        detail_pane.cont.addChild(lbl);
        x -= 60;

        lbl = Util.make_label(cast(sample.total_time), 12, 0xeeeeee);
        lbl.y = y;
        lbl.x = x - lbl.width;
        detail_pane.cont.addChild(lbl);
        x -= 80;

        // I'd use round, but Scout seems to use floor
        var pct = Math.max(0, Math.min(100, Math.floor(100*sample.self_time/total)))+"%";
        lbl = Util.make_label(pct, 12, 0xeeeeee);
        lbl.y = y;
        lbl.x = x - lbl.width;
        detail_pane.cont.addChild(lbl);
        x -= 60;

        lbl = Util.make_label(cast(sample.self_time), 12, 0xeeeeee);
        lbl.y = y;
        lbl.x = x - lbl.width;
        detail_pane.cont.addChild(lbl);

        y += lbl.height;
        display_samples(sample, indent+1);
      }
    }
    display_samples(top_down);
  }

  public static function time_format(usec):String
  {
    var sec:Float = usec/1000000;
    var rtn = "";
    var min = Math.floor(sec/60);
    rtn += min+":";
    sec = sec%60;
    if (sec<10) rtn += "0";
    rtn += Math.floor(sec)+".";
    var dec = Math.floor((sec%1)*1000);
    if (dec<1) rtn += "000";
    else if (dec<10) rtn += "00";
    else if (dec<100) rtn += "0";
    rtn += dec;
    return rtn;
  }
}

class Pane extends Sprite {

  public static inline var PAD:Float = 6;

  public var cont(get, null):Sprite;
  var backdrop:Shape;
  var scrollbars:Sprite;

  var _width:Float;
  var _height:Float;
  var _bottom_aligned:Bool;
  var _scrollbarx:Bool;
  var _scrollbary:Bool;
  var _scroll_invalid:Bool;

  public function new (bottom_aligned:Bool=false, scrollbarx:Bool=false, scrollbary:Bool=false, w:Float=0, h:Float=0)
  {
    super();
    _bottom_aligned = bottom_aligned;
    _width = w;
    _height = h;
    _scrollbarx = scrollbarx;
    _scrollbary = scrollbary;

    backdrop = new Shape();
    addChild(backdrop);

    cont = new Sprite();
    addChild(cont);
    cont.scrollRect = new flash.geom.Rectangle(0,_bottom_aligned?-h:h,w,h);
    cont.x = cont.y = PAD;

    scrollbars = new Sprite();
    addChild(scrollbars);

    AEL.add(this, MouseEvent.MOUSE_WHEEL, handle_scroll_wheel);
    Util.stage.addEventListener(Event.ENTER_FRAME, handle_enter_frame);

    resize();
  }

  override public function set_width(w:Float):Float { _width = w; resize(); return w; }
  override public function get_width():Float { return _width; }
  override public function set_height(h:Float):Float { _height = h; resize(); return h; }
  override public function get_height():Float { return _height; }

  public var innerWidth(get, null):Float;
  public var innerHeight(get, null):Float;
  public function get_innerWidth():Float { return _width-2*PAD; }
  public function get_innerHeight():Float { return _height-2*PAD; }

  static var TEMP_M:flash.geom.Matrix = new flash.geom.Matrix();

  public function get_cont():Sprite {
    _scroll_invalid = true;
    return cont;
  }

  private function handle_scroll_wheel(e:Event):Void
  {
    //trace("wheel event, delta="+cast(e).delta+", sby="+_scrollbary+", scrollrect.y="+cont.scrollRect.y);
    var r = cont.scrollRect;
    // TODO: bottom_aligned support?, +=h laster, -=h
    if (_scrollbary) {
      r.y += (cast(e).delta<0) ? 15 : -15;
      limit_scrolly(r);
    } else if (_scrollbarx) {
      r.x += (cast(e).delta<0) ? 15 : -15;
      limit_scrollx(r);
    }
    cont.scrollRect = r;
    _scroll_invalid = true;
  }

  private function max_scroll_y():Float {
    var rect = cont.scrollRect;
    var bounds = cont.getBounds(cont);
    return Math.max(0, bounds.height-rect.height);
  }

  private function max_scroll_x():Float {
    var rect = cont.scrollRect;
    var bounds = cont.getBounds(cont);
    return Math.max(0, bounds.width-rect.width);
  }

  private function handle_enter_frame(e:Event):Void
  {
    if (!_scroll_invalid) return;

    var rect = cont.scrollRect;
    var bounds = cont.getBounds(cont);

    scrollbars.graphics.clear();
    if (_scrollbary && rect.height<bounds.height) {
      scrollbars.graphics.beginFill(0xffffff,0.2);
      scrollbars.graphics.drawRoundRect(rect.width+1,
                                        PAD,
                                        PAD,
                                        rect.height,
                                        PAD);
      var pct = rect.height/bounds.height;
      var scrollbar_h = (rect.height/10)*(1-pct) + (rect.height)*pct;
      var scroll_pct = rect.y/(bounds.height-rect.height);
      var scroll_y = (rect.height-scrollbar_h)*scroll_pct;
      scrollbars.graphics.drawRoundRect(rect.width+1,
                                        PAD+scroll_y,
                                        PAD,
                                        scrollbar_h,
                                        PAD);
    }
    if (_scrollbarx && rect.width<bounds.width) {
      scrollbars.graphics.beginFill(0xffffff,0.2);
      scrollbars.graphics.drawRoundRect(PAD,
                                        rect.height+1,
                                        rect.width,
                                        PAD,
                                        PAD);
      var pct = rect.width/bounds.width;
      var scrollbar_w = (rect.width/10)*(1-pct) + (rect.width)*pct;
      var scroll_pct = rect.x/(bounds.width-rect.width);
      var scroll_x = (rect.width-scrollbar_w)*scroll_pct;
      scrollbars.graphics.drawRoundRect(PAD+scroll_x,
                                        rect.height+1,
                                        scrollbar_w,
                                        PAD,
                                        PAD);
    }

    _scroll_invalid = false;
  }

  private inline function limit_scrollx(r:flash.geom.Rectangle):Void
  {
    if (r.x<0) r.x=0;
    if (r.x>max_scroll_x()) r.x=max_scroll_x();
  }

  private inline function limit_scrolly(r:flash.geom.Rectangle):Void
  {
    if (r.y<0) r.y=0;
    if (r.y>max_scroll_y()) r.y=max_scroll_y();
  }

  private function resize()
  {
    var r = new flash.geom.Rectangle(cont.scrollRect.x,
                                     _bottom_aligned ? -(_height-2*PAD) : cont.scrollRect.y,
                                     _width-2*PAD,
                                     _height-2*PAD);

    // Ensure scroll stays in bounds during resize
    if (_scrollbarx) limit_scrollx(r);
    if (_scrollbary) limit_scrolly(r);
    cont.scrollRect = r;

    backdrop.graphics.clear();
    backdrop.graphics.lineStyle(3, 0x111111);

    TEMP_M.identity();
    TEMP_M.createGradientBox(_width,_height,Math.PI/180*(-90));
    backdrop.graphics.beginGradientFill(openfl.display.GradientType.LINEAR,
                                     [0x444444, 0x535353],
                                     [1, 1],
                                     [0,255],
                                     TEMP_M);

    backdrop.graphics.drawRoundRect(0,0,_width,_height, 7);

    // cont knockout
    var p:Float = PAD/2;
    backdrop.graphics.lineStyle(0,0, 0);
    backdrop.graphics.beginFill(0x000000, 0.25);
    backdrop.graphics.drawRoundRect(p,p,_width-p*2,_height-p*2,5);

  }
}
