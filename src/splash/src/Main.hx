package;

import flash.display.*;
import flash.events.*;

@:bitmap("assets/splash.png") class Splash extends BitmapData {}

class Main extends Sprite {

  public function new()
  {
    super();
    //var bitmap = new Bitmap(openfl.Assets.getBitmapData("assets/splash.png"));
    var bitmap = new Bitmap(new Splash(0,0));
    addChild(bitmap);

    var t = new flash.text.TextField();
    var format = new flash.text.TextFormat("Courier", 12, 0x111111);
    format.align = openfl.text.TextFormatAlign.CENTER;
    t.defaultTextFormat = format;
    t.text = Build.git_rev();
    t.width = t.textWidth*1.1;
    t.x = 210 - t.width/2;
    t.y = 186;
    addChild(t);

    // if (Sys.args().indexOf("-nosplash")<0) {
    // var p = new sys.io.Process(Sys.getCwd()+"GUI", ["-nosplash"]);

    function go():Void {
#if win
      var code = Sys.command("START /B GUI");
#else
      var code = Sys.command(Sys.getCwd()+"GUI &");
#end
      Sys.exit(0);
    }

    haxe.Timer.delay(go, 2500);
    addEventListener(flash.events.MouseEvent.CLICK, function(e:Event) { go(); });
    return;
  }
}
