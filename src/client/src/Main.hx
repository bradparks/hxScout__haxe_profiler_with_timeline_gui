package;

import flash.display.*;
import flash.events.*;

import openfl.net.Socket;

class Main extends Sprite {

  public function new()
  {
    super();

    setup_stage();
    request_hostname(function(s) {
      trace("Got socket: "+s);
      
    });
  }

  function request_hostname(callback)
  {
    var lbl = Util.make_label("Attach to hxScout server at: ", 17);
    var inp:Dynamic = null;
    inp = Util.make_input(200, 17, 0xaaaaaa, "localhost:7935",
                          function(hostname) {
                            var s:Socket = null;
                            function success() {
                              Util.fade_away(lbl);
                              Util.fade_away(inp.cont).then(function() {
                                callback(s);
                              });
                            }
                            function err() {
                              trace("Shaking cont!");
                              Util.shake(inp.cont);
                            }
                            var host = hostname;
                            var port:Int = 7935;
                            if (~/:\d+$/.match(host)) {
                              host = ~/:\d+$/.replace(hostname, "");
                              port = Std.parseInt(~/.*:(\d+)/.replace(hostname, "$1"));
                            }
                            trace("Connecting to host="+host+", port="+port);
                            s = setup_socket(host, port, success, err);
                          });

    // BUG: trace(inp.cont.width);  returns null in neko

    lbl.x = -(lbl.width + inp.bug)/2;
    lbl.y = -lbl.height/2;
    inp.cont.x = lbl.x + lbl.width;
    inp.cont.y = lbl.y;
    addChild(lbl);
    addChild(inp.cont);
  }

  function setup_stage()
  {
    var fps = new openfl.display.FPS(0,0,0xffffff);
    addChild(fps);
    var This = this;
    function center(e=null) {
      This.x = stage.stageWidth/2;
      This.y = stage.stageHeight/2;
      fps.x = -This.x;
      fps.y = -This.y;
    }
    center();
    stage.addEventListener(flash.events.Event.RESIZE, center);
  }

  function setup_socket(host, port, on_success, on_cannot_connect)
  {
    var s = new Socket();

    var cleanup = null;

    function error(e) {
      trace("Error, connect failed!");
      cleanup();
      on_cannot_connect();
    }
    function connect(e) {
      trace("Socket connect succeeded!");
      cleanup();
      on_success();
    }

    cleanup = function() {
      s.removeEventListener(IOErrorEvent.IO_ERROR, error);
      s.removeEventListener(Event.CONNECT, connect);
    }

    s.addEventListener(IOErrorEvent.IO_ERROR, error);
    s.addEventListener(Event.CONNECT, connect);
    s.connect(host, port);

    return s;
  }

}
