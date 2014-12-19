package
{
  import flash.display.Sprite;
  import flash.events.Event;
  import flash.desktop.NativeApplication;
  import flash.utils.getTimer;
  import flash.utils.setTimeout;
  import flash.geom.Rectangle;

  [SWF( width="640", height="480", backgroundColor="#ff0000", frameRate="60")]
  public class Main extends Sprite
  {
    // Exit after 0.5 seconds
    public function Main():void
    {
      var refs:Array = [];

      setTimeout(function():void {
        trace("Goodbye!");
        NativeApplication.nativeApplication.exit();
      }, 500);

      // Alloc on each frame, 10x the frame number
      var frame:int = 0;
      stage.addEventListener(Event.ENTER_FRAME,
                             function():void {
                               frame++;

                               for (var i:int=0; i<frame*10; i++) {
                                 var obj = { "a":Math.random() };
                                 refs.push(obj);
                               }
                               if (frame%10==0) refs.length = 0; // release!
                             });

    }
  }
}
