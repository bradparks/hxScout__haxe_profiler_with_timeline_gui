package;

import haxe.macro.Context;

class Build {
  macro public static function git_rev() {
    var nl = ~/\n/g;
    function trim(s:String):String { return nl.replace(s, ""); }
    function exec(cmd:String, args:Array<String>=null):String {
      return new sys.io.Process(cmd, (args==null? [] : args)).stdout.readAll().toString();
    }

    var ver = "v "+trim(sys.io.File.getContent("../version.txt"));
    ver = ver + " - " + trim( exec("git", ["rev-parse", "--short", "HEAD"]) );
    ver = ver + ", "+ Date.now().toString() + ", " + trim( exec("whoami") ) +"@" + trim( exec("hostname") );
    return Context.makeExpr(ver, Context.currentPos());
  }
}
