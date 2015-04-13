package;

import flash.display.*;
import flash.events.*;
import flash.text.*;
import motion.Actuate;
import haxe.ds.*;

// make cont private
//  - add child
//  - clear/remove
//  - scroll rect get/set x/y
//  - get drawable / drawn contents
class Pane extends Sprite {

  public var PAD:Float = 6;
  public var outline:Float = 3;
  public var outline_alpha:Float = 1;
  public var darken_alpha:Float = 0.25;

  public var cont(get, null):Sprite;
  var backdrop:Shape;
  public var scrollbars:Shape;

  var _width:Float;
  var _height:Float;
  var _bottom_aligned:Bool;
  var _scrollbarx:Bool;
  var _scrollbary:Bool;
  var _scroll_invalid:Bool;
  var _needs_resize:Bool = true;

  public function new (bottom_aligned:Bool=false, scrollbarx:Bool=false, scrollbary:Bool=false, w:Float=0, h:Float=0)
  {
    super();
    _bottom_aligned = bottom_aligned;
    _width = w;
    _height = h;
    _scrollbarx = scrollbarx;
    _scrollbary = scrollbary;

    if (bottom_aligned && scrollbary) throw "This combination of options is not yet supported";

    backdrop = new Shape();
    addChild(backdrop);

    cont = new Sprite();
    addChild(cont);
    cont.scrollRect = new flash.geom.Rectangle(0,_bottom_aligned?-h:h,w,h);
    cont.x = cont.y = PAD;

    scrollbars = new Shape();
    addChild(scrollbars);

    AEL.add(this, MouseEvent.MOUSE_WHEEL, handle_scroll_wheel);
    Util.stage.addEventListener(Event.ENTER_FRAME, handle_enter_frame);

    _needs_resize = true;
  }

  override public function set_width(w:Float):Float { _width = w; _needs_resize = true; return w; }
  override public function get_width():Float { return _width; }
  override public function set_height(h:Float):Float { _height = h; _needs_resize = true; return h; }
  override public function get_height():Float { return _height; }

  public var innerWidth(get, null):Float;
  public var innerHeight(get, null):Float;
  public function get_innerWidth():Float { return _width-2*PAD; }
  public function get_innerHeight():Float { return _height-2*PAD; }

  public function get_cont():Sprite {
    //_scroll_invalid = true; // This shouldn't be needed
    return cont;
  }

  public function invalidate_scrollbars():Void {
    _scroll_invalid = true;
  }

  private var _last_wheel_event:Int = 0;
  private var _wheel_speed:Int = 0;
  private function handle_scroll_wheel(e:Event):Void
  {
    var dt:Int = flash.Lib.getTimer() - _last_wheel_event;
    var new_speed = Math.max(25, Math.min(Math.pow(500/dt, 1.6), 800));
    if (cast(e, MouseEvent).shiftKey) new_speed *= 2;
    _wheel_speed = dt > 300 ? 25 : Std.int(0.85*Math.abs(_wheel_speed) + 0.15*new_speed);
    //trace("wheel event, delta="+cast(e).delta+", dt="+dt+", speed="+_wheel_speed);
    if (cast(e, MouseEvent).delta>0) _wheel_speed = -_wheel_speed;
    wheel_speed_updated();
  }

  private function wheel_speed_updated()
  {
    var r = cont.scrollRect;
    // TODO: bottom_aligned support?, +=h laster, -=h
    if (_scrollbary) {
      r.y += _wheel_speed;
      limit_scrolly(r);
    } else if (_scrollbarx) {
      r.x += _wheel_speed;
      limit_scrollx(r);
    }
    cont.scrollRect = r;
    _scroll_invalid = true;
    _last_wheel_event = flash.Lib.getTimer();
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
    if (_needs_resize) { _needs_resize = false; resize(); }
    if (Math.abs(_wheel_speed) > 5 && !_scroll_invalid) {
      _wheel_speed = Std.int(_wheel_speed*0.6);
      wheel_speed_updated();
    }
    if (_scroll_invalid) { _scroll_invalid = false; redraw_scrollbars(); }
  }

