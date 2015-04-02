package openfl._v2.display; #if (!flash && !html5 && !openfl_next)


class ShapeNoEvents extends Shape {
	
	
	public function new () {
		super ();
	}

  // No events for added/removed
	@:noCompletion override private function __onAdded (object:DisplayObject, isOnStage:Bool):Void { }
	@:noCompletion override private function __onRemoved (object:DisplayObject, wasOnStage:Bool):Void { }
	
}

#end
