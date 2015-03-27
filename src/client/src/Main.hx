package;

import flash.display.*;
import flash.events.*;

import openfl.net.Socket;
import haxe.ds.StringMap;
import haxe.ds.IntMap;

import UI.Pane;
import UI.TabbedPane;
import UI.AbsTabularDataSource;
import UI.ExampleTabularDataSource;
import UI.TabularDataPane;

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

    #if cpp
      setup_flm_listener();
      setup_hxt_debug_output();
      // CPP, start server thread automatically, failover to request
      //var listener = cpp.vm.Thread.create(Server.main);
      //var s:Socket = null;
      //Sys.sleep(0.2);
      //s = setup_socket("localhost", 7933,
      //                 function() {
      //                   on_server_connected(s);
      //                 },
      //                 function() {
      //                   ui_server_request(on_server_connected);
      //                 });
    #else
      function on_server_connected(s:Socket) {
        trace("Got socket: "+s);
        addChildAt(gui = new HXScoutClientGUI(), 0);
        center();
        setup_frame_data_receiver(s);
      }

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
          send_frame_data(frame_data);
        } else {
          break;
        }
      }
    }

    stage.addEventListener(Event.ENTER_FRAME, on_enter_frame);
  }

#if cpp
  function setup_flm_listener() {
    addChildAt(gui = new HXScoutClientGUI(), 0);
    center();

    var port:Int = (Sys.args().length>0 && Sys.args().indexOf('-p')>=0) ? Std.parseInt(Sys.args()[(Sys.args().indexOf('-p')+1)]) : 7934;
    var output_port:Int = (Sys.args().length>0 && Sys.args().indexOf('-d')>=0) ? Std.parseInt(Sys.args()[(Sys.args().indexOf('-d')+1)]) : -1;

    var listener = cpp.vm.Thread.create(FLMListener.start);
    listener.sendMessage(cpp.vm.Thread.current());
    listener.sendMessage(port);
    listener.sendMessage(output_port);

    function on_enter_frame(e:Event):Void
    {
      var frame_data:Dynamic;
      while (true) {
        frame_data = cpp.vm.Thread.readMessage(false);
        if (frame_data==null) break;
        // TODO: remove JSON for non-socket
        send_frame_data(frame_data);
      }
    }

    stage.addEventListener(Event.ENTER_FRAME, on_enter_frame);
  }

  function setup_hxt_debug_output() {
    var output_port:Int = (Sys.args().length>0 && Sys.args().indexOf('-d')>=0) ? Std.parseInt(Sys.args()[(Sys.args().indexOf('-d')+1)]) : -1;
    if (output_port>0) {
      trace("Will send telemetry on port "+output_port);
      var cfg = new hxtelemetry.HxTelemetry.Config();
      //cfg.allocations = false;
      cfg.port = output_port;
      cfg.app_name = "HxScout";
      var hxt = new hxtelemetry.HxTelemetry(cfg);
    }
  }

#end

  function send_frame_data(frame_data:Dynamic):Void
  {
    //trace(frame_data);
    var inst_id:String = frame_data.inst_id;
    if (!flm_sessions.exists(inst_id)) {
      flm_sessions.set(inst_id, new FLMSession(inst_id));
      gui.add_session(flm_sessions.get(inst_id));
    }
    flm_sessions.get(inst_id).receive_frame_data(frame_data);
    if (frame_data.session_name!=null) {
      gui.update_name(frame_data.session_name, frame_data.inst_id);
      flm_sessions.get(inst_id).amf_mode = frame_data.amf_mode;
    }
  }
}

class SampleData {
  public function new(){};

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

class AllocData {
  public function new(){};

  public var total_size:Int = 0;
  public var total_num:Int = 0;
  public var children:haxe.ds.IntMap<AllocData> = new haxe.ds.IntMap<AllocData>();
  public var callstack_id:Int = 0;

  public function ensure_child(idx):AllocData
  {
    if (!children.exists(idx)) {
      var s = new AllocData();
      children.set(idx, s);
    }
    return children.get(idx);
  }
}

typedef UIState = {
  nav_x:Float,
  timing_scaley:Float,
  memory_scaley:Float,
  tab_idx:Int,
  sel_start:Int,
  sel_end:Int,
};

typedef CollatedDealloc = {
  total:Int,
  size:Int
};

class SamplesTabularDataSource extends AbsTabularDataSource
{
  private var _sample_data:SampleData;
  private var _session:FLMSession;

  public function new() {
    super();
  }

  private var _rows:Array<SampleData>;
  private var _depth:Array<Int>;
  private var _names:Array<Int>;
  public function update_sample_data(sd:SampleData, session:FLMSession):Void
  {
    _sample_data = sd;
    _session = session;

    _rows = [];
    _depth = [];
    _names = [];
    function recurse(sd:SampleData, depth:Int, idx:Int):Void
    {
      if (depth>=0) {
        _rows.push(sd);
        _depth.push(depth);
        _names.push(idx);
      }
      var keys = sd.children.keys();
      for (i in keys) {
        var child:SampleData = sd.children.get(i);
        recurse(child, depth+1, i);
      }
    }
    recurse(sd, -1, -1);
  }

  private static var labels:Array<String> = ["Self Time (ms)", "Total Time (ms)"];
  override public function get_labels():Array<String> { return labels; }

  override public function get_num_rows():Int
  {
    return _rows==null ? 0 : _rows.length;
  }

  override public function get_num_cols():Int { return 2; }

  override public function get_indent(row_idx:Int):Int
  {
    return _depth[row_idx];
  }

  override public function get_row_value(row_idx:Int, col_idx:Int):Float
  {
    return col_idx==0 ? _rows[row_idx].self_time : _rows[row_idx].total_time;
  }

  override public function get_row_name(row_idx:Int):String
  {
    return _session.stack_strings[_names[row_idx]];
  }
}

class AllocsTabularDataSource extends AbsTabularDataSource
{
  private var _session:FLMSession;

  public function new() {
    super();
  }

  private var _rows:Array<AllocData>;
  private var _depth:Array<Int>;
  private var _names:Array<Int>;
  public function update_alloc_data(iad:IntMap<AllocData>, session:FLMSession):Void
  {
    _session = session;

    _rows = [];
    _depth = [];
    _names = [];
    function recurse(iad:IntMap<AllocData>, depth:Int):Void
    {
      var keys = iad.keys();
      for (type_id in keys) {
        var ad:AllocData = iad.get(type_id);
        _rows.push(ad);
        _depth.push(depth);
        _names.push(type_id);
        recurse(ad.children, depth+1);
      }
    }
    recurse(iad, 0);
  }

  private static var labels:Array<String> = ["Count", "Memory (kb)"];
  override public function get_labels():Array<String> { return labels; }

  override public function get_num_rows():Int
  {
    return _rows==null ? 0 : _rows.length;
  }

  override public function get_num_cols():Int { return 2; }

  override public function get_indent(row_idx:Int):Int
  {
    return _depth[row_idx];
  }

  override public function get_row_value(row_idx:Int, col_idx:Int):Float
  {
    return col_idx==0 ? _rows[row_idx].total_num : _rows[row_idx].total_size;
  }

  override public function get_row_name(row_idx:Int):String
  {
    return _session.stack_strings[_names[row_idx]];
  }
}

class DeallocsTabularDataSource extends AbsTabularDataSource
{
  private var _session:FLMSession;

  public function new() {
    super();
  }

  private var _rows:Array<CollatedDealloc>;
  private var _depth:Array<Int>;
  private var _names:Array<Int>;
  public function update_dealloc_data(icd:IntMap<CollatedDealloc>, session:FLMSession):Void
  {
    _session = session;

    _rows = [];
    _names = [];

    var keys = icd.keys();
    for (type_id in keys) {
      var cd:CollatedDealloc = icd.get(type_id);
      _rows.push(cd);
      _names.push(type_id);
    }
  }

  private static var labels:Array<String> = ["Count", "Memory (kb)"];
  override public function get_labels():Array<String> { return labels; }

