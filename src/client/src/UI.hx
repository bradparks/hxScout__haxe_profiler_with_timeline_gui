package;

import flash.display.*;
import flash.events.*;
import flash.text.*;
import motion.Actuate;

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

  public function get_value(row_idx, col_idx):String
  {
    throw "AbsTabularDataSources is abstract";
  }
}

class SamplesTabularDataSource extends AbsTabularDataSource
{
  public function new() {
    super();
  }

  private static var labels:Array<String> = ["Stack", "Self Time (ms)", "Total Time (ms)"];
  override public function get_labels():Array<String> { return labels; }

  override public function get_num_rows():Int
  {
    return 200;
  }

  override public function get_num_cols():Int { return 3; }

  override public function get_indent(row_idx:Int):Int
  {
    return 0;
  }

  override public function get_value(row_idx, col_idx):String
  {
    return "Test";
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

class TabularDataPane extends Pane
{
  private static var LABEL_HEIGHT:Float = 20;

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
    _row_cont.height = _height - LABEL_HEIGHT;
    _row_cont.y = LABEL_HEIGHT;
  }

  function redraw()
  {
    // cleanup
    while (_label_cont.numChildren>0) _label_cont.removeChildAt(0); // TODO: pool
    while (_row_cont.cont.numChildren>0) _row_cont.cont.removeChildAt(0); // TODO: pool

    // draw labels
    draw_labels();
    draw_rows();
  }

  function draw_labels()
  {
    var lbl:String;
    var i:Int = 0;
    for (lbl in _data_source.get_labels()) {
      var label = Util.make_label(lbl, 12);
      _label_cont.addChild(label);
      label.x = i*50;
      // label.x = ?? // TODO: specify column widths? percentages? auto?
      i++;
    }
  }

  function draw_rows()
  {
    // read from data source, draw rows, collapsable, setup linked list
    for (row_idx in 0..._data_source.get_num_rows()) {
      var row_sprite:Sprite = new Sprite(); // TODO: pool
      var indent = _data_source.get_indent(row_idx);
      row_sprite.y = 20*row_idx;
      _row_cont.cont.addChild(row_sprite);
      for (col_idx in 0..._data_source.get_num_cols()) {
        var value = Util.make_label(_data_source.get_value(row_idx, col_idx), 12);
        row_sprite.addChild(value);
        value.x = 50*col_idx;
        // TODO: value.x = ?? // TODO: specify column widths? percentages? auto?
        // TODO: indent, alignment, etc
        // TODO: draw collapsing buttons
      }
      //add_collapse_button(row_sprite); // TODO: move to private static of this class
    }
  }

  private static function add_collapse_button(row_sprite:Sprite,
                                              lbl:TextField,
                                              is_hidden:Bool,
                                              do_refresh_scrollbars:Void->Void):Void
  {
    var r:flash.geom.Rectangle = lbl.getBounds(row_sprite); // TODO: wasteful, const height
    var btn:Sprite = new Sprite();
    //btn.graphics.lineStyle(1, 0xeeeeee, 0.2);
    btn.graphics.beginFill(0xeeeeee, 0.01);
    btn.graphics.drawCircle(0, 0, r.height/3);
    btn.x = r.x-(r.height/3);
    btn.y = r.y+r.height/2;
    btn.graphics.lineStyle(1,0xeeeeee,0.7);
    btn.graphics.beginFill(0xeeeeee, 0.5);
    btn.graphics.moveTo(-r.height/5, -r.height/5);
    btn.graphics.lineTo( r.height/5, -r.height/5);
    btn.graphics.lineTo(          0,  r.height/6);
    btn.rotation = is_hidden ? -90 : 0;
    row_sprite.addChild(btn);
    btn.name = "collapse_btn";

    function do_hide():Void
    {
      var idx = row_sprite.parent.getChildIndex(row_sprite);
      var hiding = true;
      var dy = 0.0;
      for (i in (idx+1)...row_sprite.parent.numChildren) {
        var later = row_sprite.parent.getChildAt(i);
        if (later.x <= row_sprite.x) hiding = false;
        if (hiding && later.visible) {
          later.visible = false;
          dy += later.height;
        }
        later.y -= dy;
      }
    }

    function do_show(recursive:Bool=true):Void
    {
      var idx = row_sprite.parent.getChildIndex(row_sprite);
      var showing = true;
      var dy = 0.0;
      var at_x = recursive ? -1 : row_sprite.parent.getChildAt(idx+1).x;
      for (i in (idx+1)...row_sprite.parent.numChildren) {
        var later:Sprite = cast(row_sprite.parent.getChildAt(i));
        if (later.x <= row_sprite.x) showing = false;
        if (showing && !later.visible && (recursive || Math.abs(at_x-later.x)<0.01)) {
          later.visible = true;
          dy += later.height;
          // Update newly visible button
          var later_btn = later.getChildByName("collapse_btn");
          if (later_btn!=null) {
            later_btn.rotation = (recursive || row_sprite.parent.getChildAt(i+1).visible) ? 0 : -90;
          }
        }
        later.y += dy;
      }
    }

    function toggle_collapse(e:Event=null):Void
    {
      is_hidden = !is_hidden;
      Actuate.tween(btn, 0.2, { rotation: is_hidden ? -90 : 0 });
      if (is_hidden) do_hide();
      else do_show(cast(e).shiftKey);

      // Invalidate scrollbars
      do_refresh_scrollbars();
    }

    AEL.add(btn, MouseEvent.CLICK, toggle_collapse);
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
  
  