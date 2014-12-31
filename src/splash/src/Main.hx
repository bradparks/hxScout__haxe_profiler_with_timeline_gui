package;

import flash.display.*;
import flash.events.*;

@:bitmap("assets/splash.jpg") class Splash extends BitmapData {}

class Main extends Sprite {

  public function new()
  {
    super();
    var bitmap = new Bitmap(new Splash(0,0));
    addChild(bitmap);

    var t = new flash.text.TextField();
    var format = new flash.text.TextFormat("Courier", 14, 0xeeeeee);
    format.align = openfl.text.TextFormatAlign.CENTER;
    t.defaultTextFormat = format;
    var dark = new flash.text.TextFormat("Courier", 14, 0x777777);
    t.text = Build.git_rev();
    t.setTextFormat(dark, t.text.indexOf(' - '), t.text.length);
    t.width = t.textWidth*1.1;
    t.x = 295 - t.width/2;
    t.y = 600-t.textHeight*2.25;
    addChild(t);

    function go(e:Event=null):Void {
      removeEventListener(flash.events.MouseEvent.CLICK, go);
#if win
      var code = Sys.command("START /B GUI");
#else
      var code = Sys.command(Sys.getCwd()+"GUI &");
#end
      haxe.Timer.delay(function() { Sys.exit(0); }, e==null ? 250 : 1);
    }

    haxe.Timer.delay(function() { go(); }, 2000);
    addEventListener(flash.events.MouseEvent.MOUSE_DOWN, go);
    return;
  }
}
