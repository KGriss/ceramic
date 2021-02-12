package ceramic;

using ceramic.Extensions;

/**
 * Renders tilemap data.
 * Note: only ORTHOGONAL is supported
 */
class Tilemap extends Quad {

/// Properties

    public var tilemapData(default,set):TilemapData = null;
    function set_tilemapData(tilemapData:TilemapData):TilemapData {
        if (this.tilemapData == tilemapData) return tilemapData;
        this.tilemapData = tilemapData;
        contentDirty = true;
        return tilemapData;
    }

    public var tileScale(default,set):Float = 1.0;
    function set_tileScale(tileScale:Float):Float {
        if (this.tileScale == tileScale) return tileScale;
        this.tileScale = tileScale;
        if (tileScale != -1) {
            for (i in 0...layers.length) {
                layers.unsafeGet(i).tileScale = tileScale;
            }
        }
        return tileScale;
    }

    public var clipTilesX(default,set):Float = -1;
    function set_clipTilesX(clipTilesX:Float):Float {
        if (this.clipTilesX == clipTilesX) return clipTilesX;
        this.clipTilesX = clipTilesX;
        contentDirty = true;
        return clipTilesX;
    }

    public var clipTilesY(default,set):Float = -1;
    function set_clipTilesY(clipTilesY:Float):Float {
        if (this.clipTilesY == clipTilesY) return clipTilesY;
        this.clipTilesY = clipTilesY;
        contentDirty = true;
        return clipTilesY;
    }

    public var clipTilesWidth(default,set):Float = -1;
    function set_clipTilesWidth(clipTilesWidth:Float):Float {
        if (this.clipTilesWidth == clipTilesWidth) return clipTilesWidth;
        this.clipTilesWidth = clipTilesWidth;
        contentDirty = true;
        return clipTilesWidth;
    }

    public var clipTilesHeight(default,set):Float = -1;
    function set_clipTilesHeight(clipTilesHeight:Float):Float {
        if (this.clipTilesHeight == clipTilesHeight) return clipTilesHeight;
        this.clipTilesHeight = clipTilesHeight;
        contentDirty = true;
        return clipTilesHeight;
    }

    public var layers:Array<TilemapLayer> = [];

/// Overrides

    override function get_width():Float {
        if (contentDirty) computeContent();
        return super.get_width();
    }

    override function get_height():Float {
        if (contentDirty) computeContent();
        return super.get_height();
    }

/// Lifecycle

    public function new() {

        super();

    }

/// Display

    override function computeContent() {

        if (tilemapData == null) {
            width = 0;
            height = 0;
            contentDirty = false;
            return;
        }

        computeLayers();

        contentDirty = false;

    }

    function computeLayers() {

        var usedLayers = 0;
        var tileScale = this.tileScale;

        for (l in 0...tilemapData.layers.length) {
            var layerData = tilemapData.layers.unsafeGet(l);

            var layer:TilemapLayer = usedLayers < layers.length ? layers[usedLayers] : null;
            if (layer == null) {
                layer = new TilemapLayer();
                if (tileScale != -1) layer.tileScale = tileScale;
                layer.depthRange = 1;
                layers.push(layer);
                add(layer);
            }
            usedLayers++;

            layer.depth = l + 1;
            layer.layerData = layerData;
            layer.clipTilesX = clipTilesX;
            layer.clipTilesY = clipTilesY;
            layer.clipTilesWidth = clipTilesWidth;
            layer.clipTilesHeight = clipTilesHeight;
        }

        // Remove unused layers
        while (usedLayers < layers.length) {
            var layer = layers.pop();
            layer.destroy();
        }

    }

/// Clip

    public function clipTiles(clipTilesX, clipTilesY, clipTilesWidth, clipTilesHeight) {

        this.clipTilesX = clipTilesX;
        this.clipTilesY = clipTilesY;
        this.clipTilesWidth = clipTilesWidth;
        this.clipTilesHeight = clipTilesHeight;

    }

#if ceramic_arcade_physics

/// Arcade physics

    public var collidableLayers(default, set):ReadOnlyArray<String> = null;
    function set_collidableLayers(collidableLayers:ReadOnlyArray<String>):ReadOnlyArray<String> {
        if (this.collidableLayers == collidableLayers) return collidableLayers;
        this.collidableLayers = collidableLayers;
        collidableLayersDirty = true;
        return collidableLayers;
    }

    public var computedCollidableLayers(default, null):ReadOnlyArray<TilemapLayer> = null;

    public var collidableLayersDirty:Bool = false;

    @:allow(ceramic.ArcadeWorld)
    function computeCollidableLayers():Void {
        
        if (contentDirty)
            computeContent();

        var result:Array<TilemapLayer> = null;

        if (layers != null && layers.length > 0 && collidableLayers != null && collidableLayers.length > 0) {
            for (i in 0...collidableLayers.length) {
                var name = collidableLayers.unsafeGet(i);
                for (l in 0...layers.length) {
                    var layer = layers.unsafeGet(l);
                    var layerData = layer.layerData;
                    if (layerData != null && layerData.name == name) {
                        if (result == null) {
                            result = [];
                        }
                        result.push(layer);
                    }
                }
            }
        }

        // TODO destroy arcade bodies on layers that are not collidable anymore, if any

        computedCollidableLayers = result;
        collidableLayersDirty = false;

    }

#end

}
