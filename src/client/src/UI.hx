package;

import flash.display.*;
import flash.events.*;

// make cont private
//  - add child
//  - clear/remove
//  - scroll rect get/set x/y
//  - get drawable / drawn contents
class Pane extends Sprite {

  public var PAD:Float = 6;
  public var outline:Float = 3;
  public var outline_alpha:Float = 1;

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
    _scroll_invalid = true;
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
    if (!_scroll_invalid) { _scroll_invalid = false; redraw_scrollbars(); }
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
    backdrop.graphics.beginFill(0x000000, 0.25);
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

    var label = Util.make_label(p.name, 12);
    label.filters = [Util.TEXT_SHADOW];
    label.mouseEnabled = false;

    Util.begin_gradient(tab.graphics, label.width*1.4, label.height);
    tab.graphics.lineStyle(1, 0x555555);
    tab.graphics.drawRect(0,0,label.width*1.4, label.height);
    label.x = label.width*0.2;
    tab.addChild(label);

    tab.x = 0;
    if (tab_cont.numChildren>0) {
      var last = tab_cont.getChildAt(tab_cont.numChildren-1);
      tab.x = last.x + last.width + 5;
    }
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
        p.width = _width;
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
  function get_labels():Array<String>
  {
    throw "AbsTabularDataSource.get_labels() is abstract";
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

class AbsTabularDataPane extends Pane
{
  private static var LABEL_HEIGHT:Float = 20;

  private var label_cont:Sprite;
  private var row_cont:Pane;
  private var _data_source:AbsTabularDataSource;

  public function new(data_source:AbsTabularDataSource):Void
  {
    label_cont = new Sprite();
    row_cont = new Pane(false, false, true); // scrolly

    super();

    cont.addChild(label_cont);
    cont.addChild(row_cont);

    _data_source = data_source;
    redraw();
  }

  override private function resize():Void
  {
    super.resize();
    row_cont.width = _width;
    row_cont.height = _height - LABEL_HEIGHT;
    row_cont.y = LABEL_HEIGHT;
  }

  function redraw()
  {
    // cleanup
    while (label_cont.numChildren>0) label_cont.removeChildAt(0); // TODO: pool
    while (row_cont.numChildren>0) row_cont.removeChildAt(0); // TODO: pool

    // draw labels
    draw_labels();
    draw_rows();
  }

  function draw_labels()
  {
    for (lbl in _data_source.labels) {
      var label = Util.make_label(lbl, 12);
      label_cont.addChild(label);
      // label.x = ?? // TODO: specify column widths? percentages? auto?
    }
  }

  function draw_rows()
  {
    // read from data source, draw rows, collapsable, setup linked list
    for (row_idx=0..._data_source.num_rows) {
      var row_sprite:Sprite = new Sprite(); // TODO: pool
      for (col_idx=0..._data_source.num_cols) {
        var value = Util.make_label(_data_source.get_string(row_idx, col_idx), 12);
        row_sprite.addChild(value);
        var indent = _data_source.get_indent(row_idx);
        // TODO: value.x = ?? // TODO: specify column widths? percentages? auto?
        // TODO: indent, alignment, etc
        // TODO: draw collapsing buttons
      }
    }

build _indent_linked_list

    var sort_order:Array<Int> = _data_source.get_sort_order();
    if (sort_order==null) {
      for (i=0..._data_source.num_rows) {
        
      }
    } else {
      throw "TODO: support sort"
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
  
  