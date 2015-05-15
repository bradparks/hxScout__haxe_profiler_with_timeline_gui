package;

import flash.display.*;
import flash.events.*;

import haxe.ds.StringMap;
import haxe.ds.IntMap;

import hxtelemetry.HxTelemetry;

class FLMConst
{
  // Others mem keys seen:
  // - bytearray.alchemy
  // - bitmap.image
  // - network
  // - network.shared
  // - bitmap.source

  public static var mem_keys = ["total","used","managed.used","bitmap","bytearray","script","network","telemetry.overhead","managed","bitmap.display","bitmap.data"];
  public static var mem_info = {
    "managed.used":{ description:"ActionScript Objects", color:0x227788 },
    "bitmap":{ description:"Bitmap", color:0x22aa99 },
    "telemetry.overhead":{ description:"Other", color:0x667755 },
    "network":{ redirect:"telemetry.overhead" }, // Also 'other', Network Buffers
    "script":{ description:"SWF Files", color:0x119944 },
    "bytearray":{ description:"ByteArrays", color:0x11bb66 }
  }

  public static var timing_keys:Array<String> = ["as", "rend", "net", "gc", "other"];
  public static var timing_info:StringMap<hxtelemetry.HxTelemetry.ActivityDescriptor> =
    new StringMap<hxtelemetry.HxTelemetry.ActivityDescriptor>();
  private static var __init:Bool = (function() {
    Util.each([
      {name:"as", description:"ActionScript", color:0x2288cc },
      {name:"rend", description:"Rendering", color:0x66aa66 },
      {name:"net", description:"Network", color:0xcccc66 },
      {name:"gc", description:"Garbage Collection", color:0xdd5522 },
      {name:"other", description:"Other", color:0xaa4488 }
    ],
    function(v:Dynamic) {
      var ad:hxtelemetry.HxTelemetry.ActivityDescriptor = v;
      timing_info.set(ad.name, ad);
    });
    return true;
  })();
}