  private function redraw_scrollbars():Void
  {
    var rect = cont.scrollRect;
    var bounds = cont.getBounds(cont);

    if (_scrollbary || _scrollbarx) scrollbars.graphics.clear();
    if (_scrollbary && rect.height<bounds.height) {
      scrollbars.graphics.lineStyle(1, 0x0,0.2);
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
      scrollbars.graphics.lineStyle(1, 0xffffff,0.2);
      scrollbars.graphics.beginFill(0xcccccc,0.4);
      scrollbars.graphics.drawRoundRect(rect.width+2,
                                        PAD+scroll_y,
                                        PAD-2,
                                        scrollbar_h,
                                        PAD);
    }
    if (_scrollbarx && rect.width<bounds.width) {
      scrollbars.graphics.lineStyle(1, 0x0,0.2);
      scrollbars.graphics.beginFill(0xffffff,0.2);
      scrollbars.graphics.drawRoundRect(PAD,
                                        rect.height+2,
                                        rect.width,
                                        PAD-2,
                                        PAD);
      var pct = rect.width/bounds.width;
      var scrollbar_w = (rect.width/10)*(1-pct) + (rect.width)*pct;
      var scroll_pct = rect.x/(bounds.width-rect.width);
      var scroll_x = (rect.width-scrollbar_w)*scroll_pct;
      scrollbars.graphics.lineStyle(1, 0xffffff,0.2);
      scrollbars.graphics.beginFill(0xcccccc,0.4);
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

  private function resize():Void
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
    backdrop.graphics.lineStyle(outline, 0x111111, outline_alpha);

    Util.begin_gradient(backdrop.graphics, _width, _height);
    backdrop.graphics.drawRoundRect(0,0,_width,_height, 7);

    // cont knockout
    var p:Float = outline;
    backdrop.graphics.lineStyle(0,0, 0);
    backdrop.graphics.beginFill(0x000000, darken_alpha);
    backdrop.graphics.drawRoundRect(p,p,_width-p*2,_height-p*2,5);

  }
}

// UI only

// populates tab container container, adds mouse handlers
// pubsub tab change listeners (with same tabsetid)
// tabs hide/remove pane but must stay populated
class TabbedPane extends Pane
{
  private static var TAB_HEIGHT:Float = 20;

  // move cont down by tab height
  // return innerHeight smaller by tab height
  private var tab_cont:Sprite;
  private var panes:Array<Pane>;

  public function new()
  {
    tab_cont = new Sprite();
    panes = [];

    super();

    addChild(tab_cont);
  }

  public function add_pane(p:Pane):Void
  {
    cont.addChild(p);

    // draw tab
    var tab:Sprite = new Sprite();

    var label = Util.make_label(p.name, Std.int(12/20*TAB_HEIGHT));
    label.filters = [Util.TEXT_SHADOW];
    label.mouseEnabled = false;

    Util.begin_gradient(tab.graphics, label.width*1.4, label.height);
    tab.graphics.lineStyle(1, 0x222222);
    tab.graphics.drawRect(0,0,label.width*1.4, TAB_HEIGHT);
    label.x = label.width*0.2;
    label.y = 1;
    tab.addChild(label);

    tab.x = 0;
    if (tab_cont.numChildren>0) {
      var last = tab_cont.getChildAt(tab_cont.numChildren-1);
      tab.x = last.x + last.width + 5;
    }
    tab.y = PAD;
    var idx:Int = tab_cont.numChildren;
    tab_cont.addChild(tab);
    panes.push(p);

    function handle_tab_click(e:Event):Void { select_tab(idx); }
    AEL.add(tab, MouseEvent.CLICK, handle_tab_click);
  }

  private var _selected_tab:Int = -1;
  public var selected_tab(get, set):Int;
  public function get_selected_tab():Int { return _selected_tab; }
  public function set_selected_tab(val:Int):Int { select_tab(val); return _selected_tab; }

