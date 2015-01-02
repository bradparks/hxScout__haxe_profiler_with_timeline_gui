package
{
  import flash.display.Sprite;
  import flash.events.Event;
  import flash.utils.getTimer;
  import flash.utils.setTimeout;
  import flash.geom.Rectangle;
  import flash.text.TextField;

  [SWF( width="640", height="480", backgroundColor="#eeeeee", frameRate="30")]
  public class Main extends Sprite
  {
    // Exit after 0.5 seconds
    public function Main():void
    {
      var refs:Array = [];

      stage.scaleMode = 'noScale';
      stage.align = 'topLeft';

      var t:TextField = new TextField();
      t.text = "This SWF is compiled with -advanced-telemetry\n\nIf you have a .telemetry.cfg setup,\nstart hxScout, and load this SWF,\nyou'll see timing, profiler, and\nallocation data in hxScout.";
      t.width = stage.stageWidth;
      addChild(t);

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
