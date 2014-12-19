import haxe.ds.*;
import flash.display.*;
import flash.events.*;

class AEL {
  private static var _ael_do = new ObjectMap<DisplayObject, StringMap<Array<Dynamic>>>();

  public static function add(d:DisplayObject,
                             event:String,
                             func)
  {
    var hash = null;
    if (!_ael_do.exists(d)) {
      hash = new StringMap<Array<Dynamic>>();
      _ael_do.set(d, hash);
      //trace(" --- AEL watching: "+d);
      add(d, Event.REMOVED_FROM_STAGE, cleanup);
    } else hash = _ael_do.get(d);
    var arr = null;
    if (!hash.exists(event)) {
      arr = [];
      hash.set(event, arr);
    } else arr = hash.get(event);
    arr.push(func);
    d.addEventListener(event, func);
  }

  public static function remove(d:DisplayObject,
                                event:String,
                                func)
  {
    var hash = null;
    if (!_ael_do.exists(d)) return;
    hash = _ael_do.get(d);
    var arr = null;
    if (!hash.exists(event)) return;
    arr = hash.get(event);
    var idx = arr.indexOf(func);
    if (idx>=0) {
      d.removeEventListener(event, func);
      arr.splice(idx, 1);
    }
  }
  
  public static function cleanup(e:Event)
  {
    GlobalTimer.setTimeout(function() {
      var d = cast(e.target, DisplayObject);
      if (d.stage!=null) return;
      if (!_ael_do.exists(d)) return;
      var hash = _ael_do.get(d);
      var keys = hash.keys();
      var event:String;
      while (keys.hasNext()) {
        var event:String = keys.next();
        var arr = hash.get(event);
        var func = null;
        for (func in arr) {
          d.removeEventListener(event, func);
          //trace("    - removing: "+event+" from "+d);
        }
      }
      _ael_do.remove(d);
      //trace(" --- AEL Cleanup on: "+d);
    }, 2);
  }

}
