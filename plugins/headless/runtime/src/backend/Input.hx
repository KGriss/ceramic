package backend;

class Input implements tracker.Events implements spec.Input {

    @event function keyDown(key:ceramic.Key);
    @event function keyUp(key:ceramic.Key);

    @event function gamepadAxis(gamepadId:Int, axisId:Int, value:Float);
    @event function gamepadDown(gamepadId:Int, buttonId:Int);
    @event function gamepadUp(gamepadId:Int, buttonId:Int);
    @event function gamepadEnable(gamepadId:Int, name:String);
    @event function gamepadDisable(gamepadId:Int);

    public function new() {
        
    }

}
