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

    // if (Sys.args().indexOf("-nosplash")<0) {
    // var p = new sys.io.Process(Sys.getCwd()+"GUI", ["-nosplash"]);

    haxe.Timer.delay(function():Void {
#if win
        var code = Sys.command("START /B GUI");
#else
        var code = Sys.command(Sys.getCwd()+"GUI &");
#end
        Sys.exit(0);

    }, 2000);
    return;
  }
}
