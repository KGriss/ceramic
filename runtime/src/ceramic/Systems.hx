package ceramic;

import ceramic.ReadOnlyArray;
import ceramic.System;
import haxe.ds.ArraySort;

using ceramic.Extensions;

@:allow(ceramic.App)
class Systems extends Entity {

    /**
     * If `true`, `earlyUpdateOrdered` list needs to be sorted
     */
    var earlyUpdateOrderDirty:Bool = false;

    /**
     * If `true`, `lateUpdateOrdered` list needs to be sorted
     */
    var lateUpdateOrderDirty:Bool = false;

    /**
     * List of systems, ordered ascending according to their `earlyUpdateOrder` property
     */
    var earlyUpdateOrdered:ReadOnlyArray<System> = [];

    /**
     * List of systems, ordered ascending according to their `lateUpdateOrder` property
     */
    var lateUpdateOrdered:ReadOnlyArray<System> = [];

    /**
     * Internal pre-allocated array used for iteration
     */
    var _udpatingSystems:Array<System> = [];

    private function new() {

        super();

    }

    function addSystem(system:System):Void {

        earlyUpdateOrdered.original.push(system);
        earlyUpdateOrderDirty = true;

        lateUpdateOrdered.original.push(system);
        lateUpdateOrderDirty = true;

    }

    function removeSystem(system:System):Void {

        earlyUpdateOrdered.original.remove(system);
        earlyUpdateOrderDirty = true;

        lateUpdateOrdered.original.remove(system);
        lateUpdateOrderDirty = true;

    }

    function earlyUpdate(delta:Float):Void {

        // Sort if needed
        if (earlyUpdateOrderDirty) {
            ArraySort.sort(earlyUpdateOrdered.original, sortSystemsByEarlyUpdateOrder);
            earlyUpdateOrderDirty = false;
        }

        // Work on a copy of systems list, to ensure nothing bad happens
        // if a new system is created or destroyed during iteration
        var len = earlyUpdateOrdered.length;
        for (i in 0...len) {
            _udpatingSystems[i] = earlyUpdateOrdered.unsafeGet(i);
        }

        // Call
        for (i in 0...len) {
            var system = _udpatingSystems.unsafeGet(i);
            system.emitBeginEarlyUpdate(delta);
            system.earlyUpdate(delta);
            system.emitEndEarlyUpdate(delta);

            // Flush immediate
            ceramic.App.app.flushImmediate();
        }

        // Cleanup array
        for (i in 0...len) {
            _udpatingSystems.unsafeSet(i, null);
        }
        
    }

    function lateUpdate(delta:Float):Void {

        // Sort if needed
        if (lateUpdateOrderDirty) {
            ArraySort.sort(lateUpdateOrdered.original, sortSystemsByLateUpdateOrder);
            lateUpdateOrderDirty = false;
        }

        // Work on a copy of systems list, to ensure nothing bad happens
        // if a new system is created or destroyed during iteration
        var len = lateUpdateOrdered.length;
        for (i in 0...len) {
            _udpatingSystems[i] = lateUpdateOrdered.unsafeGet(i);
        }

        // Call
        for (i in 0...len) {
            var system = _udpatingSystems.unsafeGet(i);
            system.emitBeginLateUpdate(delta);
            system.lateUpdate(delta);
            system.emitEndLateUpdate(delta);

            // Flush immediate
            ceramic.App.app.flushImmediate();
        }

        // Cleanup array
        for (i in 0...len) {
            _udpatingSystems.unsafeSet(i, null);
        }
        
    }

/// Helpers

    public function get(name:String):System {

        for (i in 0...earlyUpdateOrdered.length) {
            var system = earlyUpdateOrdered.unsafeGet(i);
            if (system.name == name) {
                return system;
            }
        }

        return null;

    }

/// Sorting

    static function sortSystemsByEarlyUpdateOrder(a:System, b:System):Int {

        if (a.earlyUpdateOrder > b.earlyUpdateOrder)
            return 1;
        else if (a.earlyUpdateOrder < b.earlyUpdateOrder)
            return -1;
        else
            return 0;

    }

    static function sortSystemsByLateUpdateOrder(a:System, b:System):Int {

        if (a.lateUpdateOrder > b.lateUpdateOrder)
            return 1;
        else if (a.lateUpdateOrder < b.lateUpdateOrder)
            return -1;
        else
            return 0;

    }

}