  override public function get_num_rows():Int
  {
    return _rows==null ? 0 : _rows.length;
  }

  override public function get_num_cols():Int { return 2; }

  override public function get_indent(row_idx:Int):Int
  {
    return 0;
  }

  override public function get_row_value(row_idx:Int, col_idx:Int):Float
  {
    return col_idx==0 ? _rows[row_idx].total : _rows[row_idx].size;
  }

  override public function get_row_name(row_idx:Int):String
  {
    return _session.stack_strings[_names[row_idx]];
  }
}

class FLMSession {

  public var frames:Array<FLMListener.Frame> = [];
  public var inst_id:String;
  public var amf_mode:Bool = true;
  public var temp_running_mem:StringMap<Int>;
  public var name:String;
  public var stack_strings:Array<String> = ["1-indexed"];
  public var stack_maps:Array<Array<Int>> = new Array<Array<Int>>();
  public var ses_tile:Sprite;
  public var ui_state:UIState;

  // Allocation IDs are actually, memory addresses, which can be reused,
  // so map them to guid's as soon as they arrive.
  private var alloc_guid:Int = 1;
  // This lookup can only be used as soon as the data arrives.
  public var alloc_id_to_guid:IntMap<Int> = new IntMap<Int>();
  public var alloc_guid_to_newalloc:IntMap<FLMListener.NewAlloc> = new IntMap<FLMListener.NewAlloc>();

  public function new(iid:String)
  {
    inst_id = iid;
    name = inst_id;
  }

  public function receive_frame_data(data:Dynamic)
  {
    if (data.session_name!=null) {
      name = data.session_name;
      return; // Not really frame data...
    }

    var frame_data:FLMListener.Frame = data;

    // For profiler samples && memory allocation stacks...
    if (frame_data.push_stack_strings!=null) {
      var strings:Array<String> = frame_data.push_stack_strings;
      for (str in strings) {
        stack_strings.push(str);
      }
    }

    // For memory alloc stacks...
    if (frame_data.push_stack_maps!=null) {
      var maps:Array<Array<Int>> = frame_data.push_stack_maps;
      for (map in maps) {
        stack_maps.push(map);
      }
    }

    if (frame_data.samples!=null && frame_data.samples.length>0) collate_sample_data(frame_data);
    if (frame_data.mem_dealloc.length>0 || frame_data.mem_alloc.length>0) collate_alloc_data(frame_data);

    frames.push(frame_data);
  }

  private function collate_sample_data(frame_data:FLMListener.Frame):Void
  {
    //trace(haxe.Json.stringify(frame_data.samples, null, "  "));
    var samples:Array<FLMListener.SampleRaw> = frame_data.samples;

    var top_down = new SampleData();
    frame_data.prof_top_down = top_down;
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
    //print_samples(frame_data.prof_top_down);

    // not yet used...
    //  var bottom_up = new SampleData();
    //  frame_data.prof_bottom_up = bottom_up;
    //  for (sample in samples) {
    //    var numticks:Int = sample.get("numticks");
    //    var callstack:Array<Int> = sample.get("callstack");
    //    var ptr:SampleData = bottom_up;
    //    var i:Int = -1;
    //    while ((++i)<callstack.length) {
    //      var idx = callstack[i];
    //      ptr.ensure_child(idx);
    //      ptr.children.get(idx).self_time += numticks;
    //      ptr = ptr.children.get(idx);
    //    }
    //  }

    //trace("Bottom Up, frame "+(frames.length+1));
    //print_samples(frame_data.prof_bottom_up);
  }