  public function select_tab(idx:Int):Void
  {
    if (_selected_tab==idx) return;
    _selected_tab = idx;

    var highlight_on = new openfl.geom.ColorTransform(0.9,0.9,0.9,1,0,0,0);
    var highlight_off = new openfl.geom.ColorTransform(0.5,0.5,0.5,1,10,10,10);

    for (i in 0...tab_cont.numChildren) {
      tab_cont.getChildAt(i).transform.colorTransform = i==idx ? highlight_on : highlight_off;
      panes[i].visible = i==idx;

      // openfl bug /w set colortransform on parent of textfields?
      cast(tab_cont.getChildAt(i), DisplayObjectContainer).getChildAt(0).alpha = 1;
    }

    //plbl.visible = tgt==pcont;
    //albl.visible = tgt==acont;
  }

  override private function resize():Void
  {
    super.resize();
    for (i in 0...cont.numChildren) {
      var p:DisplayObject = cont.getChildAt(i);
      if (Std.is(p, Pane)) {
        p.width = _width - 2*PAD;
        p.height = _height - TAB_HEIGHT;
        p.x = 0;
        p.y = TAB_HEIGHT;
      }
    }
    tab_cont.y = 2;
    tab_cont.x = PAD;
    tab_cont.scrollRect = new flash.geom.Rectangle(0,0,_width,TAB_HEIGHT+PAD-1);
  }

}

class AbsTabularDataSource
{
  public function new() { }

  public function get_labels():Array<String>
  {
    throw "AbsTabularDataSources is abstract";
  }

  public function get_num_rows():Int
  {
    throw "AbsTabularDataSources is abstract";
  }

  public function get_num_cols():Int
  {
    throw "AbsTabularDataSources is abstract";
  }

  public function get_indent(row_idx:Int):Int
  {
    throw "AbsTabularDataSources is abstract";
  }

  public function has_indent_children(row_idx:Int):Bool
  {
    return get_num_rows()>(row_idx+1) && get_indent(row_idx) < get_indent(row_idx+1);
  }

  public function get_row_name(row_idx:Int):String { throw "AbsTabularDataSources is abstract"; }
  public function get_row_value(row_idx:Int, col_idx:Int):Float { throw "AbsTabularDataSources is abstract"; }
}

class ExampleTabularDataSource extends AbsTabularDataSource
{
  public function new() {
    super();
  }

  private static var labels:Array<String> = ["Self Time (ms)", "Total Time (ms)"];
  override public function get_labels():Array<String> { return labels; }

  override public function get_num_rows():Int
  {
    return 15000;
  }

  override public function get_num_cols():Int { return 2; }

  override public function get_indent(row_idx:Int):Int
  {
    return row_idx % 5;
  }

  override public function get_row_value(row_idx:Int, col_idx:Int):Float
  {
    return (row_idx%21) + col_idx*31%(row_idx+2);
  }

  override public function get_row_name(row_idx:Int):String
  {
    return "Something or other";
  }
}

// collapsable infrastructure (optional)
// redraw() --
//   linked list of rows? nextRow, nextVisibleRow, nextRowAtThisIndent?
//                        maxHeight (rows), currentHeight (viusible rows)
//                        variable row height?
//                        Row index maps to abstract array/vector of row/col data (+ indent, height)
//   pool of labels, containers, row LLNodes
//   row data (strings, mapped ints?) for each column
//   row formatter (string formatting, int-mapping to strings)
// get label strings (abstract)
// resort trigger

class TabularRowSprite extends Sprite
{
  public var label:TextField;
  public var collapse_btn:Sprite;
  public var indent:Int;
  public var row_idx:Int;
  public var toggle_collapse:flash.events.Event->Void;
}

class ToggleButton extends Sprite
{
  public var toggle(get,null):Bool = false;
  public function new() { super(); redraw(); }
  public function get_toggle():Bool { return toggle; }
  function redraw()
  {
    this.graphics.clear();
    var dx:Int = toggle ? 0 : 2;
    this.graphics.lineStyle(1, 0xaaaaaa, 0.6);
    this.graphics.beginFill(0xaaaaaa, 0.2);
    this.graphics.drawRoundRect(-8,-8,16,16,4);
    this.graphics.moveTo(-3-dx,-4);
    this.graphics.lineTo(3-dx, -4);
    this.graphics.moveTo(-3,0);
    this.graphics.lineTo(3, 0);
    this.graphics.moveTo(-3+dx,4);
    this.graphics.lineTo(3+dx, 4);
  }
  public function do_toggle():Void
  {
    toggle = !toggle;
    redraw();
  }
}

class TabularDataPane extends Pane
{
  private static var LABEL_HEIGHT:Float = 20;
  private static var INDENT_X:Float = 20;

