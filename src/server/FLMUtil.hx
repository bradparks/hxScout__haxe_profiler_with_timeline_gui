package;

import sys.net.Socket;
import amf.io.Amf3Reader;
import cpp.vm.Thread;
import haxe.io.*;
import haxe.ds.StringMap;

class FLMUtil
{
  public static function send_policy_file(s:Socket)
  {
    s.output.writeString('<cross-domain-policy><site-control permitted-cross-domain-policies="master-only"/><allow-access-from domain="*" to-ports="7934,7933"/></cross-domain-policy>');
    s.output.writeByte(0);
    s.close();
  }
}

