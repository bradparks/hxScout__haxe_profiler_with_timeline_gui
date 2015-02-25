package;

import flash.display.*;
import flash.text.*;
import flash.events.*;
import flash.filters.*;
import haxe.ds.*;
import openfl.Assets;

import motion.Actuate;

class Util {
  public static var stage:openfl.display.Stage;

  private static var fonts:StringMap<Font> = new StringMap<Font>();

  public static function make_label(text:String,
                                    size:Int=11,
                                    color:Int=0xaaaaaa,
                                    width:Int=-1,
                                    font_file:String="DroidSans.ttf")
  {
    if (!fonts.exists(font_file)) fonts.set(font_file, Assets.getFont("assets/"+font_file));

    var format = new TextFormat(fonts.get(font_file).fontName, size, color);
    var textField = new TextField();

    textField.defaultTextFormat = format;
    textField.embedFonts = true;
    textField.selectable = false;

    textField.text = text;
    textField.width = (width >= 0) ? width : textField.textWidth+4;
    textField.height = textField.textHeight+4;

    return textField;
  }

  public static function make_input(width:Int=200,
                                    size:Int=11,
                                    color:Int=0xaaaaaa,
                                    text:String="",
                                    submit:String->Void=null)
  {
    var cont = new Sprite();

    var bkg = new flash.display.Shape();
    bkg.graphics.beginFill(color, 0.2);
    bkg.graphics.lineStyle(1, 0xffffff);
    bkg.graphics.drawRoundRect(0,0,width,size*1.5, 3);
    cont.addChild(bkg);

    var input = make_label(text, size, color, Std.int(width-4-size*1.5));
    input.x = 2;
    input.selectable = true;
    input.type = openfl.text.TextFieldType.INPUT;
    cont.addChild(input);

    // TODO: dispose / remove events listeners framework
    AEL.add(input, KeyboardEvent.KEY_DOWN, function(ev) {
      var e = cast(ev, KeyboardEvent);
      if (e.keyCode==13) {
        if (submit!=null) submit(input.text);
      }
    });

    var btn = new Sprite();
    btn.graphics.beginFill(color, 0.6);
    btn.graphics.lineStyle(1, 0xffffff);
    btn.graphics.drawRoundRect(0,0,size*1.5,size*1.5, 3);
    btn.x = width-size*1.5;
    btn.mouseEnabled = true;
    btn.buttonMode = true;
    btn.alpha = 0.5;

    // TODO: dispose / remove events listeners framework
    
    AEL.add(btn, MouseEvent.MOUSE_OVER, function(e) {
      Actuate.tween(btn, 0.4, { alpha: 1 });
    });
    AEL.add(btn, MouseEvent.MOUSE_OUT, function(e) {
      Actuate.tween(btn, 0.3, { alpha: 0.5 });
    });
    AEL.add(btn, MouseEvent.CLICK, function(e) {
      if (submit!=null) submit(input.text);
    });
    cont.addChild(btn);

    var lbl = make_label(">", size, color);
    lbl.x = width-size*1.2;
    lbl.mouseEnabled = false;
    cont.addChild(lbl);

    // trace(cont.width); // Not null here
    var a:Float = cont.width*1.0;

    return {cont:cont, input:input, bug:a };
  }
  public static var TEXT_SHADOW:flash.filters.DropShadowFilter = new flash.filters.DropShadowFilter(1, 120, 0x0, 0.8, 3, 3, 1, 2);
  private static var GRADIENT_M:flash.geom.Matrix = new flash.geom.Matrix();
  public static function begin_gradient(g:openfl.display.Graphics,
                                        w:Float,
                                        h:Float,
                                        c1:UInt=0x444444,
                                        c2:UInt=0x535353,
                                        angle:Float=-1.5757963):Void
  {
    GRADIENT_M.identity();
    GRADIENT_M.createGradientBox(w, h, angle);
    g.beginGradientFill(openfl.display.GradientType.LINEAR,
                        [c1,c2],
                        [1,1],
                        [0,255],
                        GRADIENT_M);
  }

  public static function fade_away(d:DisplayObject,
                                   t:Float=0.4)
  {
    var callbacks = [];
    if (Reflect.hasField(d, "mouseEnabled")) cast(d).mouseEnabled = false;
    // TODO: dispose / remove events listeners framework
    Actuate.tween(d, 0.4,
                  { alpha: 0, }
                  ).onComplete(function() {
                      while (callbacks.length>0) (callbacks.pop())();
                    });
    return {
      then:function(f:Void->Void) {
        callbacks.push(f);
      }
    };
  }

  public static function remove_children(d:DisplayObjectContainer):Void
  {
    while (d.numChildren>0) d.removeChildAt(0);
  }

  public static function shake(d:DisplayObject)
  {
    var orig_x:Float = d.x;
    var dt=0.0;
    var t=0.0;
    Actuate.tween(d, dt=0.4*0.1, { x: orig_x-6 });
    Actuate.tween(d, dt=0.4*0.15, { x: orig_x+8 }, false).delay(t+=dt);
    Actuate.tween(d, dt=0.4*0.2, { x: orig_x-8 }, false).delay(t+=dt);
    Actuate.tween(d, dt=0.4*0.3, { x: orig_x+6 }, false).delay(t+=dt);
    Actuate.tween(d, dt=0.4*0.15, { x: orig_x }, false).delay(t+=dt);
  }

  public static function add_commas(i:Int, sep:String=','):String
  {
    if (i==0) return "0";
    var neg = false;
    var cnt = 0;
    var rtn = "";
    if (i<0) { neg = true; i = -i; }
    while (i>0) {
      rtn = (i%10)+(cnt==0&&rtn.length>0?sep:'')+rtn;
      i = Math.floor(i/10);
      cnt = (cnt+1)%3;
    }
    return neg?'-'+rtn:rtn;
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
    if (dec<10) rtn += "00";
    else if (dec<100) rtn += "0";
    rtn += dec;
    return rtn;
  }

  public static function add_collapse_button(cont:Sprite,
                                             lbl:TextField,
                                             is_hidden:Bool,
                                             do_refresh_scrollbars:Void->Void):Void
  {
    var r:flash.geom.Rectangle = lbl.getBounds(cont);
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
    cont.addChild(btn);
    btn.name = "collapse_btn";

    function do_hide():Void
    {
      var idx = cont.parent.getChildIndex(cont);
      var hiding = true;
      var dy = 0.0;
      for (i in (idx+1)...cont.parent.numChildren) {
        var later = cont.parent.getChildAt(i);
        if (later.x <= cont.x) hiding = false;
        if (hiding && later.visible) {
          later.visible = false;
          dy += later.height;
        }
        later.y -= dy;
      }
    }

    function do_show(recursive:Bool=true):Void
    {
      var idx = cont.parent.getChildIndex(cont);
      var showing = true;
      var dy = 0.0;
      var at_x = recursive ? -1 : cont.parent.getChildAt(idx+1).x;
      for (i in (idx+1)...cont.parent.numChildren) {
        var later:Sprite = cast(cont.parent.getChildAt(i));
        if (later.x <= cont.x) showing = false;
        if (showing && !later.visible && (recursive || Math.abs(at_x-later.x)<0.01)) {
          later.visible = true;
          dy += later.height;
          // Update newly visible button
          var later_btn = later.getChildByName("collapse_btn");
          if (later_btn!=null) {
            later_btn.rotation = (recursive || cont.parent.getChildAt(i+1).visible) ? 0 : -90;
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