  private var _label_cont:Sprite;
  private var _toggle_all_btn:ToggleButton;
  private var _row_cont:Pane;
  private var _data_source:AbsTabularDataSource;
  private var _style:Dynamic;

  private var _lines:Sprite;

  private static var DEFAULT_STYLE = {
    font:"DroidSans.ttf",
    color:0x66aadd,
    row_height:20,
    preindent:20
  };

  public function new(data_source:AbsTabularDataSource,
                      style:Dynamic=null):Void
  {
    _style = style==null ? DEFAULT_STYLE : style;

    _label_cont = new Sprite();
    _row_cont = new Pane(false, false, true); // scrolly
    _row_cont.outline = 0;
    _row_cont.outline_alpha = 0;
    _row_cont.darken_alpha = 0.5;

    _row_cont.mouseChildren = false;
    _row_cont.addEventListener(MouseEvent.CLICK, handle_row_cont_click);

    super();

    _toggle_all_btn = new ToggleButton();
    _toggle_all_btn.x = _toggle_all_btn.y = 8;
    AEL.add(_toggle_all_btn, MouseEvent.CLICK, toggle_all);

    cont.addChild(_label_cont);
    cont.addChild(_row_cont);
    cont.addChild(_toggle_all_btn);

    _lines = new Sprite();
    addChild(_lines);
    _lines.mouseEnabled = false;

    _data_source = data_source;
    redraw();
  }

  public var data_source(get,null):AbsTabularDataSource;
  public function get_data_source():AbsTabularDataSource
  {
    return _data_source;
  }

  override private function handle_enter_frame(e:Event):Void
  {
    var did_scroll = _scroll_invalid || Math.abs(_wheel_speed)>5;
    super.handle_enter_frame(e);
    if (did_scroll) {
      revise_in_view();
      var yy = (_row_cont.cont.scrollRect.y % (2.0*_style.row_height));
      var r = _lines.scrollRect;
      r.y = yy;
      _lines.scrollRect = r;
    }
  }

  override private function resize():Void
  {
    _row_cont.width = _width - 2*PAD;
    _row_cont.height = _height - 3*PAD - LABEL_HEIGHT;
    _row_cont.y = LABEL_HEIGHT;
    _row_cont.resize();

    super.resize();

    reposition();

    _lines.x = _row_cont.x;
    _lines.y = _row_cont.y + PAD*1.5;
    _lines.graphics.clear();
    _lines.graphics.beginFill(0xffffff);
    var y = 0.0;
    while (y < _row_cont.height+_style.row_height*2) {
      _lines.graphics.drawRect(PAD*3, y+1, _width-PAD*6,_style.row_height);
      y = y + _style.row_height*2.0;
    }
    _lines.alpha = 0.03;
    _lines.scrollRect = new flash.geom.Rectangle(0,0,_width,_row_cont.height+2*PAD);
  }

  private var _cur_col_sort:Int = -1;
  private var _cur_col_desc:Bool = true;

  private var _row_hierarchy:IntMap<Array<Int>>;
  private var _sorted_rows:Array<Int>;
  private var _sorted_lookup:IntMap<Int>;
  private var _row_sprites:Array<TabularRowSprite>;
  private function sort_on_col(col_idx:Int, descending:Bool=true, reposition_now:Bool=true):Void
  {
    _cur_col_sort = col_idx;
    _cur_col_desc = descending;

    _sorted_rows = [];
    _sorted_lookup = new IntMap<Int>();
    var desc:Int = descending ? 1 : -1;

    function recursive_sort(indexes:Array<Int>):Void
    {
      //trace("Sorting: "+indexes);
      var sorted:Array<Int> = new Array<Int>();
      for (row_idx in indexes) sorted.push(row_idx); //trace(" - "+row_idx+" = "+_data_source.get_row_value(row_idx, col_idx)); }
      sorted.sort(function(i0:Int, i1:Int):Int {
        var val0 = _data_source.get_row_value(i0, col_idx);
        var val1 = _data_source.get_row_value(i1, col_idx);
        return val0 > val1 ? -desc :
              (val0 < val1 ?  desc : 0);
      });
      //trace("Sorted:  "+sorted);
      for (row_idx in sorted) {
        _sorted_lookup.set(row_idx, _sorted_rows.length);
        _sorted_rows.push(row_idx);
        if (_row_hierarchy.exists(row_idx)) recursive_sort(_row_hierarchy.get(row_idx));
      }
    }

    // Start with the roots
    recursive_sort(_row_hierarchy.get(-1));

    if (reposition_now) {
      reposition();
    }
  }

