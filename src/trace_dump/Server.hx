package;

import sys.net.Socket;
import amf.io.Amf3Reader;

class Server {
  static function main() {
    trace("Starting telemetry listener...");
    var s = new Socket();
    s.bind(new sys.net.Host("localhost"),7934); // Default Scout port
    s.listen(2);

    while( true ) {
      trace("Waiting for connection on 7934...");
      var flm_socket : Socket = s.accept();
      trace(" --- Client connected ---");
      var r = new Amf3Reader(flm_socket.input);
      var connected = true;
      while( connected ) {

        // Read next event blob. TODO: r.eof? socket.eof? instead of try/catch
        var data:Map<String, Dynamic> = null;
        try {
          data = r.read();
        } catch( e:Dynamic )  {
          // Handle EOF
          if (Type.getClass(e)==haxe.io.Eof) {
            connected = false;
            flm_socket.close();
            break;
          }
          // Other errors, rethrow
          throw e;
        }
        if (data['name']==".trace") {
          Sys.stdout().writeString(data['value']+"\n");
        }
      }
    }
  }
}
