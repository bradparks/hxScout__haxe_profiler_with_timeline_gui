package;

import sys.net.Socket;
import amf.io.Amf3Reader;
import cpp.vm.Thread;
import haxe.io.*;
import haxe.ds.StringMap;

class Server {
  static public function main() {
    trace("hxScout");

    var listener = Thread.create(FLMListener.start);
    listener.sendMessage(Thread.current());

    var s = new Socket();
    s.bind(new sys.net.Host("0.0.0.0"),7933); // hxScout client port
    s.listen(2);
    s.setBlocking(true);

    var policy = "<policy-file-request/>";
    var policy_idx = 0;

    while( true ) {
      trace("Waiting for client on 7933...");
      var client_socket : Socket = s.accept();
      trace("-- Connected on 7933, waiting for data");
      client_socket.setBlocking(false);
      while (true) {
        var data = 0;
        try {
          data = client_socket.input.readByte();
          //trace(ts()+"Read data from client: "+data);
        } catch (e:Dynamic) {
          if (Type.getClass(e)==haxe.io.Eof) {
            trace("Client disconnected!");
            client_socket.close();
            break;
          }
          else if (e=="Blocked") {
            // no data from client
          }
          else {
            // Unknown exception, rethrow
            throw e;
          }
        }

        if (policy.charCodeAt(policy_idx)==data) { // <policy-file-request/>
          policy_idx++;
          if (policy_idx==policy.length && client_socket.input.readByte()==0) {
            trace("Got policy file req on 7933");
            FLMUtil.send_policy_file(client_socket); // closes socket
            break;
          }
        } else {
          policy_idx = 0;
        }

        var frame_data = Thread.readMessage(false);
        if (frame_data!=null) {
          var b = Bytes.ofString(frame_data);
          //trace("Writing frame_data length="+b.length);
          client_socket.output.writeInt32(b.length);
          client_socket.output.writeBytes(b, 0, b.length);
        } else {
          // No frame data, sleep for a bit
          Sys.sleep(0.033);
        }
      }
    }
  }

  static var t0:Float = Date.now().getTime();
  static function ts():String {
    var t:Float = (Date.now().getTime()-t0)/1000.0;
    return (t)+" s: ";
  }

}