  // Sets y based on visible, then calls revise_inview (to add/remove)
  private function reposition():Void
  {
    inline function col_width():Float {
      return Math.max(120.0, _width*0.075);
    }

    // position labels
    var n = _label_cont.numChildren;
    for (i in 0...n) {
      var label = _label_cont.getChildAt(n-i-1);
      var w = col_width();
      label.x = _row_cont.innerWidth - i*w - label.width - 2*PAD;
    }

    // position row text
    var n = _data_source.get_num_rows();
    var dy = 0.0;
    var last_btn:Sprite = null;
    for (sorted_idx in 0...n) {
      var row_idx = _sorted_rows[sorted_idx];
      var row_sprite:TabularRowSprite = _row_sprites[row_idx];
      dy += row_sprite.visible ? 0 : _style.row_height;
      row_sprite.y = sorted_idx*_style.row_height-dy;
      row_sprite.x = 0;

      //var r:flash.geom.Rectangle = _row_cont.cont.scrollRect;
      //if (sorted_idx==0 ||
      //    sorted_idx==n-1 ||
      //    (row_sprite.y > r.y - _style.row_height &&
      //     row_sprite.y < r.y + r.height)) {
      //  _row_cont.cont.addChild(row_sprite);
      //} else if (row_sprite.parent!=null) {
      //  _row_cont.cont.removeChild(row_sprite);
      //}

      var indent = _data_source.get_indent(row_idx);
      row_sprite.getChildAt(0).x = _style.preindent + INDENT_X * indent;

      var num_cols = _data_source.get_num_cols();
      for (i in 0...num_cols) {
        var value = row_sprite.getChildAt(-1-i+row_sprite.numChildren);
        var w = col_width();
        value.x = _row_cont.innerWidth - i*w - value.width - 2*PAD;
      }

      if (last_btn!=null) last_btn.rotation = row_sprite.visible ? 0 : -90;
      last_btn = row_sprite.collapse_btn;
    }

    _row_cont.invalidate_scrollbars();

    _first_row = 0;
    _last_row = 0;
    revise_in_view();
  }

  private var _first_row:Int;
  private var _last_row:Int;
  private var _in_view:Array<TabularRowSprite>;
  function revise_in_view()
  {
    if (_sorted_rows.length==0) return;

    var row_sprite:TabularRowSprite;
    var r:flash.geom.Rectangle = _row_cont.cont.scrollRect;
    var row_idx;

    row_idx = _sorted_rows[_first_row];
    row_sprite = _row_sprites[row_idx];

    while (row_sprite.y < r.y && _first_row < _sorted_rows.length) {
      _first_row = _first_row + 1;
      row_idx = _sorted_rows[_first_row];
      row_sprite = _row_sprites[row_idx];
    }
    while (row_sprite.y >= r.y-_style.row_height && _first_row>0) {
      _first_row = _first_row - 1;
      row_idx = _sorted_rows[_first_row];
      row_sprite = _row_sprites[row_idx];
    }

    _last_row = _first_row;
    row_idx = _sorted_rows[_last_row];
    row_sprite = _row_sprites[row_idx];
    while (row_sprite.y < r.y + r.height && _last_row < _sorted_rows.length) {
      _last_row = _last_row + 1;
      row_idx = _sorted_rows[_last_row];
      row_sprite = _row_sprites[row_idx];
    }

    if (_in_view==null) {
      _in_view = [];
    } else {
      for (rs in _in_view) {
        if (rs.parent!=null) {
          rs.parent.removeChild(rs);
        }
      }
      _in_view = [];
    }

    inline function add_sorted_idx(sorted_idx):Void {
      var row_idx = _sorted_rows[sorted_idx];
      var row_sprite:TabularRowSprite = _row_sprites[row_idx];
      _row_cont.cont.addChild(row_sprite);
      _in_view.push(row_sprite);
    }

    for (sorted_idx in _first_row...(_last_row+1)) add_sorted_idx(sorted_idx);
    add_sorted_idx(0);
    add_sorted_idx(_sorted_rows.length-1);
  }

