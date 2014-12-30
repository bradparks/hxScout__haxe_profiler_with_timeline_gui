package;

import haxe.macro.Context;

class Build {
  macro public static function git_rev() {
    var ver = "v "+sys.io.File.getContent("../version.txt");
    var nl = ~/\n/g;
    ver = nl.replace(ver, "");
    ver = ver + " [" + nl.replace(new sys.io.Process("git", ["rev-parse", "--short", "HEAD"]).stdout.readAll().toString(), "") + "]";
    return Context.makeExpr(ver, Context.currentPos());
  }
}