  private function collate_alloc_data(frame_data:FLMListener.Frame):Void
  {
    //trace(haxe.Json.stringify(frame_data.alloc, null, "  "));
    var news:Array<FLMListener.NewAlloc> = frame_data.mem_alloc;
    //var updates:Array<Dynamic> = frame_data.alloc.updateObject;
    var dels:Array<FLMListener.DelAlloc> = frame_data.mem_dealloc;

    // Bottom-up objects by type
    var bottom_up = new IntMap<AllocData>();
    frame_data.alloc_bottom_up = bottom_up;
    if (news!=null) {
      for (i in 0...news.length) {
        var item:FLMListener.NewAlloc = news[i];
        if (!bottom_up.exists(item.type)) bottom_up.set(item.type, new AllocData());
        var ad:AllocData = bottom_up.get(item.type);
        ad.total_size += item.size;
        ad.total_num++;
        //trace("collate allocation: "+item);

        // Track with guid
        if (!alloc_id_to_guid.exists(item.id)) {
          item.guid = (alloc_guid++);
          alloc_id_to_guid.set(item.id, item.guid);
          alloc_guid_to_newalloc.set(item.guid, item);
        }

        var id = item.stackid;
        var callstack:Array<Int> = this.stack_maps[id];
        if (callstack==null) {
          if (this.stack_strings[item.type]!="[object Event]") trace("- warning: null callstack for "+this.stack_strings[item.type]+" on frame id="+frame_data.id+", stack map id "+id+" > length "+this.stack_maps.length);
          continue;
        }
        //trace(" - type "+item.type+", callstack="+callstack);

        //trace("New "+item.type+"=="+stack_strings[item.type]+" from stackid="+id+", ["+callstack+"], "+stack_strings[callstack[0]]);

        var ptr:AllocData = ad;
        for (j in 0...callstack.length) {
          ptr = ptr.ensure_child(callstack[j]);
          ptr.total_size += item.size;
          ptr.total_num++;
          ptr.callstack_id = callstack[j];
        }
      }
    }

    if (dels!=null) {
      for (del in dels) {
        // Convert ID to GUID, allocs guaranteed already seen
        del.guid = alloc_id_to_guid.get(del.id);
      }
    }

    // TODO: top-down allocs
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
  private var detail_pane:TabbedPane;
  private var sample_pane:TabularDataPane;
  private var alloc_pane:TabularDataPane;
  private var dealloc_pane:TabularDataPane;

  private var active_session = -1;
  private var last_frame_drawn = -1;
  private var nav_scalex:Float = 1;

  private var nav_ctrl:NavController;
  private var sel_ctrl:SelectionController;
  private var detail_ui:DetailUI;

  public var samples_data_source:SamplesTabularDataSource;
  public var allocs_data_source:AllocsTabularDataSource;
  public var deallocs_data_source:DeallocsTabularDataSource;

  public function new()
  {
    super();

    nav_pane = new Pane();
    summary_pane = new Pane(false, false, true); // scrolly
    timing_pane = new Pane(true);
    memory_pane = new Pane(true);
    session_pane = new Pane(false, false, true); // scrolly
    detail_pane = new TabbedPane();

    samples_data_source = new SamplesTabularDataSource();
    sample_pane = new TabularDataPane(samples_data_source);
    //sample_pane = new TabularDataPane(new ExampleTabularDataSource());
    sample_pane.outline = 0;
    sample_pane.outline_alpha = 0.75;
    sample_pane.name = "Profiler";

    allocs_data_source = new AllocsTabularDataSource();
    alloc_pane = new TabularDataPane(allocs_data_source);
    alloc_pane.outline = 0;
    alloc_pane.outline_alpha = 0.75;
    alloc_pane.name = "Allocations";

    deallocs_data_source = new DeallocsTabularDataSource();
    dealloc_pane = new TabularDataPane(deallocs_data_source);
    dealloc_pane.outline = 0;
    dealloc_pane.outline_alpha = 0.75;
    dealloc_pane.name = "Collections";

    addChild(session_pane);
    addChild(nav_pane);
    addChild(summary_pane);
    addChild(timing_pane);
    addChild(memory_pane);

    addChild(detail_pane);

    detail_pane.add_pane(sample_pane);
    detail_pane.add_pane(alloc_pane);
    detail_pane.add_pane(dealloc_pane);
    detail_pane.select_tab(0);

    sel_ctrl = new SelectionController(nav_pane, timing_pane, memory_pane, sample_pane, alloc_pane, dealloc_pane, summary_pane, layout, get_active_session);
    nav_ctrl = new NavController(nav_pane, timing_pane, memory_pane, sel_ctrl, layout, get_active_session, function() { return layout.frame_width/nav_scalex; }, function() { var tmp = active_session; set_active_session(-1); set_active_session(tmp); });
    detail_ui = new DetailUI(detail_pane, sample_pane, alloc_pane, sel_ctrl);

    addEventListener(Event.ENTER_FRAME, on_enter_frame);
  }

  private function get_active_session():FLMSession { return active_session<0 ? null : sessions[active_session]; }

  private var layout = {
    nav:{
      height:50,
    },
    timing:{
      height:180,
      scale:300
    },
    session:{
      width:200,
    },
    summary:{
      width:300,
    },
    frame_width:5,
    mscale:200
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

    // This now occurs via TabbedPane
    //resize_pane(0, 0, sample_pane,  0, 20, detail_pane.innerWidth, detail_pane.innerHeight-20);
    //resize_pane(0, 0, alloc_pane,  0, 20, detail_pane.innerWidth, detail_pane.innerHeight-20);

    if (stage!=null) {
      sel_ctrl.redraw();
      //nav_ctrl.redraw();
    }
    detail_ui.resize();
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
    lbl.filters = [Util.TEXT_SHADOW];
    var ses:Sprite = cast(session_pane.cont.getChildAt(Std.parseInt(inst_id)));
    lbl.y = ses.height/2-lbl.height/2;
    lbl.x = 4;
    lbl.mouseEnabled = false;
    ses.addChild(lbl);

    var stop = new Sprite();
    Util.begin_gradient(stop.graphics, 16, 16, 0xee0000, 0xff3333);
    stop.graphics.lineStyle(1, 0xcc0000);
    stop.graphics.drawRoundRect(0,0,16,16, 3);
    stop.x = ses.width-stop.width-6;
    stop.y = ses.height/2-stop.height/2;
    stop.name = "stop";
    ses.addChild(stop);

    function stop_clicked(e) {
      PubSub.publish("stop_session", { inst_id:inst_id });
    }
    function disable_stop() {
      stop.mouseEnabled = false;
      stop.graphics.clear();
      Util.begin_gradient(stop.graphics, 16, 16, 0x777777, 0xaaaaaa);
      stop.graphics.lineStyle(1, 0x555555);
      stop.graphics.drawRoundRect(0,0,16,16, 3);
      AEL.remove(stop, MouseEvent.CLICK, stop_clicked);
    }
    AEL.add(stop, MouseEvent.CLICK, stop_clicked);
    PubSub.subscribe("flm_listener_closed", function(data:Dynamic):Void {
      if (data.inst_id == inst_id) disable_stop();
    });

  }

  public function add_session(flm_session:FLMSession)
  {
    trace("GUI got new session: "+flm_session.inst_id);
    var s:Sprite = flm_session.ses_tile = new Sprite();
    sessions.push(flm_session);
    if (active_session<0) {
      set_active_session(sessions.length-1);
    }

    Util.begin_gradient(s.graphics, session_pane.innerWidth, 42);
    s.graphics.lineStyle(2, 0x555555);
    s.graphics.drawRect(0,0,session_pane.innerWidth,42);
    s.buttonMode = true;
    AEL.add(s, MouseEvent.CLICK, function(e) { set_active_session(s.parent.getChildIndex(s)); });
    s.y = (sessions.length-1)*46;
    session_pane.cont.addChild(s);
  }

  public function set_active_session(n:Int)
  {
    if (active_session==n) return;
    if (n>=sessions.length) return; // invalid

    if (active_session>=0) { // save current ui_state
      var session:FLMSession = sessions[active_session];
      session.ui_state = { nav_x:timing_pane.cont.scrollRect.x,
                           timing_scaley:nav_ctrl.timing_scaley,
                           memory_scaley:nav_ctrl.memory_scaley,
                           tab_idx:detail_pane.selected_tab,
                           sel_start:sel_ctrl.start_sel,
                           sel_end:sel_ctrl.end_sel };
    }

    for (i in 0...sessions.length) {
      sessions[i].ses_tile.transform.colorTransform = i==n ? new openfl.geom.ColorTransform(1,1.03,1.08,1,20,20,20) : null;
      if (sessions[i].ses_tile.numChildren>0) sessions[i].ses_tile.getChildAt(0).alpha = 1;
    }

    active_session = n;
    last_frame_drawn = -1;
    sel_ctrl.start_sel = sel_ctrl.end_sel = -1;
    while (timing_pane.cont.numChildren>0) timing_pane.cont.removeChildAt(0);
    timing_pane.cont.graphics.clear();
    while (memory_pane.cont.numChildren>0) memory_pane.cont.removeChildAt(0);
    //while (sample_pane.cont.numChildren>0) sample_pane.cont.removeChildAt(0);
    while (summary_pane.cont.numChildren>0) summary_pane.cont.removeChildAt(0);
    //sample_pane.cont.graphics.clear();

    timing_shapes = [];
    memory_shapes = [];

    reset_nav_pane();
    resize(stage.stageWidth, stage.stageHeight);

    if (n<0) return; // -1 is idle / no active session

    var session:FLMSession = sessions[active_session];
    session.temp_running_mem = new StringMap<Int>();

    { nav_x:timing_pane.cont.scrollRect.x,
        timing_scaley:nav_ctrl.timing_scaley,
        memory_scaley:nav_ctrl.memory_scaley,
        tab_idx:detail_pane.selected_tab,
        sel_start:sel_ctrl.start_sel,
        sel_end:sel_ctrl.end_sel }

    // Restore ui_state
    if (session.ui_state==null) session.ui_state = { nav_x:0.0,
                                                     timing_scaley:1.0,
                                                     memory_scaley:1.0,
                                                     tab_idx:0,
                                                     sel_start:-1,
                                                     sel_end:-1 };

    var r = timing_pane.cont.scrollRect;
    r.x = session.ui_state.nav_x;
    timing_pane.cont.scrollRect = r;
    var r = memory_pane.cont.scrollRect;
    r.x = session.ui_state.nav_x;
    memory_pane.cont.scrollRect = r;
    nav_ctrl.timing_scaley = session.ui_state.timing_scaley;
    nav_ctrl.memory_scaley = session.ui_state.memory_scaley;
    detail_pane.selected_tab = session.ui_state.tab_idx;
    sel_ctrl.start_sel = session.ui_state.sel_start;
    sel_ctrl.end_sel = session.ui_state.sel_end;
    sel_ctrl.redraw();
  }

  function reset_nav_pane()
  {
    if (nav_pane.cont.numChildren<1) {
      nav_pane.cont.addChild(new Bitmap(new BitmapData(2048, layout.nav.height, true, 0x0)));
    }
    var bd:BitmapData = cast(nav_pane.cont.getChildAt(0)).bitmapData;
    bd.fillRect(new flash.geom.Rectangle(0,0,2048,layout.nav.height), 0); // clear
  }

  private function on_enter_frame(e:Event)
  {
    if (active_session<0) return;
    var i=0;
    var session:FLMSession = sessions[active_session];
    for (i in (last_frame_drawn+1)...session.frames.length) {
      var frame = session.frames[i];

      if (true) {
        for (key in SelectionController.mem_keys) {
          if (frame.mem.exists(key)) {
            session.temp_running_mem.set(key, frame.mem.get(key));
          }
          // Copy all keys back to each frame data for summary
          frame.mem.set(key, session.temp_running_mem.exists(key) ? session.temp_running_mem.get(key) : 0);
        }
        //trace("mem debug:");
        //trace(frame.mem); // mem debug
      }

      add_rect(i, timing_pane, frame.duration.total/layout.timing.scale, 0x444444, false);
      add_rect(i, timing_pane, frame.duration.gc/layout.timing.scale, 0xdd5522, true);
      add_rect(i, timing_pane, frame.duration.net/layout.timing.scale, 0xcccc66, true);
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

      //trace(session.temp_running_mem); // mem debug

      add_rect(i, memory_pane, session.temp_running_mem.get("total")/layout.mscale, 0x444444, false);             // Current Total Memory
      add_rect(i, memory_pane, session.temp_running_mem.get("telemetry.overhead")/layout.mscale, 0x667755, true); // In other?
      add_rect(i, memory_pane, session.temp_running_mem.get("script")/layout.mscale, 0x119944, true); // In other?
      add_rect(i, memory_pane, session.temp_running_mem.get("bytearray")/layout.mscale, 0x11cc77, true); // In other?
      add_rect(i, memory_pane, session.temp_running_mem.get("bitmap")/layout.mscale, 0x22aa99, true);             // TODO: category
      add_rect(i, memory_pane, session.temp_running_mem.get("managed.used")/layout.mscale, 0x227788, true);       // ActionScript Objects
    }
    last_frame_drawn = session.frames.length-1;

    // display only those shapes in view
    var idx:Int = Math.floor(i/16);
    while (timing_pane.cont.numChildren>0) timing_pane.cont.removeChildAt(0);
    while (memory_pane.cont.numChildren>0) memory_pane.cont.removeChildAt(0);
    var i0 = Math.floor((timing_pane.cont.scrollRect.x)/(16*layout.frame_width));
    for (offset in 0...Math.ceil(timing_pane.innerWidth/(layout.frame_width*16))+1) {
      i = offset + i0;
      if (i>=0 && i<timing_shapes.length) {
        timing_pane.cont.addChild(timing_shapes[i]);
        timing_shapes[i].scaleY = nav_ctrl.timing_scaley;
      }
      if (i>=0 && i<memory_shapes.length) {
        memory_pane.cont.addChild(memory_shapes[i]);
        memory_shapes[i].scaleY = nav_ctrl.memory_scaley;
      }
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
      //nav_ctrl.redraw();
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

    s.scaleY = pane==timing_pane ? nav_ctrl.timing_scaley : nav_ctrl.memory_scaley;

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
  private var get_active_session:Void->FLMSession;
  private var layout:Dynamic;
  private var on_change_layout:Void->Void;

  public var timing_scaley:Float = 1.0;
  public var memory_scaley:Float = 1.0;
  public var following:Bool = true;

  public function new (nav_pane, timing_pane, memory_pane, sel_ctrl, layout, get_active_session, get_nav_factor, on_change_layout):Void
  {
    this.nav_pane = nav_pane;
    this.timing_pane = timing_pane;
    this.memory_pane = memory_pane;
    this.sel_ctrl = sel_ctrl;
    this.layout = layout;
    this.get_nav_factor = get_nav_factor;
    this.get_active_session = get_active_session;
    this.on_change_layout = on_change_layout;

    AEL.add(nav_pane, MouseEvent.MOUSE_DOWN, handle_nav_start);
    AEL.add(nav_pane, Event.ENTER_FRAME, redraw);
    AEL.add(Util.stage, KeyboardEvent.KEY_DOWN, handle_key);

    AEL.add(timing_pane, MouseEvent.MOUSE_WHEEL, handle_zoom);
    AEL.add(memory_pane, MouseEvent.MOUSE_WHEEL, handle_zoom);
    AEL.add(timing_pane, MouseEvent.CLICK, handle_unfollow);
    AEL.add(memory_pane, MouseEvent.CLICK, handle_unfollow);
  }

  function handle_unfollow(e:Event) { following = false; }

  function handle_key(ev:Event)
  {
    var e = cast(ev, KeyboardEvent);
    //trace(e.keyCode);
    var session:FLMSession = get_active_session();
    if ((e.keyCode==39 && e.ctrlKey) || e.keyCode==35) { // ctrl-right or end
      following = true;
    }
    if ((e.keyCode==37 && e.ctrlKey) || e.keyCode==36) { // ctrl-left or home
      nav_to(0);
    }
  }

  private function handle_zoom(ev:Event):Void {
    var e:MouseEvent = cast(ev);
    if (e.shiftKey) {
      layout.frame_width += (e.delta>0) ? 1 : -1;
      layout.frame_width = Math.max(2, Math.min(8, layout.frame_width));
      on_change_layout();
      return;
    }

    // Do it this way because selection graphic is part of memory pane, so
    // e.target doesn't work.
    var p = new flash.geom.Point(timing_pane.stage.mouseX, timing_pane.stage.mouseY);
    var tp = timing_pane.globalToLocal(p);
    var pane = (tp.y>0 && tp.y<timing_pane.height) ? timing_pane : memory_pane;

    var shrink = e.delta<0;

    if (pane==timing_pane) timing_scaley *= shrink ? 0.8 : 1.2;
    if (pane==memory_pane) memory_scaley *= shrink ? 0.8 : 1.2;

    var i = -1;
    while (++i < pane.cont.numChildren) {
      pane.cont.getChildAt(i).scaleY = (pane==timing_pane) ? timing_scaley : memory_scaley;
    }
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
    nav_to(nav_pane.cont.mouseX);
  }

  function nav_to(x:Float)
  {
    following = false;

    //trace("Nav to: "+x);
    var w = timing_pane.innerWidth/get_nav_factor();
    x -= w/2;
    if (x<0) x=0;
    timing_pane.cont.scrollRect.x = -x;

    var r = new flash.geom.Rectangle();
    r.copyFrom(timing_pane.cont.scrollRect);
    r.x = x*get_nav_factor(); // layout.frame_width
    timing_pane.cont.scrollRect = r;
    memory_pane.cont.scrollRect = r;

    //redraw();

    sel_ctrl.redraw_selection();
  }

  function redraw(e:Event=null):Void
  {
    if (following && get_active_session()!=null) {
      var session = get_active_session();
      var w = timing_pane.innerWidth/get_nav_factor();      
      nav_to(session.frames.length/get_nav_factor()*layout.frame_width-w/2);
      following = true;
    }

    var g = nav_pane.scrollbars.graphics;
    var x = timing_pane.cont.scrollRect.x/get_nav_factor()+timing_pane.cont.x;
    var w = timing_pane.innerWidth/get_nav_factor();
    g.clear();

    if (get_active_session()==null) return;

    g.lineStyle(1, 0xeeeeee, 0.2);
    g.beginFill(0xeeeeee, 0.05);
    g.drawRect(x, 4, w, nav_pane.height-8);
    g.endFill();

    g.lineStyle(2, 0xeeeeee, 0.4);
    g.moveTo(x+3, 4);
    g.lineTo(x, 4);
    g.lineTo(x, nav_pane.height-4);
    g.lineTo(x+3, nav_pane.height-4);
    g.moveTo(w+x-3, 4);
    g.lineTo(w+x, 4);
    g.lineTo(w+x, nav_pane.height-4);
    g.lineTo(w+x-3, nav_pane.height-4);

    if (sel_ctrl.start_sel>0) {
      var x0:Float = sel_ctrl.start_sel;
      var x1:Float = sel_ctrl.end_sel;
      if (x1<1) x1 = 1;
      if (x0<1) x0 = 1;
      x0 = x0*layout.frame_width / get_nav_factor() + timing_pane.cont.x;
      x1 = x1*layout.frame_width / get_nav_factor() + timing_pane.cont.x;
      if (x0>x1) {
        var t = x0;
        x0 = x1;
        x1 = t;
      }
      g.beginFill(0xeeeeee, 0.1);
      g.drawRect(x0, 8, x1-x0, nav_pane.height-14);
    }
  }
}

class SelectionController {
  private var nav_pane:Pane;
  private var timing_pane:Pane;
  private var memory_pane:Pane;
  private var sample_pane:TabularDataPane;
  private var alloc_pane:TabularDataPane;
  private var dealloc_pane:TabularDataPane;
  private var summary_pane:Pane;
  private var layout:Dynamic;
  private var get_active_session:Void->FLMSession;

  private var _detail_pane:Pane;

  private var selection:Shape;
  public var start_sel:Int;
  public var end_sel:Int;

  public function new (nav_pane, timing_pane, memory_pane, sample_pane, alloc_pane, dealloc_pane, summary_pane, layout,
                       get_active_session):Void
  {
    this.nav_pane = nav_pane;
    this.timing_pane = timing_pane;
    this.memory_pane = memory_pane;
    this.sample_pane = sample_pane;
    this.alloc_pane = alloc_pane;
    this.dealloc_pane = dealloc_pane;
    this.summary_pane = summary_pane;
    this.layout = layout;
    this.get_active_session = get_active_session;

    AEL.add(timing_pane, MouseEvent.MOUSE_DOWN, handle_select_start);
    AEL.add(memory_pane, MouseEvent.MOUSE_DOWN, handle_select_start);
    AEL.add(Util.stage, KeyboardEvent.KEY_DOWN, handle_key);

    selection = new Shape();
    memory_pane.addChild(selection);

    Util.stage.addEventListener(Event.ENTER_FRAME, handle_enter_frame);
  }

  function handle_key(ev:Event)
  {
    var e = cast(ev, KeyboardEvent);
    //trace(e.keyCode);
    var session:FLMSession = get_active_session();
    if (e.ctrlKey && !e.shiftKey) return;
    if (e.keyCode==39 || e.keyCode==35) { // right or end
      if (end_sel>=session.frames.length || (!e.shiftKey && start_sel>=session.frames.length)) return;
      if (!e.shiftKey) start_sel++;
      end_sel++;
      if ((e.ctrlKey || e.keyCode==35) && e.shiftKey) end_sel = session.frames.length;
      redraw();
    } else if (e.keyCode==37 || e.keyCode==36) { // left or home
      if ((start_sel<2 && !e.shiftKey) || end_sel<2) return;
      if (!e.shiftKey) start_sel--;
      end_sel--;
      if ((e.ctrlKey || e.keyCode==36) && e.shiftKey) start_sel = 1;
      redraw();
    } else if (e.keyCode==65 && e.ctrlKey) { // ctrl-a
      start_sel = 1;
      end_sel = session.frames.length;
      redraw();
    }
  }

  function handle_select_start(e:Event)
  {
    selection.stage.addEventListener(MouseEvent.MOUSE_MOVE, handle_select_move);
    selection.stage.addEventListener(MouseEvent.MOUSE_UP, handle_select_stop);

    select_at(Math.max(layout.frame_width/2, timing_pane.cont.mouseX), !cast(e).shiftKey);
  }

  function handle_select_stop(e:Event)
  {
    selection.stage.removeEventListener(MouseEvent.MOUSE_MOVE, handle_select_move);
    selection.stage.removeEventListener(MouseEvent.MOUSE_UP, handle_select_stop);
  }

  function handle_select_move(e:Event)
  {
    select_at(Math.max(layout.frame_width/2, timing_pane.cont.mouseX), false);
  }

  function select_at(x:Float, start_selection:Bool=true)
  {
    var num:Int = 1+Math.floor((x-2)/layout.frame_width);
    //trace("Select at: "+x+" num="+num);
    if (start_selection) start_sel = num;
    end_sel = num;

    //var r = sample_pane.cont.scrollRect; r.y = 0;
    //sample_pane.cont.scrollRect = r;
    //var r = alloc_pane.cont.scrollRect; r.y = 0;
    //alloc_pane.cont.scrollRect = r;

    redraw();
  }

  // Others mem keys seen:
  // - bytearray.alchemy
  // - bitmap.image
  // - network
  // - network.shared
  // - bitmap.source

  public static var mem_keys = ["total","used","managed.used","bitmap","bytearray","script","network","telemetry.overhead","managed","bitmap.display","bitmap.data"];
  private static var mem_info = {
    "managed.used":{ name:"ActionScript Objects", hxt_name:"Haxe Objects", color:0x227788 },
    "bitmap":{ name:"Bitmap", hxt_name:"Bitmap", color:0x22aa99 },
    "telemetry.overhead":{ name:"Other", hxt_name:"Other", color:0x667755 },
    "network":{ redirect:"telemetry.overhead" }, // Also 'other', Network Buffers
    "script":{ name:"SWF Files", hxt_name:"Unexpected (SWF Files)", color:0x119944 },
    "bytearray":{ name:"ByteArrays", hxt_name:"Unexpected (ByteArrays)", color:0x11bb66 }
  }

  private static var timing_keys = ["as", "rend", "net", "gc", "other"];
  private static var timing_info = {
    "as":{ name:"ActionScript", color:0x2288cc },
    "rend":{ name:"Rendering", color:0x66aa66 },
    "net":{ name:"Network", color:0xcccc66 },
    "gc":{ name:"Garbage Collection", color:0xdd5522 },
    "other":{ name:"Other", color:0xaa4488 }
  }

  private var _prof_sort_self:Bool = false;
  public function handle_sort_self(e:Event=null):Void { _prof_sort_self = true; redraw(); }
  public function handle_sort_total(e:Event=null):Void { _prof_sort_self = false; redraw(); }

  private var _alloc_sort_count:Bool = false;
  public function handle_sort_size(e:Event=null):Void { _alloc_sort_count = false; redraw(); }
  public function handle_sort_count(e:Event=null):Void { _alloc_sort_count = true; redraw(); }

  private var selection_invalid:Bool = false;
  public function redraw_selection() { selection_invalid = true; }

  private var invalid:Bool = false;
  public function redraw() { invalid = true; }
  private function handle_enter_frame(e:Event):Void
  {
    if (invalid || selection_invalid) do_redraw();
    invalid = false;
    selection_invalid = false;
  }

  private function do_redraw():Void
  {
    //while (sample_pane.cont.numChildren>0) sample_pane.cont.removeChildAt(0);
    //sample_pane.cont.graphics.clear();
    selection.graphics.clear();

    var session:FLMSession = get_active_session();
    if (session==null) return;

    var start = Std.int(Math.min(start_sel, end_sel));
    var end = Std.int(Math.max(start_sel, end_sel));
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

    if (!invalid) return;

    //while (alloc_pane.cont.numChildren>0) alloc_pane.cont.removeChildAt(0);
    //alloc_pane.cont.graphics.clear();
    while (summary_pane.cont.numChildren>0) summary_pane.cont.removeChildAt(0);
    summary_pane.cont.graphics.clear();

    inline function each_frame(f:Dynamic->Void):Void {
      var idx;
      for (idx in start...end+1) f(session.frames[idx-1]);
    }

    // - - - - - - - - - - -
    // - - Summary pane - -
    // - - - - - - - - - -
    var total = 0;
    var active = 0;
    var durations = new StringMap<Int>();
    var mem = new StringMap<Int>();
    var mem_used = 0;
    each_frame(function(f) {
      total += f.duration.total;
      for (key in timing_keys) {
        if (!durations.exists(key)) durations.set(key, 0);
        var val = Reflect.field(f.duration, key);
        durations.set(key, durations.get(key)+val);
        active += val;
      }
      for (key in mem_keys) {
        var info = Reflect.field(mem_info, key);
        var val = f.mem.get(key);
        if (info!=null && Reflect.hasField(info, "redirect")) {
          key = Reflect.field(info, "redirect");
        }
        if (info!=null) mem_used += val;
        if (!mem.exists(key)) mem.set(key, 0);
        mem.set(key, mem.get(key)+val);
      }
    });

    // Please forgive my utter disregard for any sane variable
    // naming and reuse convention, bwa ha ha!
    var lbl = Util.make_label("Framerate", 12, 0x777777, -1, "DroidSans-Bold.ttf");
    lbl.y = 5;
    lbl.x = 10;
    summary_pane.cont.addChild(lbl);

    var unit:Int = Math.floor(num_frames*1000000/total);
    var dec:Int = Math.floor(num_frames*10000000/total)-10*unit;

    var fps = Util.make_label((unit+"."+dec+" fps"), 18, 0xeeeeee);
    fps.y = lbl.y + 18 - 4;
    fps.x = 10;
    summary_pane.cont.addChild(fps);

    var tgtlbl = Util.make_label("Target", 12, 0x777777, -1, "DroidSans-Bold.ttf");
    tgtlbl.y = lbl.y + 18*2;
    tgtlbl.x = 10;
    summary_pane.cont.addChild(tgtlbl);

    var tgtval = Util.make_label("--", 12, 0xeeeeee, -1, "DroidSans-Bold.ttf");
    tgtval.y = tgtlbl.y;
    tgtval.x = tgtlbl.x + 55;
    summary_pane.cont.addChild(tgtval);

    var flbl = Util.make_label("Frame"+(start==end?"":"s"), 12, 0x777777, -1, "DroidSans-Bold.ttf");
    flbl.y = 5;
    flbl.x = lbl.x + lbl.width*1.3;
    summary_pane.cont.addChild(flbl);

    var ftxt = Util.make_label(start+(start==end?"":" - "+end), 12, 0xeeeeee, -1, "DroidSans-Bold.ttf");
    ftxt.y = 5;
    ftxt.x = flbl.x + 55;
    summary_pane.cont.addChild(ftxt);

    var tlbl = Util.make_label("Time", 12, 0x777777, -1, "DroidSans-Bold.ttf");
    tlbl.y = lbl.y + 18;
    tlbl.x = lbl.x + lbl.width*1.3;
    summary_pane.cont.addChild(tlbl);

    var t = Util.time_format(frame.offset)+" - "+Util.time_format(end_frame.offset+end_frame.duration.total);
    var ttxt = Util.make_label(t, 12, 0xeeeeee, -1, "DroidSans-Bold.ttf");
    ttxt.y = tlbl.y;
    ttxt.x = ftxt.x;
    summary_pane.cont.addChild(ttxt);

    var cpulbl = Util.make_label("CPU", 12, 0x777777, -1, "DroidSans-Bold.ttf");
    cpulbl.y = lbl.y + 18*2;
    cpulbl.x = lbl.x + lbl.width*1.3;
    summary_pane.cont.addChild(cpulbl);

    var ctxt = Util.make_label((Math.floor(1000*frame.cpu)/10)+" %", 12, 0xeeeeee, -1, "DroidSans-Bold.ttf");
    ctxt.y = cpulbl.y;
    ctxt.x = ftxt.x;
    summary_pane.cont.addChild(ctxt);

    // Timing summary
    var ttlbl = Util.make_label("Total Frame Time", 12, 0x777777);
    ttlbl.y = lbl.y + 18*4;
    ttlbl.x = 10;
    summary_pane.cont.addChild(ttlbl);

    var tttxt = Util.make_label(Util.add_commas(Math.floor(total/1000))+" ms", 12, 0xeeeeee, -1, "DroidSans-Bold.ttf");
    tttxt.y = ttlbl.y;
    tttxt.x = ftxt.x + 30 - tttxt.width + 21;
    summary_pane.cont.addChild(tttxt);

    var tlbl = Util.make_label("Active Time", 12, 0x777777);
    tlbl.y = ttlbl.y + ttlbl.height;
    tlbl.x = 10;
    summary_pane.cont.addChild(tlbl);

    var ttxt = Util.make_label(Util.add_commas(Math.floor(active/1000))+"", 12, 0xeeeeee, -1, "DroidSans-Bold.ttf");
    ttxt.y = tlbl.y;
    ttxt.x = ftxt.x + 30 - ttxt.width;
    summary_pane.cont.addChild(ttxt);

    var y:Float = tlbl.y + tlbl.height;
    for (key in timing_keys) {
      var val = Reflect.field(timing_info, key);
      var albl = Util.make_label(session.amf_mode ? val.name : val.hxt_name, 12, val.color);
      albl.y = y;
      albl.x = 20;
      summary_pane.cont.addChild(albl);
      var aval = Util.make_label(Util.add_commas(Math.floor(durations.get(key)/1000))+"", 12, 0xeeeeee, -1, "DroidSans-Bold.ttf");
      aval.y = albl.y;
      aval.x = ftxt.x + 30 - aval.width;
      summary_pane.cont.addChild(aval);

      summary_pane.cont.graphics.beginFill(0xffffff, 0.07);
      summary_pane.cont.graphics.drawRect(10, albl.y, summary_pane.innerWidth-20, albl.height-1);
      summary_pane.cont.graphics.beginFill(val.color);
      summary_pane.cont.graphics.drawRect(10, albl.y, 5, albl.height-1);
      summary_pane.cont.graphics.drawRect(ftxt.x + 35, albl.y, ((summary_pane.innerWidth-20)-(ftxt.x + 35))/active*durations.get(key), albl.height-1);
      y += albl.height;
    }

    // Memory summary
    var ttlbl = Util.make_label("Average Total Mem", 12, 0x777777);
    ttlbl.y = y + tlbl.height;
    ttlbl.x = 10;
    summary_pane.cont.addChild(ttlbl);

    var tttxt = Util.make_label(Util.add_commas(Math.floor(mem.get("total")/num_frames))+" KB", 12, 0xeeeeee, -1, "DroidSans-Bold.ttf");
    tttxt.y = ttlbl.y;
    tttxt.x = ftxt.x + 30 - tttxt.width + 19;
    summary_pane.cont.addChild(tttxt);

    var tlbl = Util.make_label("Used Memory", 12, 0x777777);
    tlbl.y = ttlbl.y + ttlbl.height;
    tlbl.x = 10;
    summary_pane.cont.addChild(tlbl);

    var ttxt = Util.make_label(Util.add_commas(Math.floor(mem_used/num_frames))+"", 12, 0xeeeeee, -1, "DroidSans-Bold.ttf");
    ttxt.y = tlbl.y;
    ttxt.x = ftxt.x + 30 - ttxt.width;
    summary_pane.cont.addChild(ttxt);

    var y:Float = tlbl.y + tlbl.height;
    for (key in mem_keys) {
      var val = Reflect.field(mem_info, key);
      if (val==null) continue; // total and used are not in info
      if (Reflect.hasField(val, "redirect")) continue;
      var albl = Util.make_label(session.amf_mode ? val.name : val.hxt_name, 12, val.color);
      albl.y = y;
      albl.x = 20;
      summary_pane.cont.addChild(albl);
      var aval = Util.make_label(Util.add_commas(Math.floor(mem.get(key)/num_frames))+"", 12, 0xeeeeee, -1, "DroidSans-Bold.ttf");
      aval.y = albl.y;
      aval.x = ftxt.x + 30 - aval.width;
      summary_pane.cont.addChild(aval);

      summary_pane.cont.graphics.beginFill(0xffffff, 0.07);
      summary_pane.cont.graphics.drawRect(10, albl.y, summary_pane.innerWidth-20, albl.height-1);
      summary_pane.cont.graphics.beginFill(val.color);
      summary_pane.cont.graphics.drawRect(10, albl.y, 5, albl.height-1);
      summary_pane.cont.graphics.drawRect(ftxt.x + 35, albl.y, ((summary_pane.innerWidth-20)-(ftxt.x + 35))/mem.get("used")*mem.get(key), albl.height-1);
      y += albl.height;
    }

    // - - - - - - - - - - - - - - -
    // - - Samples pane - -
    // - - - - - - - - - - - - - - -
    var sample_data = new SampleData();
    var total:Float = 0;
    each_frame(function(f) {
      if (f.prof_top_down!=null) SampleData.merge_sample_data(sample_data, f.prof_top_down);
      total += f.duration.as/1000;
    });

    cast(sample_pane.data_source, SamplesTabularDataSource).update_sample_data(sample_data, session);
    sample_pane.redraw();

      // var y:Float = 0;
      // var ping = true;
      // function display_samples(ptr:SampleData, indent:Int=0):Void
      // {
      //   var keys = ptr.children.keys();
      //   var sorted:Array<Int> = new Array<Int>();
      //   for (key in keys) sorted.push(key);
      //   sorted.sort(function(i0:Int, i1:Int):Int {
      //     var sd0 = ptr.children.get(i0);
      //     var sd1 = ptr.children.get(i1);
      //     if (_prof_sort_self) return sd0.self_time > sd1.self_time ? -1 :
      //                            (sd0.self_time < sd1.self_time ? 1 : 0);
      //     return sd0.total_time > sd1.total_time ? -1 :
      //       (sd0.total_time < sd1.total_time ? 1 : 0);
      //   });
      //  
      //   for (i in sorted) {
      //     var sample = ptr.children.get(i);
      //  
      //     var cont:Sprite = new Sprite();
      //     cont.y = y;
      //     cont.x = 15+indent*15;
      //  
      //     var lbl = Util.make_label(session.stack_strings[i], 12, 0x66aadd);
      //     lbl.x = 0;
      //     cont.addChild(lbl);
      //  
      //     if (sample.children.keys().hasNext()) Util.add_collapse_button(cont, lbl, false, sample_pane.invalidate_scrollbars);
      //  
      //     ping = !ping;
      //     if (ping) {
      //       sample_pane.cont.graphics.beginFill(0xffffff, 0.02);
      //       sample_pane.cont.graphics.drawRect(0,y,sample_pane.innerWidth,lbl.height);
      //     }
      //  
      //     // I'd use round, but Scout seems to use floor
      //     var pct = Math.max(0, Math.min(100, Math.floor(100*sample.total_time/total)))+"%";
      //     var x:Float = sample_pane.innerWidth - 20 - (cont.x + 15);
      //     lbl = Util.make_label(pct, 12, 0xeeeeee);
      //     lbl.x = x - lbl.width;
      //     cont.addChild(lbl);
      //     x -= 60;
      //  
      //     lbl = Util.make_label(cast(sample.total_time), 12, 0xeeeeee);
      //     lbl.x = x - lbl.width;
      //     cont.addChild(lbl);
      //     x -= 80;
      //  
      //     // I'd use round, but Scout seems to use floor
      //     var pct = Math.max(0, Math.min(100, Math.floor(100*sample.self_time/total)))+"%";
      //     lbl = Util.make_label(pct, 12, 0xeeeeee);
      //     lbl.x = x - lbl.width;
      //     cont.addChild(lbl);
      //     x -= 60;
      //  
      //     lbl = Util.make_label(cast(sample.self_time), 12, 0xeeeeee);
      //     lbl.x = x - lbl.width;
      //     cont.addChild(lbl);
      //  
      //     sample_pane.cont.addChild(cont);
      //  
      //     y += lbl.height;
      //     display_samples(sample, indent+1);
      //   }
      // }
      // display_samples(sample_data);


    // - - - - - - - - - - - - - - -
    // - - Alloc pane deallocs (temp) - -
    // - - - - - - - - - - - - - - -
    var deallocs:IntMap<CollatedDealloc> = new IntMap<CollatedDealloc>();
    var total:Int = 0;
    var total_size:Int = 0;
    each_frame(function(f:FLMListener.Frame) {
      for (i in 0...f.mem_dealloc.length) {
        var d = f.mem_dealloc[i];
        var item:FLMListener.NewAlloc = session.alloc_guid_to_newalloc.get(d.guid);
        var type:Int = item.type;
        if (!deallocs.exists(type)) {
          deallocs.set(type, {total:0,size:0});
        }
        var cd = deallocs.get(type);
        total++;
        cd.total++;
        total_size += item.size;
        cd.size += item.size;
      }
    });

    cast(dealloc_pane.data_source, DeallocsTabularDataSource).update_dealloc_data(deallocs, session);
    dealloc_pane.redraw();


    //  if (total>0) {
    //    y = 0;
    //    for (type_int in deallocs.keys()) {
    //      var cd = deallocs.get(type_int);
    //      var type:String = session.stack_strings[type_int];
    // 
    //      // type name formatting
    //      if (type.substr(0,7)=='[object') type = type.substr(8, type.length-9);
    //      if (type.substr(0,6)=='[class') type = type.substr(7, type.length-8);
    //      type = (~/\$$/).replace(type, ' <static>');
    //      var clo = type.indexOf('::');
    //      if (clo>=0) {
    //        type = 'Closure ['+type.substr(clo+2)+' ('+type.substr(0,clo)+')]';
    //      }
    // 
    //      var lbl = Util.make_label(type, 12, 0x227788);
    //      var cont = new Sprite();
    //      cont.y = y;
    //      cont.x = 15;
    //      cont.addChild(lbl);
    //      alloc_pane.cont.addChild(cont);
    // 
    //      inline function draw_pct(cont, val:Int, total:Int, offset:Float) {
    //        var unit:Int = Math.floor(val*100/total);
    // 
    //        var num = Util.make_label((val==0)?"< 1" : Util.add_commas(val), 12, 0xeeeeee);
    //        num.x = offset - 70 - num.width;
    //        cont.addChild(num);
    // 
    //        var numpctunit = Util.make_label(unit+" %", 12, 0xeeeeee);
    //        numpctunit.x = offset - 25 - numpctunit.width;
    //        cont.addChild(numpctunit);
    //      }
    //      draw_pct(cont, cd.total, total, alloc_pane.innerWidth-120);
    //      draw_pct(cont, Math.round(cd.size/1024), Math.round(total_size/1024), alloc_pane.innerWidth-10);
    // 
    //      y += lbl.height;
    //    }
    //  }

    // - - - - - - - - - - - - - - -
    // - - Alloc pane - -
    // - - - - - - - - - - - - - - -
    var allocs:IntMap<AllocData> = new IntMap<AllocData>();
    var total_num = 0;
    var total_size = 0;
    each_frame(function(f) { // also updateObjects?
      var frame_allocs:IntMap<AllocData> = f.alloc_bottom_up;
      if (frame_allocs!=null) {
        for (type in frame_allocs.keys()) {
          if (!allocs.exists(type)) allocs.set(type, new AllocData());
          var ad:AllocData = allocs.get(type);

          function merge_children(tgt:AllocData, src:AllocData) {
            tgt.total_size += src.total_size;
            tgt.total_num += src.total_num;
            tgt.callstack_id = src.callstack_id;
            total_size += src.total_size;
            total_num += src.total_num;
            for (key in src.children.keys()) {
              if (!tgt.children.exists(key)) tgt.children.set(key, new AllocData());
              merge_children(tgt.children.get(key), src.children.get(key));
            }
          }
          merge_children(ad, frame_allocs.get(type));
        }
      }
    });

    cast(alloc_pane.data_source, AllocsTabularDataSource).update_alloc_data(allocs, session);
    alloc_pane.redraw();

      // //trace(allocs);
      // var y:Float = 0;
      // var ping = true;
      //  
      // var keys = allocs.keys();
      // var sorted:Array<Int> = new Array<Int>();
      // for (key in keys) sorted.push(key);
      // sorted.sort(function(i0:Int, i1:Int):Int {
      //   var ad0 = allocs.get(i0);
      //   var ad1 = allocs.get(i1);
      //   if (_alloc_sort_count) return ad0.total_num > ad1.total_num ? -1 : (ad0.total_num < ad1.total_num ? 1 : 0);
      //   return ad0.total_size > ad1.total_size ? -1 : (ad0.total_size < ad1.total_size ? 1 : 0);
      // });
      //  
      // for (type_int in sorted) {
      //   var ad = allocs.get(type_int);
      //   var type = session.stack_strings[type_int];
      //  
      //   // type name formatting
      //   if (type.substr(0,7)=='[object') type = type.substr(8, type.length-9);
      //   if (type.substr(0,6)=='[class') type = type.substr(7, type.length-8);
      //   type = (~/\$$/).replace(type, ' <static>');
      //   var clo = type.indexOf('::');
      //   if (clo>=0) {
      //     type = 'Closure ['+type.substr(clo+2)+' ('+type.substr(0,clo)+')]';
      //   }
      //  
      //   var lbl = Util.make_label(type, 12, 0x227788);
      //   var cont = new Sprite();
      //   cont.y = y;
      //   cont.x = 15;
      //   cont.addChild(lbl);
      //   alloc_pane.cont.addChild(cont);
      //  
      //   inline function draw_pct(cont, val:Int, total:Int, offset:Float) {
      //     var unit:Int = Math.floor(val*100/total);
      //  
      //     var num = Util.make_label((val==0)?"< 1" : Util.add_commas(val), 12, 0xeeeeee);
      //     num.x = offset - 70 - num.width;
      //     cont.addChild(num);
      //  
      //     var numpctunit = Util.make_label(unit+" %", 12, 0xeeeeee);
      //     numpctunit.x = offset - 25 - numpctunit.width;
      //     cont.addChild(numpctunit);
      //   }
      //   draw_pct(cont, ad.total_num, total_num, alloc_pane.innerWidth-120);
      //   draw_pct(cont, Math.round(ad.total_size/1024), Math.round(total_size/1024), alloc_pane.innerWidth-10);
      //  
      //   // TODO: background graphics on special shape
      //   //ping = !ping;
      //   //if (ping) {
      //   //  alloc_pane.cont.graphics.beginFill(0xffffff, 0.02);
      //   //  alloc_pane.cont.graphics.drawRect(0,y,sample_pane.innerWidth,lbl.height);
      //   //}
      //  
      //   y += lbl.height;
      //  
      //   // merged stacks (bottom-up objects)
      //   if (ad.children.keys().hasNext()) {
      //     Util.add_collapse_button(cont, lbl, false, alloc_pane.invalidate_scrollbars);
      //  
      //     inline function iterate_children(alloc_data:AllocData,
      //                                      sort_param:String, // TODO: Implement various sorting
      //                                      f:AllocData->Int->Void,
      //                                      depth:Int=0):Void
      //     {
      //       var children:Array<AllocData> = new Array<AllocData>();
      //       for (child in alloc_data.children) children.push(child);
      //       children.sort(function(a:AllocData, b:AllocData):Int {
      //         if (_alloc_sort_count) return a.total_num > b.total_num ? -1 : (a.total_num < b.total_num ? 1 : 0);
      //         return a.total_size > b.total_size ? -1 : (a.total_size < b.total_size ? 1 : 0);
      //       });
      //       for (child in children) {
      //         f(child, depth);
      //       }
      //     }
      //  
      //     function draw_alloc_data(d:AllocData, depth:Int=0):Void
      //     {
      //       var stack = Util.make_label(session.stack_strings[d.callstack_id], 12, 0x66aadd);
      //       var cont = new Sprite();
      //       cont.addChild(stack);
      //       cont.x = 15+15*(depth+1);
      //       cont.y = y;
      //       alloc_pane.cont.addChild(cont);
      //  
      //       if (d.children.keys().hasNext()) Util.add_collapse_button(cont, stack, false, alloc_pane.invalidate_scrollbars);
      //  
      //       draw_pct(cont, d.total_num, total_num, alloc_pane.innerWidth-120-cont.x+15);
      //       draw_pct(cont, Math.round(d.total_size/1024), Math.round(total_size/1024), alloc_pane.innerWidth-10-cont.x+15);
      //  
      //       y += stack.height;
      //  
      //       iterate_children(d, "total_num", draw_alloc_data, depth+1);
      //     }
      //  
      //     iterate_children(ad, "total_num", draw_alloc_data);
      //     //ping = !ping;
      //     //if (ping) {
      //     //  alloc_pane.cont.graphics.beginFill(0xffffff, 0.02);
      //     //  alloc_pane.cont.graphics.drawRect(0,y,sample_pane.innerWidth,stack.height);
      //     //}
      //   }
      // }

  }
}

class DetailUI {
  private var detail_pane:Pane;
  private var sample_pane:Pane;
  private var alloc_pane:TabularDataPane;
  private var sel_ctrl:SelectionController;
  private var get_detail_factor:Void->Float;

  private var pcont:Sprite;
  private var acont:Sprite;
  private var plbl:Sprite;
  private var albl:Sprite;

  public function new (detail_pane, sample_pane, alloc_pane, sel_ctrl):Void
  {
    this.detail_pane = detail_pane;
    this.sample_pane = sample_pane;
    this.alloc_pane = alloc_pane;
    this.sel_ctrl = sel_ctrl;

    var profiler = Util.make_label("Profiler", 12);
    profiler.filters = [Util.TEXT_SHADOW];
    profiler.mouseEnabled = false;
    var p = pcont = new Sprite();
    Util.begin_gradient(p.graphics, profiler.width*1.4, profiler.height);
    p.graphics.lineStyle(1, 0x555555);
    p.graphics.drawRect(0,0,profiler.width*1.4, profiler.height);
    profiler.x = profiler.width*0.2;
    p.addChild(profiler);
    //detail_pane.cont.addChild(p);

    var alloc = Util.make_label("Memory", 12);
    alloc.filters = [Util.TEXT_SHADOW];
    alloc.mouseEnabled = false;
    var a = acont = new Sprite();
    Util.begin_gradient(a.graphics, alloc.width*1.4, alloc.height);
    a.graphics.lineStyle(1, 0x555555);
    a.graphics.drawRect(0,0,alloc.width*1.4, alloc.height);
    alloc.x = alloc.width*0.2;
    a.addChild(alloc);
    a.x = p.x+p.width+5;
    //detail_pane.cont.addChild(a);

    plbl = new Sprite();
    var plbl_self = Util.make_label("Self Time (ms)", 12);
    var plbl_total = Util.make_label("Total Time (ms)", 12);
    plbl.addChild(plbl_self);
    plbl.addChild(plbl_total);
    plbl_total.x = 130;
    //detail_pane.cont.addChild(plbl);
    AEL.add(plbl_self, MouseEvent.CLICK, sel_ctrl.handle_sort_self);
    AEL.add(plbl_total, MouseEvent.CLICK, sel_ctrl.handle_sort_total);

    albl = new Sprite();
    var albl_size = Util.make_label("Size (KB)", 12);
    var albl_count = Util.make_label("Count", 12);
    albl.addChild(albl_size);
    albl.addChild(albl_count);
    albl_size.x = 130;
    //detail_pane.cont.addChild(albl);
    AEL.add(albl_size, MouseEvent.CLICK, sel_ctrl.handle_sort_size);
    AEL.add(albl_count, MouseEvent.CLICK, sel_ctrl.handle_sort_count);

    function handle_tab_click(e:Event):Void { select(e.target); }
    AEL.add(p, MouseEvent.CLICK, handle_tab_click);
    AEL.add(a, MouseEvent.CLICK, handle_tab_click);
    select(p);

    AEL.add(Util.stage, KeyboardEvent.KEY_DOWN, handle_key);
  }

  function handle_key(ev:Event)
  {
    var e = cast(ev, KeyboardEvent);
    if (e.keyCode==9) { // tab
      select((alloc_pane.visible) ? pcont : acont);
    }
  }

  // public var sel_index(get, set):Int;
  // public function get_sel_index():Int { return sample_pane.visible ? 0 : 1; }
  // public function set_sel_index(val:Int):Int { select(val==0 ? pcont : acont); return val; }

  private function select(tgt:Sprite):Void
  {
    var highlight_on = new openfl.geom.ColorTransform(1,1.02,1.04,1,0,0,0);
    var highlight_off = new openfl.geom.ColorTransform(0.5,0.5,0.5,1,10,10,10);

    pcont.transform.colorTransform = tgt==pcont ? highlight_on : highlight_off;
    acont.transform.colorTransform = tgt==acont ? highlight_on : highlight_off;
    sample_pane.visible = true; //tgt==pcont;
    alloc_pane.visible = true; //tgt==acont;
    plbl.visible = tgt==pcont;
    albl.visible = tgt==acont;

    // openfl bug /w set colortransform / cached textfields?
    pcont.getChildAt(0).alpha = 1;
    acont.getChildAt(0).alpha = 1;

    sel_ctrl.redraw();
  }

  public function resize():Void
  {
    plbl.x = detail_pane.innerWidth - plbl.width - 30;
    albl.x = detail_pane.innerWidth - albl.width - 30;
  }

}