  public function redraw()
  {
    // cleanup
    while (_label_cont.numChildren>0) _label_cont.removeChildAt(0); // TODO: pool
    while (_row_cont.cont.numChildren>0) _row_cont.cont.removeChildAt(0); // TODO: pool
    _row_sprites = [];

    //trace("Redrawing...");

    // draw labels
    draw_labels();
    draw_rows();
    sort_on_col(1, true, false);

    resize();
  }

  function draw_labels()
  {
    function toggle_sort(e:flash.events.Event):Void {
      var col_idx = _label_cont.getChildIndex(e.target);
      sort_on_col(col_idx, col_idx==_cur_col_sort ? !_cur_col_desc : true);
    }

    var lbls:Array<String> = _data_source.get_labels();
    for (i in 0...lbls.length) {
      var label = Util.make_label(lbls[i], 12);
      _label_cont.addChild(label);
      AEL.add(label, MouseEvent.CLICK, toggle_sort);
    }
  }

  function draw_rows()
  {
    var start_collapsed = true;

    _first_row = 0;
    _last_row = 0;

    _row_hierarchy = new IntMap<Array<Int>>();
    _row_hierarchy.set(-1, new Array<Int>());
    var last_row_idx_at_indent:IntMap<Int> = new IntMap<Int>();
    last_row_idx_at_indent.set(-1, -1);

    //trace("Drawing rows: "+_data_source.get_num_rows());
    // read from data source, draw rows, collapsable, setup linked list
    for (row_idx in 0..._data_source.get_num_rows()) {
      var row_sprite:TabularRowSprite = new TabularRowSprite(); // TODO: pool
      //row_sprite.y = _style.row_height*row_idx;
      //_row_cont.cont.addChild(row_sprite);
      _row_sprites.push(row_sprite);

      var text = Util.make_label(_data_source.get_row_name(row_idx), 12, _style.color, -1, _style.font);
      row_sprite.label = text;
      row_sprite.addChild(text);
      row_sprite.row_idx = row_idx;

      var indent = _data_source.get_indent(row_idx);

      // build _row_hierarchy
      _row_hierarchy.set(row_idx, new Array<Int>());
      last_row_idx_at_indent.set(indent, row_idx);
      var parent_row_idx = last_row_idx_at_indent.get(indent-1);
      _row_hierarchy.get(parent_row_idx).push(row_idx);

      row_sprite.indent = indent;
      text.x = INDENT_X + INDENT_X * indent;

      if (_data_source.has_indent_children(row_idx)) {
        add_collapse_button(row_sprite, _row_cont.invalidate_scrollbars);
      }

      row_sprite.visible = start_collapsed && indent==0;

      for (col_idx in 0..._data_source.get_num_cols()) {
        var value_str:String = Util.add_commas(Std.int(_data_source.get_row_value(row_idx, col_idx)));
        var value = Util.make_label(value_str, 12);
        row_sprite.addChild(value);
      }
    }
  }

