package
{
  import flash.utils.*;

  public class SomeClass
  {
    private static var _rel:Array = [];

    public static function foo1():void
    {
      for (var i:int=0; i<10000; i++) {
        _rel.push(foo2());
      }
      setTimeout(function():void {
        for (var i:int=0; i<10000; i++) {
          _rel.shift();
        }
      }, 2000);
    }

    public static function foo2():Array
    {
      var a:Array = [];
      for (var i:int=0; i<10000; i++) {
        a.push(new Point(Math.random(), Math.random()));
      }
      return a;
    }

  }
}
