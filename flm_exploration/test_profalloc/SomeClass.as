package
{
  import flash.utils.*;

  public class SomeClass
  {
    private static var _ref:Array = [];

    // self 3, total 3+2+16+8, alloc 1+4+1+4=10mb, 
    public static function foo_a():void
    {
      var t0:Number = getTimer();
      var i:int = 0;
      while (getTimer()-t0 < 3) {
        for (var j=0; j<1000; j++) { i++; }
      }

      self_2ms_1mb();
      self_8ms_total_16ms_4mb();
      alloc_1mb_64strings();
      foo_b();
    }

    // self 0, total 8ms, alloc 4mb
    public static function foo_b():void
    {
      alloc_1mb_64strings();
      self_2ms_total_8ms_3mb();
    }

    public static function clear():void
    {
      _ref.length = 0;
    }

    public static function self_2ms_1mb():void
    {
      var t0:Number = getTimer();
      var i:int = 0;
      while (getTimer()-t0 < 2) {
        for (var j=0; j<1000; j++) { i++; }
      }
      alloc_1mb_64strings();
    }

    public static function self_8ms_total_16ms_4mb():void
    {
      var t0:Number = getTimer();
      var i:int = 0;
      while (getTimer()-t0 < 8) {
        for (var j=0; j<1000; j++) { i++; }
      }
      for (i=0; i<4; i++) self_2ms_1mb();
    }

    public static function self_2ms_total_8ms_3mb():void
    {
      var t0:Number = getTimer();
      var i:int = 0;
      while (getTimer()-t0 < 2) {
        for (var j=0; j<1000; j++) { i++; }
      }
      for (i=0; i<3; i++) self_2ms_1mb();
    }

    public static function alloc_1mb_64strings():void
    {
      var b:ByteArray = new ByteArray();
      b.length = 1024*1024;
      b.position = 1024*1024 - 1;
      b.writeByte(1);
      _ref.push(b);
      alloc_64_strings();
    }

    public static function alloc_64_strings():void
    {
      for (var i:int=0; i<64; i++) {
        _ref.push(i+" <--- a string is a string is a string, and by any other name, still a string!");
      }
    }

  }
}
