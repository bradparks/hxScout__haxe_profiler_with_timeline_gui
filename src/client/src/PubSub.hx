package;

import haxe.ds.StringMap;
import cpp.vm.Mutex;

class DLLNode<T>
{
  public var prev:DLLNode<T>;
  public var next:DLLNode<T>;
  public var item:T;
  public function new() {
    prev = null;
    next = null;
    item = null;
  }
}

class PubSub
{
  private static var listeners = new StringMap<DLLNode<Dynamic->Void>>();
  private static var mutex:Mutex = new Mutex();

  public static function subscribe(channel:String,
                                   handler:Dynamic->Void):Void->Void
  {
    if (handler==null) throw "Cannot add null handler!";

    mutex.acquire();
    var ptr:DLLNode<Dynamic->Void>;
    if (!listeners.exists(channel)) {
      ptr = new DLLNode<Dynamic->Void>();
      listeners.set(channel, ptr);
    } else{
      ptr = listeners.get(channel);
    }

    while (ptr.next!=null) ptr = ptr.next;
    ptr.next = new DLLNode<Dynamic->Void>();
    ptr.next.prev = ptr;
    ptr = ptr.next;
    ptr.item = handler;

    mutex.release();

    // Returns an unsubscribe function
    return function():Void {
      // unlink
      mutex.acquire();
      ptr.prev.next = ptr.next;
      if (ptr.next!=null) ptr.next.prev = ptr.prev;
      mutex.release();
    }
  }

  public static function publish(channel:String,
                                 data:Dynamic=null):Void
  {
    mutex.acquire();
    if (listeners.exists(channel)) {
      var ptr = listeners.get(channel);
      while ((ptr=ptr.next)!=null) {
        ptr.item(data);
      }
    }
    mutex.release();
  }
}