  private function add_collapse_button(row_sprite:TabularRowSprite,
                                       do_refresh_scrollbars:Void->Void):Void
  {
    var btn:Sprite = new Sprite();
    btn.graphics.beginFill(0xeeeeee, 0.01);
    btn.graphics.drawCircle(0, 0, _style.row_height/3);
    btn.x = row_sprite.label.x - _style.row_height/3;
    btn.y = _style.row_height/2;
    btn.graphics.lineStyle(1,0xeeeeee,0.7);
    btn.graphics.beginFill(0xeeeeee, 0.3);
    btn.graphics.moveTo(-_style.row_height/5, -_style.row_height/5);
    btn.graphics.lineTo( _style.row_height/5, -_style.row_height/5);
    btn.graphics.lineTo(                   0,  _style.row_height/6);
    row_sprite.addChild(btn);
    btn.name = "collapse_btn";

    // updates visible
    function do_hide():Void
    {
      var sorted_idx = _sorted_lookup.get(row_sprite.row_idx);
      var hiding = true;
      for (i in (sorted_idx+1)..._sorted_rows.length) {
        var later:TabularRowSprite = _row_sprites[_sorted_rows[i]];
        if (later.label.x <= row_sprite.label.x) hiding = false;
        if (hiding && later.visible) {
          later.visible = false;
        }
      }

      //trace("Do_hide, calling repo!");
      reposition();
    }

    // updates visible
    function do_show(recursive:Bool=true):Void
    {
      var sorted_idx = _sorted_lookup.get(row_sprite.row_idx);
      var showing = true;
      var at_indent = recursive ? -1 : _row_sprites[_sorted_rows[sorted_idx+1]].indent;
      for (i in (sorted_idx+1)..._sorted_rows.length) {
        var later:TabularRowSprite = _row_sprites[_sorted_rows[i]];
        if (later.indent < at_indent) showing = false;
        if (showing && (recursive || later.indent==at_indent)) {
          later.visible = true;
        }
      }

      //trace("Do_show, calling repo!");
      reposition();
    }

    function toggle_collapse(e:Event=null):Void
    {
      var sorted_idx = _sorted_lookup.get(row_sprite.row_idx);
      var rs:TabularRowSprite = _row_sprites[_sorted_rows[sorted_idx]];
      if (!rs.visible) return;
      var later:TabularRowSprite = (sorted_idx==_sorted_rows.length-1) ? null : _row_sprites[_sorted_rows[sorted_idx+1]];

      var needs_hidden = later==null || (later.visible && later.parent!=null);
      Actuate.tween(btn, 0.2, { rotation: needs_hidden ? -90 : 0 });
      if (needs_hidden) do_hide();
      else do_show(cast(e, MouseEvent).shiftKey);

      // Invalidate scrollbars
      do_refresh_scrollbars();
    }

    row_sprite.collapse_btn = btn;
    row_sprite.toggle_collapse = toggle_collapse;
  }

  function toggle_all(e):Void
  {
    _toggle_all_btn.do_toggle();
    var expand:Bool = _toggle_all_btn.toggle;

    var n = _data_source.get_num_rows();
    for (idx in 0...n) {
      var row_sprite:TabularRowSprite = _row_sprites[idx];
      row_sprite.visible = expand || row_sprite.indent==0;
    }

    reposition();
  }

  function handle_row_cont_click(e:flash.events.MouseEvent):Void
  {
    var objs = _row_cont.cont.getObjectsUnderPoint(new flash.geom.Point(e.stageX, e.stageY));
    if (objs.length>0) {
      var obj:DisplayObject = objs[0];
      while (Type.getClass(obj)!=TabularRowSprite && obj!=null) {
        obj = obj.parent;
      }
      if (obj!=null) {
        var rs:TabularRowSprite = cast(obj, TabularRowSprite);
        if (objs.indexOf(rs.collapse_btn)>=0) {
          rs.toggle_collapse(e);
        }
      }
    }
  }

}

// Knows about frames / session
// update frame numbers (abstract), update session reference (reset)
//class AbsFrameDataTable extends AbsSortableTabularBaseClass {
//}

// Top-level, implements all abstracts
// 
// Tries to maintain collapsing across frame changes
//class AllocationTable extends FrameDataTable {
//}

  // Base implementations:
  // - Given a container pane and tab container sprite
  // - tab sprite
  // - column label sprites (and click handlers)
 
  // abstract:
  //  column label strings, trigger resort
  //  data source
  
  // 1 - construct
  // 1.5 - update session reference / reset
  // 1.75 - update frame numbers (start / end)
  //        allows performance / caching
  // 2 - merge in each frame
  // 3 - sort / setup list
  // 4 - draw rows /w collapse buttons (pre-collacpsed)
  
  