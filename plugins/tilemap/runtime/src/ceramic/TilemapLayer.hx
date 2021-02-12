package ceramic;

using ceramic.Extensions;

class TilemapLayer extends Visual {

    public var layerData(default,set):TilemapLayerData = null;
    function set_layerData(layerData:TilemapLayerData):TilemapLayerData {
        if (this.layerData == layerData) return layerData;
        this.layerData = layerData;
        contentDirty = true;
        return layerData;
    }

    public var tileScale(default,set):Float = 1.0;
    function set_tileScale(tileScale:Float):Float {
        if (this.tileScale == tileScale) return tileScale;
        this.tileScale = tileScale;
        contentDirty = true;
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

    public var tileQuads(default,null):Array<TilemapQuad> = [];

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

        if (layerData == null) {
            width = 0;
            height = 0;
            contentDirty = false;
            return;
        }

        computeTileQuads();

        contentDirty = false;
        
    }

    function computeTileQuads() {

        var usedQuads = 0;

        var tilemap:Tilemap = cast parent;
        var tilemapData:TilemapData = tilemap.tilemapData;

        var hasClipping = false;
        if (clipTilesX != -1 && clipTilesY != -1 && clipTilesWidth != -1 && clipTilesHeight != -1) {
            hasClipping = true;
        }
        
        // Computing depth from render order
        var startDepthX = 0;
        var startDepthY = 0;
        var depthXStep = 1;
        var depthYStep = layerData.width;
        switch (tilemapData.renderOrder) {
            case RIGHT_DOWN:
            case RIGHT_UP:
                startDepthY = layerData.width * (layerData.height - 1);
                depthYStep = -layerData.width;
            case LEFT_DOWN:
                startDepthX = layerData.width - 1;
                depthXStep = -1;
            case LEFT_UP:
                startDepthX = layerData.width - 1;
                depthXStep = -1;
                startDepthY = layerData.width * (layerData.height - 1);
                depthYStep = -layerData.width;
        }

        var tileDepth = startDepthX;

        if (layerData.visible && layerData.tiles != null) {
            for (t in 0...layerData.tiles.length) {
                var tile = layerData.tiles.unsafeGet(t);
                var gid = tile.gid;
                
                var tileset = tilemapData.tilesetForGid(gid);

                if (tileset != null && tileset.image != null && tileset.columns > 0) {
                    var index = gid - tileset.firstGid;

                    var tileLeft = ((t % layerData.width) + layerData.x) * tileset.tileWidth + layerData.offsetX;
                    var tileTop = (Math.floor(t / layerData.width) + layerData.y) * tileset.tileWidth + layerData.offsetY;
                    var tileWidth = tileset.tileWidth;
                    var tileHeight = tileset.tileHeight;
                    var tileRight = tileLeft + tileWidth;
                    var tileBottom = tileTop + tileHeight;

                    var doesClip = false;
                    if (hasClipping) {
                        if (tileRight < clipTilesX || tileBottom < clipTilesY || tileLeft >= clipTilesX + clipTilesWidth || tileTop >= clipTilesY + clipTilesHeight) {
                            doesClip = true;
                        } 
                    }

                    if (!doesClip) {

                        var quad:TilemapQuad = usedQuads < tileQuads.length ? tileQuads[usedQuads] : null;
                        if (quad == null) {
                            quad = new TilemapQuad();
                            quad.anchor(0.5, 0.5);
                            quad.inheritAlpha = true;
                            tileQuads.push(quad);
                            add(quad);
                        }
                        usedQuads++;

                        quad.tilemapTile = tile;
                        quad.visible = true;
                        quad.texture = tileset.image.texture;
                        quad.frameX = (index % tileset.columns) * (tileset.tileWidth + tileset.margin * 2 + tileset.spacing) + tileset.margin;
                        quad.frameY = Math.floor(index / tileset.columns) * (tileset.tileHeight + tileset.margin * 2) + tileset.spacing;
                        quad.frameWidth = tileset.tileWidth;
                        quad.frameHeight = tileset.tileHeight;
                        quad.depth = startDepthX + (t % layerData.width) * depthXStep + startDepthY + Math.floor(t / layerData.width) * depthYStep;
                        quad.x = tileWidth * 0.5 + tileLeft;
                        quad.y = tileHeight * 0.5 + tileTop;

                        if (tile.diagonalFlip) {
                            
                            if (tile.verticalFlip)
                                quad.scaleX = -1.0 * tileScale;
                            else
                                quad.scaleX = tileScale;

                            if (tile.horizontalFlip)
                                quad.scaleY = tileScale;
                            else
                                quad.scaleY = -1.0 * tileScale;

                            quad.rotation = 90;
                        }
                        else {

                            if (tile.horizontalFlip)
                                quad.scaleX = -1.0 * tileScale;
                            else
                                quad.scaleX = tileScale;

                            if (tile.verticalFlip)
                                quad.scaleY = -1.0 * tileScale;
                            else
                                quad.scaleY = tileScale;

                            quad.rotation = 0;
                        }
                    }

                }

            }
        }

        // Remove unused quads
        while (usedQuads < tileQuads.length) {
            // TODO find a way to recycle this quads on the whole tilemap
            var quad = tileQuads.pop();
            quad.destroy();
        }
    }

}
