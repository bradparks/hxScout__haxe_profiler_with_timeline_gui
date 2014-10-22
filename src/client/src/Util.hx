package;

import flash.display.*;
import flash.text.*;
import flash.events.*;
import flash.filters.*;

import openfl.Assets;

import motion.Actuate;

class Util {
  private static var font;

  public static function make_label(text:String,
                                    size:Int=11,
                                    color:Int=0xaaaaaa,
                                    width:Int=-1)
  {
    if (font==null) font = Assets.getFont("assets/DroidSans.ttf");

    var format = new TextFormat(font.fontName, size, color);
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

    input.addEventListener(KeyboardEvent.KEY_DOWN, function(e) {
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
    btn.addEventListener(MouseEvent.MOUSE_OVER, function(e) {
      Actuate.tween(btn, 0.4, { alpha: 1 });
    }, 1, true);
    btn.addEventListener(MouseEvent.MOUSE_OUT, function(e) {
      Actuate.tween(btn, 0.3, { alpha: 0.5 });
    }, 1, true);
    btn.addEventListener(MouseEvent.CLICK, function(e) {
      if (submit!=null) submit(input.text);
    }, 1, true);
    cont.addChild(btn);

    var lbl = make_label(">", size, color);
    lbl.x = width-size*1.2;
    lbl.mouseEnabled = false;
    cont.addChild(lbl);

    return {cont:cont, input:input };
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

  public static function shake(d:DisplayObject)
  {
    var orig_x:Float = d.x;
    Actuate.tween(d, 0.3*0.1, { x: orig_x-10 });
    Actuate.tween(d, 0.3*0.15, { x: orig_x+10 }, false).delay(0.2);
    Actuate.tween(d, 0.3*0.2, { x: orig_x-10 }, false).delay(0.4);
    Actuate.tween(d, 0.3*0.15, { x: orig_x+10 }, false).delay(0.6);
    Actuate.tween(d, 0.3*0.1, { x: orig_x }, false).delay(0.8);
  }
                                   

}
