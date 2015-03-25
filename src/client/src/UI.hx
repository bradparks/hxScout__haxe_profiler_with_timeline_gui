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

  private function handle_scroll_wheel(e:Event):Void
  {
    //trace("wheel event, delta="+cast(e).delta+", sby="+_scrollbary+", scrollrect.y="+cont.scrollRect.y);
    var r = cont.scrollRect;
    // TODO: bottom_aligned support?, +=h laster, -=h
    if (_scrollbary) {
      r.y += (cast(e).delta<0) ? 25 : -25;
      limit_scrolly(r);
    } else if (_scrollbarx) {
      r.x += (cast(e).delta<0) ? 25 : -25;
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
    if (_needs_resize) { _needs_resize = false; resize(); }
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
    tab.graphics.lineStyle(1, 0x555555);
    tab.graphics.drawRect(0,0,label.width*1.4, TAB_HEIGHT);
    label.x = label.width*0.2;
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

    var highlight_on = new openfl.geom.ColorTransform(1,1.02,1.04,1,0,0,0);
    var highlight_off = new openfl.geom.ColorTransform(0.5,0.5,0.5,1,10,10,10);

    for (i in 0...tab_cont.numChildren) {
      tab_cont.getChildAt(i).transform.colorTransform = i==idx ? highlight_on : highlight_off;
      panes[i].visible = i==idx;

      // openfl bug /w set colortransform on parent of textfields?
      cast(tab_cont.getChildAt(i)).getChildAt(0).alpha = 1;
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
    tab_cont.x = PAD;
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

class SamplesTabularDataSource extends AbsTabularDataSource
{
  public function new() {
    super();
  }

  private static var labels:Array<String> = ["Self Time (ms)", "Total Time (ms)"];
  override public function get_labels():Array<String> { return labels; }

  override public function get_num_rows():Int
  {
    return 50;
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
}

class TabularDataPane extends Pane
{
  private static var LABEL_HEIGHT:Float = 20;
  private static var ROW_HEIGHT:Float = 20;
  private static var INDENT_X:Float = 20;

  private var _label_cont:Sprite;
  private var _row_cont:Pane;
  private var _data_source:AbsTabularDataSource;

  public function new(data_source:AbsTabularDataSource):Void
  {
    _label_cont = new Sprite();
    _row_cont = new Pane(false, false, true); // scrolly
    _row_cont.outline = 0;
    _row_cont.outline_alpha = 0;
    _row_cont.darken_alpha = 0.5;

    super();

    cont.addChild(_label_cont);
    cont.addChild(_row_cont);

    _data_source = data_source;
    redraw();
  }

  override private function resize():Void
  {
    super.resize();
    _row_cont.width = _width - 2*PAD;
    _row_cont.height = _height - 3*PAD - LABEL_HEIGHT;
    _row_cont.y = LABEL_HEIGHT;

    reposition();
  }

  private var _row_hierarchy:IntMap<Array<Int>>;
  private var _sorted_rows:Array<Int>;
  private var _sorted_lookup:IntMap<Int>;
  private function sort_on_col(col_idx:Int, descending:Bool=true, reposition_now:Bool=true):Void
  {
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

    if (reposition_now) reposition();
  }

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

    // TODO: only position visible, uncollapsed rows...
    // position row text
    var n = _data_source.get_num_rows();
    var dy = 0.0;
    for (sorted_idx in 0...n) {
      var row_idx = _sorted_rows[sorted_idx];
      var row_sprite:TabularRowSprite = cast(_row_cont.cont.getChildAt(row_idx), TabularRowSprite);
      dy += row_sprite.visible ? 0 : ROW_HEIGHT;
      row_sprite.y = sorted_idx*ROW_HEIGHT-dy;
      row_sprite.x = 0;
      var indent = _data_source.get_indent(row_idx);
      row_sprite.getChildAt(0).x = INDENT_X + INDENT_X * indent;

      var num_cols = _data_source.get_num_cols();
      for (i in 0...num_cols) {
        var value = row_sprite.getChildAt(-1-i+row_sprite.numChildren);
        var w = col_width();
        value.x = _row_cont.innerWidth - i*w - value.width - 2*PAD;
      }
    }

    _row_cont.invalidate_scrollbars();
  }

  function redraw()
  {
    // cleanup
    while (_label_cont.numChildren>0) _label_cont.removeChildAt(0); // TODO: pool
    while (_row_cont.cont.numChildren>0) _row_cont.cont.removeChildAt(0); // TODO: pool

    // draw labels
    draw_labels();
    draw_rows();
    sort_on_col(1, true, false);

    resize();
  }

  function draw_labels()
  {
    function toggle_sort(e:flash.events.Event):Void {
      trace(e);
      trace(e.target);
      var col_idx = _label_cont.getChildIndex(e.target);
      sort_on_col(col_idx);
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

    _row_hierarchy = new IntMap<Array<Int>>();
    _row_hierarchy.set(-1, new Array<Int>());
    var last_row_idx_at_indent:IntMap<Int> = new IntMap<Int>();
    last_row_idx_at_indent.set(-1, -1);

    // read from data source, draw rows, collapsable, setup linked list
    for (row_idx in 0..._data_source.get_num_rows()) {
      var row_sprite:TabularRowSprite = new TabularRowSprite(); // TODO: pool
      //row_sprite.y = ROW_HEIGHT*row_idx;
      _row_cont.cont.addChild(row_sprite);

      var text = Util.make_label(_data_source.get_row_name(row_idx)+" "+row_idx, 12);
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
        row_sprite.collapse_btn = add_collapse_button(row_sprite, start_collapsed, _row_cont.invalidate_scrollbars);
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
                                       is_hidden:Bool,
                                       do_refresh_scrollbars:Void->Void):Sprite
  {
    var btn:Sprite = new Sprite();
    btn.graphics.beginFill(0xeeeeee, 0.01);
    btn.graphics.drawCircle(0, 0, ROW_HEIGHT/3);
    btn.x = row_sprite.label.x - ROW_HEIGHT/3;
    btn.y = ROW_HEIGHT/2;
    btn.graphics.lineStyle(1,0xeeeeee,0.7);
    btn.graphics.beginFill(0xeeeeee, 0.3);
    btn.graphics.moveTo(-ROW_HEIGHT/5, -ROW_HEIGHT/5);
    btn.graphics.lineTo( ROW_HEIGHT/5, -ROW_HEIGHT/5);
    btn.graphics.lineTo(          0,  ROW_HEIGHT/6);
    btn.rotation = is_hidden ? -90 : 0;
    row_sprite.addChild(btn);
    btn.name = "collapse_btn";

    function do_hide():Void
    {
      var sorted_idx = _sorted_lookup.get(row_sprite.row_idx);
      var hiding = true;
      var dy = 0.0;
      for (i in (sorted_idx+1)..._sorted_rows.length) {
        var later:TabularRowSprite = cast(_row_cont.cont.getChildAt(_sorted_rows[i]), TabularRowSprite);
        if (later.label.x <= row_sprite.label.x) hiding = false;
        if (hiding && later.visible) {
          later.visible = false;
          dy += ROW_HEIGHT;
        }
        later.y -= dy;
      }
    }

    function do_show(recursive:Bool=true):Void
    {
      var sorted_idx = _sorted_lookup.get(row_sprite.row_idx);
      var showing = true;
      var dy = 0.0;
      var at_x = recursive ? -1 : cast(_row_cont.cont.getChildAt(_sorted_rows[sorted_idx+1]), TabularRowSprite).label.x;
      for (i in (sorted_idx+1)..._sorted_rows.length) {
        var later:TabularRowSprite = cast(_row_cont.cont.getChildAt(_sorted_rows[i]));
        if (later.label.x <= row_sprite.label.x) showing = false;
        if (showing && !later.visible && (recursive || Math.abs(at_x-later.label.x)<0.01)) {
          later.visible = true;
          dy += ROW_HEIGHT;
          // Update newly visible button
          var later_btn = later.collapse_btn;
          if (later_btn!=null) {
            later_btn.rotation = recursive ? 0 : -90;
          }
        }
        later.y += dy;
      }
    }

    function toggle_collapse(e:Event=null):Void
    {
      var sorted_idx = _sorted_lookup.get(row_sprite.row_idx);
      var later:TabularRowSprite = (sorted_idx==_sorted_rows.length-1) ? null : cast(_row_cont.cont.getChildAt(_sorted_rows[sorted_idx+1]), TabularRowSprite);

      is_hidden = later==null || later.visible;
      Actuate.tween(btn, 0.2, { rotation: is_hidden ? -90 : 0 });
      if (is_hidden) do_hide();
      else do_show(cast(e).shiftKey);

      // Invalidate scrollbars
      do_refresh_scrollbars();
    }

    AEL.add(btn, MouseEvent.CLICK, toggle_collapse);

    return btn;
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
  
  