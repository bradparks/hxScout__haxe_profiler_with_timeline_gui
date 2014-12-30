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
      }, 5000);

      // Alloc on each frame, 10x the frame number
      var frame:int = 0;
      stage.addEventListener(Event.ENTER_FRAME,
                             function():void {
                               frame++;

                               if (frame%15==5) SomeClass.foo_a();
                               if (frame%15==10) SomeClass.foo_b();
                               if (frame%15==0) SomeClass.clear();

                             });

    }
  }
}
