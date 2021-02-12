package ceramic;

import ceramic.Shortcuts.*;

using ceramic.Extensions;

/** An implementation-independant GPU 2D renderer.
    To be used in pair with a draw backend implementation. */
class Renderer extends Entity {

#if !ceramic_render_no_indice

    var drawCalls:Int = 0;

    var activeShader:backend.Shader = null;
    var customFloatAttributesSize:Int = 0;

    var stencilClip:Bool = false;

    var lastTexture:ceramic.Texture = null;
    var lastTextureId:backend.TextureId = backend.TextureId.DEFAULT;
    var lastShader:ceramic.Shader = null;
    var lastRenderTarget:ceramic.RenderTexture = null;
    var lastComputedBlending:ceramic.Blending = ceramic.Blending.PREMULTIPLIED_ALPHA;
    var lastClip:ceramic.Visual = null;
    var activeTextureSlot:Int = 0;

    var backendTextures:backend.Textures;
    var backendShaders:backend.Shaders;

    var texWidth:Int = 0;
    var texHeight:Int = 0;
    var texWidthActual:Int = 0;
    var texHeightActual:Int = 0;

    //var defaultPlainShader:backend.Shader = null;
    var defaultTexturedShader:backend.Shader = null;
    var defaultWhiteTexture:ceramic.Texture = null;

    var quad:ceramic.Quad = null;
    var mesh:ceramic.Mesh = null;

    var stateDirty:Bool = true;

    var z:Float = 0;

    var usedTextureIndexes:Array<Int> = [];
    var usedTextures:Int = 0;
    var maxUsableTexturesInBatch:Int = -1;
    var activeShaderCanBatchMultipleTextures:Bool = false;

    #if ceramic_debug_draw
    var lastDebugTime:Float = -1;
    var debugDraw:Bool = false;
    var drawnQuads:Int = 0;
    var drawnMeshes:Int = 0;
    var flushedQuads:Int = 0;
    var flushedMeshes:Int = 0;
    #end

    #if ceramic_debug_rendering_option
    var lastDebugRendering = ceramic.DebugRendering.DEFAULT;
    #end

    public function new() {

        super();

    }

    public function render(isMainRender:Bool, ceramicVisuals:Array<Visual>):Void {

        var draw = app.backend.draw;
        backendTextures = app.backend.textures;
        backendShaders = app.backend.shaders;

        //defaultPlainShader = ceramic.App.app.defaultColorShader.backendItem;
        defaultTexturedShader = ceramic.App.app.defaultTexturedShader.backendItem;
        defaultWhiteTexture = ceramic.App.app.defaultWhiteTexture;
        
        maxUsableTexturesInBatch = Std.int(Math.min(
            backendTextures.maxTexturesByBatch(),
            backendShaders.maxIfStatementsByFragmentShader()
        ));
        
        while (usedTextureIndexes.length < maxUsableTexturesInBatch) {
            usedTextureIndexes.push(0);
        }

        #if ceramic_avoid_last_texture_slot
        if (maxUsableTexturesInBatch > 1) {
            // On some devices, we have problems if we use the last texture slot.
            // As a workaround, we avoid using it. I wish I could understand why.
            // That's sad. Very sad.
            maxUsableTexturesInBatch--;
        }
        #end

    #if ceramic_debug_draw
        if (isMainRender) {
            if (ceramic.Timer.now - lastDebugTime > 10) {
                debugDraw = true;
                lastDebugTime = ceramic.Timer.now;
            } else {
                debugDraw = false;
            }
            drawnQuads = 0;
            drawnMeshes = 0;
            flushedQuads = 0;
            flushedMeshes = 0;
        } else {
            debugDraw = false;
        }
    #end

        drawCalls = 0;

        draw.initBuffers();

        quad = null;
        mesh = null;

        lastTexture = null;
        lastTextureId = backend.TextureId.DEFAULT;
        lastShader = null;
        lastRenderTarget = null;
        lastComputedBlending = ceramic.Blending.PREMULTIPLIED_ALPHA;
    #if ceramic_debug_rendering_option
        lastDebugRendering = ceramic.DebugRendering.DEFAULT;
    #end
        lastClip = null;
        usedTextures = 0;

        texWidth = 0;
        texHeight = 0;
        texWidthActual = 0;
        texHeightActual = 0;

        stencilClip = false;
        z = 0;
        stateDirty = true;

        //var defaultPlainShader:backend.Shader = ceramic.App.app.defaultColorShader.backendItem;
        var defaultTexturedShader:backend.Shader = ceramic.App.app.defaultTexturedShader.backendItem;

        // Mark auto-rendering render textures as dirty
        var allRenderTextures = ceramic.App.app.renderTextures;
        for (ii in 0...allRenderTextures.length) {
            var renderTexture = allRenderTextures.unsafeGet(ii);
            if (renderTexture.autoRender) {
                renderTexture.renderDirty = true;
            }
        }

        draw.beginRender();

        // Initialize default state
        draw.setActiveTexture(0);
        activeTextureSlot = 0;
        draw.setRenderTarget(null, true);
        draw.clearAndApplyBackground();
        draw.enableBlending();
        activeShader = null;
        lastShader = null;
        useShader(draw, null);


        // Default blending
        draw.setBlendFuncSeparate(
            backend.BlendMode.ONE,
            backend.BlendMode.ONE_MINUS_SRC_ALPHA,
            backend.BlendMode.ONE,
            backend.BlendMode.ONE_MINUS_SRC_ALPHA
        );
        lastComputedBlending = ceramic.Blending.PREMULTIPLIED_ALPHA;

        // Default stencil test
        draw.drawWithoutStencilTest();

        // For each ceramic visual in the list
        //
        if (ceramicVisuals != null) {

            for (ii in 0...ceramicVisuals.length) {
                var visual = ceramicVisuals.unsafeGet(ii);
                var quad = visual.asQuad;
                var mesh = visual.asMesh;

                // If it's valid to be drawn
                if (visual.computedVisible) {

                    // If it should be redrawn anyway
                    if (visual.computedRenderTarget == null || visual.computedRenderTarget.renderDirty) {

                        var clip:ceramic.Visual;
                        #if !ceramic_no_clip
                        if (visual.computedClip) {
                            // Get new clip and compare with last
                            var clippingVisual = visual;
                            while (clippingVisual != null && clippingVisual.clip == null) {
                                clippingVisual = clippingVisual.parent;
                            }
                            clip = clippingVisual != null ? clippingVisual.clip : null;

                        } else {
                        #end
                            clip = null;
                        #if !ceramic_no_clip
                        }
                        #end

                        if (clip != lastClip) {

                            flush(draw);
                            unbindUsedTextures(draw);
                            stateDirty = true;

                            if (lastClip != null) {
                                lastRenderTarget = lastClip.computedRenderTarget;
                                useRenderTarget(draw, lastRenderTarget);

                                // Finish clipping
                                draw.drawWithoutStencilTest();
                            }

                            lastClip = clip;

                            if (lastClip != null) {
                                // Update stencil buffer
                                
                                lastRenderTarget = lastClip.computedRenderTarget;
                                useRenderTarget(draw, lastRenderTarget);

                                draw.beginDrawingInStencilBuffer();

                                if (lastClip.asQuad != null) {
                                    quad = lastClip.asQuad;
                                    stencilClip = true;
                                    drawQuad(draw, quad);
                                    stencilClip = false;
                                    quad = visual.asQuad;
                                }
                                else if (lastClip.asMesh != null) {
                                    mesh = lastClip.asMesh;
                                    stencilClip = true;
                                    #if !ceramic_no_mesh
                                    drawMesh(draw, mesh);
                                    #end
                                    stencilClip = false;
                                    mesh = visual.asMesh;
                                }

                                // Next things to be drawn will be clipped
                                flush(draw);
                                unbindUsedTextures(draw);
                                stateDirty = true;

                                draw.endDrawingInStencilBuffer();
                                draw.drawWithStencilTest();
                            }
                        }

                        if (quad != null && !quad.transparent) {

                            drawQuad(draw, quad);

                        }

                        else if (mesh != null) {

                            #if !ceramic_no_mesh
                            drawMesh(draw, mesh);
                            #end

                        }
                    }
                }
            }

            flush(draw);
            unbindUsedTextures(draw);
            stateDirty = true;
        }

    #if ceramic_debug_draw
        if (debugDraw) {
            log.success(' -- $drawCalls draw call' + (drawCalls > 1 ? 's' : '') + ' / $drawnQuads quad' + (drawnQuads > 1 ? 's' : '') + ' / $drawnMeshes mesh' + (drawnMeshes > 1 ? 'es' : '') + '');
        }
    #end

    }

    #if (!ceramic_debug_draw && !ceramic_soft_inline) inline #end function drawQuad(draw:backend.Draw, quad:ceramic.Quad):Void {

    #if ceramic_debug_draw
        drawnQuads++;
    #end

        inline function flushAndCleanState() {

            flush(draw);
            unbindUsedTextures(draw);

            // Update texture
            lastTexture = quad.texture;
            useFirstTextureInBatch(draw, lastTexture);

    #if ceramic_debug_rendering_option
            lastDebugRendering = quad.debugRendering;
            draw.setRenderWireframe(lastDebugRendering == ceramic.DebugRendering.WIREFRAME);
    #end

            // Update render target
            if (quad.computedRenderTarget != lastRenderTarget) {
                lastRenderTarget = quad.computedRenderTarget;
                useRenderTarget(draw, lastRenderTarget);
            }

            // Update shader
            lastShader = quad.shader;
            useShader(draw, lastShader != null ? lastShader.backendItem : null);

            // Update blending
            lastComputedBlending = computeQuadBlending(quad);
            useBlending(draw, lastComputedBlending);

            stateDirty = false;

        }

        if (stencilClip) {
            // Special case of drawing into stencil buffer

            // No texture
            unbindUsedTextures(draw);
            useFirstTextureInBatch(draw, null);

            // Default blending
            draw.setBlendFuncSeparate(
                backend.BlendMode.ONE,
                backend.BlendMode.ONE_MINUS_SRC_ALPHA,
                backend.BlendMode.ONE,
                backend.BlendMode.ONE_MINUS_SRC_ALPHA
            );
            lastComputedBlending = ceramic.Blending.PREMULTIPLIED_ALPHA;

            // No render target when writing to stencil buffer
            lastRenderTarget = quad.computedRenderTarget;
            useRenderTarget(draw, lastRenderTarget);

            // Use default shader
            lastShader = null;
            useShader(draw, null);

            stateDirty = false;
        }
        else {
            // Check if state is dirty
            var textureToUseInSameBatch = null;
            if (!stateDirty) {
                var newComputedBlending = computeQuadBlending(quad);
                stateDirty =
                    !isSameShader(quad.shader, lastShader) ||
                    newComputedBlending != lastComputedBlending ||
    #if ceramic_debug_rendering_option
                    quad.debugRendering != lastDebugRendering ||
    #end
                    quad.computedRenderTarget != lastRenderTarget;
    #if ceramic_debug_draw_flush_reason
                if (debugDraw && stateDirty) {
                    if (!isSameShader(quad.shader, lastShader))
                        log.debug('- dirty: shader');
                    if (newComputedBlending != lastComputedBlending)
                        log.debug('- dirty: blending $lastComputedBlending -> $newComputedBlending');
                    if (quad.computedRenderTarget != lastRenderTarget)
                        log.debug('- dirty: render target');
                }
    #end
                if (!stateDirty) {
                    if (quad.texture != lastTexture) {
                        if (quad.texture != null && lastTexture != null) {
                            // Different ceramic textures could use the same backend texture
                            if (!draw.textureBackendItemMatchesId(quad.texture.backendItem, lastTextureId)) {
                                // We could use multiple texture in same batch
                                if (!canUseTextureInSameBatch(draw, quad.texture)) {
    #if ceramic_debug_draw_flush_reason
                                    if (debugDraw) {
                                        log.debug('- dirty: texture not matching');
                                    }
    #end
                                    stateDirty = true;
                                }
                                else {
                                    textureToUseInSameBatch = quad.texture;
                                }
                            }
                        } else {
                            // We could use multiple texture in same batch
                            if (!canUseTextureInSameBatch(draw, quad.texture)) {
    #if ceramic_debug_draw_flush_reason
                                if (debugDraw) {
                                    log.debug('- dirty: texture not matching');
                                }
    #end
                                stateDirty = true;
                            }
                            else {
                                textureToUseInSameBatch = quad.texture != null ? quad.texture : defaultWhiteTexture;
                            }
                        }
                    }
                }
            }

            if (stateDirty) {
                flushAndCleanState();
            }
            else {
                if (textureToUseInSameBatch != null) {
                    useTextureInSameBatch(draw, textureToUseInSameBatch);
                }
            }
        }

        // Submit the current batch if we exceed the max buffer size
        if (draw.shouldFlush(4, 6, customFloatAttributesSize)) {
            flushAndCleanState();
        }

        // Update size
        var w:Float = quad.width;
        var h:Float = quad.height;

        // Fetch matrix
        //
        var matA:Float = quad.matA;
        var matB:Float = quad.matB;
        var matC:Float = quad.matC;
        var matD:Float = quad.matD;
        var matTX:Float = quad.matTX;
        var matTY:Float = quad.matTY;
        var z:Float = this.z;
        var textureSlot:Float = activeShaderCanBatchMultipleTextures ? activeTextureSlot : -1;
        var quadDrawsRenderTexture:Bool = quad.texture != null && quad.texture.isRenderTexture;

    #if ceramic_debug_draw
        if (debugDraw && #if ceramic_debug_draw_all true #elseif ceramic_debug_multitexture activeShaderCanBatchMultipleTextures #else quad.id != null #end) {
            log.warning('* drawQuad(${quad.id != null ? quad.id : ''}) slot=$textureSlot texture=${lastTexture} stencil=$stencilClip clip=$lastClip');
        }
    #end

        // Let backend know we will start sending quad data
        draw.beginDrawQuad(quad);

        /** Using an inline internal function because we want to use similar code multiple times,
            and let haxe compiler evaluate `hasCustomAttributes` and `hasTextureSlot`
            at compile time. */
        inline function batchQuadVertices(hasCustomAttributes:Bool, hasTextureSlot:Bool) {

            var numPos = draw.getNumPos();

            //tl
            if (hasTextureSlot) {
                draw.putPosAndTextureSlot(
                    matTX,
                    matTY,
                    z,
                    textureSlot
                );
            }
            else {
                draw.putPos(
                    matTX,
                    matTY,
                    z
                );
            }
            if (hasCustomAttributes) {
                draw.beginFloatAttributes();
                for (l in 0...customFloatAttributesSize) {
                    draw.putFloatAttribute(l, 0.0);
                }
                draw.endFloatAttributes();
            }

            //tr
            if (hasTextureSlot) {
                draw.putPosAndTextureSlot(
                    matTX + matA * w,
                    matTY + matB * w,
                    z,
                    textureSlot
                );
            }
            else {
                draw.putPos(
                    matTX + matA * w,
                    matTY + matB * w,
                    z
                );
            }
            if (hasCustomAttributes) {
                draw.beginFloatAttributes();
                for (l in 0...customFloatAttributesSize) {
                    draw.putFloatAttribute(l, 0.0);
                }
                draw.endFloatAttributes();
            }

            //br
            var n8 = matTX + matA * w + matC * h;
            var n9 = matTY + matB * w + matD * h;

            if (hasTextureSlot) {
                draw.putPosAndTextureSlot(
                    n8,
                    n9,
                    z,
                    textureSlot
                );
            }
            else {
                draw.putPos(
                    n8,
                    n9,
                    z
                );
            }
            if (hasCustomAttributes) {
                draw.beginFloatAttributes();
                for (l in 0...customFloatAttributesSize) {
                    draw.putFloatAttribute(l, 0.0);
                }
                draw.endFloatAttributes();
            }

            //bl
            if (hasTextureSlot) {
                draw.putPosAndTextureSlot(
                    matTX + matC * h,
                    matTY + matD * h,
                    z,
                    textureSlot
                );
            }
            else {
                draw.putPos(
                    matTX + matC * h,
                    matTY + matD * h,
                    z
                );
            }
            if (hasCustomAttributes) {
                draw.beginFloatAttributes();
                for (l in 0...customFloatAttributesSize) {
                    draw.putFloatAttribute(l, 0.0);
                }
                draw.endFloatAttributes();
            }

            draw.putIndice(numPos);
            draw.putIndice(numPos + 1);
            draw.putIndice(numPos + 2);
            draw.putIndice(numPos + 0);
            draw.putIndice(numPos + 2);
            draw.putIndice(numPos + 3);

        }

        // Position
        if (customFloatAttributesSize == 0) {
            if (textureSlot != -1) {
                batchQuadVertices(false, true);
            }
            else {
                batchQuadVertices(false, false);
            }
        }
        else {
            if (textureSlot != -1) {
                batchQuadVertices(true, true);
            }
            else {
                batchQuadVertices(true, false);
            }
        }

        // Colors
        //
        var r:Float;
        var g:Float;
        var b:Float;
        var a:Float;

        if (stencilClip) {
            a = 1;
            r = 1;
            g = 0;
            b = 0;
        }
        else if (quadDrawsRenderTexture || lastComputedBlending == ceramic.Blending.ALPHA) {
            a = quad.computedAlpha;
            r = quad.color.redFloat;
            g = quad.color.greenFloat;
            b = quad.color.blueFloat;
            if (quad.blending == ceramic.Blending.ADD && lastComputedBlending != ceramic.Blending.ADD) a = 0;
        }
        else {
            a = quad.computedAlpha;
            r = quad.color.redFloat * a;
            g = quad.color.greenFloat * a;
            b = quad.color.blueFloat * a;
            if (quad.blending == ceramic.Blending.ADD && lastComputedBlending != ceramic.Blending.ADD) a = 0;
        }

        var i = 0;
        while (i < 4) {
            draw.putColor(r, g, b, a);
            i++;
        }

        var uvX:Float = 0;
        var uvY:Float = 0;
        var uvW:Float = 0;
        var uvH:Float = 0;

        if (quad.texture != null) {

            var texWidthActual = this.texWidthActual;
            var texHeightActual = this.texHeightActual;
            var texDensity = quad.texture.density;

            // UV
            //
            uvX = (quad.frameX * texDensity) / texWidthActual;
            uvY = (quad.frameY * texDensity) / texHeightActual;
            uvW = (quad.frameWidth * texDensity) / texWidthActual;
            uvH = (quad.frameHeight * texDensity) / texHeightActual;

            //tl
            draw.putUVs(uvX, uvY);
            //tr
            draw.putUVs(uvX + uvW, uvY);
            //br
            draw.putUVs(uvX + uvW, uvY + uvH);
            //bl
            draw.putUVs(uvX, uvY + uvH);

        } else {
            draw.putUVs(0, 0);
            draw.putUVs(0, 0);
            draw.putUVs(0, 0);
            draw.putUVs(0, 0);
        }

        // Let backend know we did finish sending quad data
        draw.endDrawQuad();

        // Increase counts
        this.z = z + 0.001;

    }

#if !ceramic_no_mesh
    #if (!ceramic_debug_draw && !ceramic_soft_inline) inline #end function drawMesh(draw:backend.Draw, mesh:ceramic.Mesh):Void {

    #if ceramic_debug_draw
        drawnMeshes++;
    #end
        // The following code is doing pretty much the same thing as quads, but for meshes.
        // We could try to refactor to prevent redundancy but this is not required as our
        // main concern here is raw performance and anyway this code won't be updated often.

        inline function flushAndCleanState() {

            flush(draw);
            unbindUsedTextures(draw);

            // Update texture
            lastTexture = mesh.texture;
            useFirstTextureInBatch(draw, lastTexture);

    #if ceramic_debug_rendering_option
            lastDebugRendering = mesh.debugRendering;
            draw.setRenderWireframe(lastDebugRendering == ceramic.DebugRendering.WIREFRAME);
    #end

            // Update render target
            if (mesh.computedRenderTarget != lastRenderTarget) {
                lastRenderTarget = mesh.computedRenderTarget;
                useRenderTarget(draw, lastRenderTarget);
            }

            // Update shader
            lastShader = mesh.shader;
            useShader(draw, lastShader != null ? lastShader.backendItem : null);

            // Update blending
            lastComputedBlending = computeMeshBlending(mesh);
            useBlending(draw, lastComputedBlending);

            stateDirty = false;

        }

        if (stencilClip) {
            // Special case of drawing into stencil buffer

            // No texture
            unbindUsedTextures(draw);
            useFirstTextureInBatch(draw, null);

            // Default blending
            draw.setBlendFuncSeparate(
                backend.BlendMode.ONE,
                backend.BlendMode.ONE_MINUS_SRC_ALPHA,
                backend.BlendMode.ONE,
                backend.BlendMode.ONE_MINUS_SRC_ALPHA
            );
            lastComputedBlending = ceramic.Blending.PREMULTIPLIED_ALPHA;

            // No render target when writing to stencil buffer
            lastRenderTarget = quad.computedRenderTarget;
            useRenderTarget(draw, lastRenderTarget);

            // Use default shader
            lastShader = null;
            useShader(draw, null);

            stateDirty = false;
        }
        else {
            // Check if state is dirty
            var textureToUseInSameBatch = null;
            if (!stateDirty) {
                var newComputedBlending = computeMeshBlending(mesh);
                stateDirty =
                    !isSameShader(mesh.shader, lastShader) ||
                    newComputedBlending != lastComputedBlending ||
    #if ceramic_debug_rendering_option
                    mesh.debugRendering != lastDebugRendering ||
    #end
                    mesh.computedRenderTarget != lastRenderTarget;
    #if ceramic_debug_draw_flush_reason
                if (debugDraw && stateDirty) {
                    if (!isSameShader(mesh.shader, lastShader))
                        log.debug('- dirty: shader');
                    if (newComputedBlending != lastComputedBlending)
                        log.debug('- dirty: blending $lastComputedBlending -> $newComputedBlending');
                    if (mesh.computedRenderTarget != lastRenderTarget)
                        log.debug('- dirty: render target');
                }
    #end
                if (!stateDirty) {
                    if (mesh.texture != lastTexture) {
                        if (mesh.texture != null && lastTexture != null) {
                            // Different ceramic textures could use the same backend texture
                            if (!draw.textureBackendItemMatchesId(mesh.texture.backendItem, lastTextureId)) {
                                // We could use multiple texture in same batch
                                if (!canUseTextureInSameBatch(draw, mesh.texture)) {
    #if ceramic_debug_draw_flush_reason
                                    if (debugDraw) {
                                        log.debug('- dirty: texture not matching');
                                    }
    #end
                                    stateDirty = true;
                                }
                                else {
                                    textureToUseInSameBatch = mesh.texture;
                                }
                            }
                        } else {
                            // We could use multiple texture in same batch
                            if (!canUseTextureInSameBatch(draw, mesh.texture)) {
    #if ceramic_debug_draw_flush_reason
                                if (debugDraw) {
                                    log.debug('- dirty: texture not matching');
                                }
    #end
                                stateDirty = true;
                            }
                            else {
                                textureToUseInSameBatch = mesh.texture != null ? mesh.texture : defaultWhiteTexture;
                            }
                        }
                    }
                }
            }

            if (stateDirty) {
                flushAndCleanState();
            }
            else {
                if (textureToUseInSameBatch != null) {
                    useTextureInSameBatch(draw, textureToUseInSameBatch);
                }
            }
        }

        // Fetch matrix
        //
        var matA:Float = mesh.matA;
        var matB:Float = mesh.matB;
        var matC:Float = mesh.matC;
        var matD:Float = mesh.matD;
        var matTX:Float = mesh.matTX;
        var matTY:Float = mesh.matTY;
        var z:Float = this.z;
        var textureSlot:Float = activeShaderCanBatchMultipleTextures ? activeTextureSlot : -1;

    #if ceramic_debug_draw
        if (debugDraw && #if ceramic_debug_draw_all true #elseif ceramic_debug_multitexture activeShaderCanBatchMultipleTextures #else mesh.id != null #end) {
            log.warning('* drawMesh(${mesh.id != null ? mesh.id : ''}) slot=$textureSlot texture=${lastTexture} stencil=$stencilClip clip=$lastClip');
        }
    #end

        // Color
        var meshColors = mesh.colors;
        var meshSingleColor = stencilClip || mesh.colorMapping == MESH;
        var meshIndicesColor = !stencilClip && mesh.colorMapping == INDICES;

        // Data
        var meshUvs = mesh.uvs;
        var meshVertices = mesh.vertices;
        var meshIndices = mesh.indices;

        // Let backend know we will start sending mesh data
        draw.beginDrawMesh(mesh); // TODO pass mesh info

    #if ceramic_debug_rendering_option
        // TODO avoid allocating an array
        if (lastDebugRendering == ceramic.DebugRendering.WIREFRAME) {
            meshIndices = [];
            var i = 0;
            while (i < mesh.indices.length) {
                meshIndices.push(mesh.indices[i]);
                meshIndices.push(mesh.indices[i+1]);
                meshIndices.push(mesh.indices[i+1]);
                meshIndices.push(mesh.indices[i+2]);
                meshIndices.push(mesh.indices[i+2]);
                meshIndices.push(mesh.indices[i]);
                i += 3;
            }
            meshSingleColor = true;
        }
    #end

        // Update num vertices
        var visualNumVertices = meshIndices.length;
        //var posFloats = this.posFloats;
        //var uvFloats = this.uvFloats;
        //var posList = draw.getPosList();
        var customFloatAttributesSize = this.customFloatAttributesSize;
        var meshCustomFloatAttributesSize = mesh.customFloatAttributesSize;
        //var floatsPerVertex = (4 + customFloatAttributesSize);
        //var posFloatsAdd = visualNumVertices * floatsPerVertex;
        //var posFloatsAfter = posFloats + posFloatsAdd;
        //var uvFloatsAfter = uvFloats + visualNumVertices * 4;
        var startVertices = 0;
        var meshDrawsRenderTexture:Bool = mesh.texture != null && mesh.texture.isRenderTexture;
        var endVertices = visualNumVertices;
        // Divide and multiply by 3 (a triangle has 3 vertices, we want to split between 2 triangles)
        //var maxVertices = Std.int((maxVertFloats / floatsPerVertex) / 3) * 3;

        // Submit the current batch if we exceed the max buffer size
        if (draw.shouldFlush(visualNumVertices, visualNumVertices, customFloatAttributesSize)) {//posFloatsAfter > maxVertFloats || uvFloatsAfter > maxVertFloats) {
            flushAndCleanState();
            textureSlot = activeShaderCanBatchMultipleTextures ? activeTextureSlot : -1;

            // Check that our mesh is still not too large
            if (visualNumVertices > draw.remainingVertices() || visualNumVertices > draw.remainingIndices()) {
                endVertices = Std.int(Math.min(draw.remainingVertices(), draw.remainingIndices()));
                endVertices = Std.int(endVertices / 3) * 3;
            }
        }

        // Actual texture size may differ from its logical one.
        // Keep factor values to generate UV mapping that matches the real texture.
        var texture = mesh.texture;
        var uvFactorX:Float = 0;
        var uvFactorY:Float = 0;
        if (texture != null) {
            uvFactorX = texWidth / texWidthActual;
            uvFactorY = texHeight / texHeightActual;
        }

        //var uvList = draw.getUvList();
        //var colorList = draw.getColorList();

        inline function batchMeshVertices() {

            // We may run this code multiple times if the mesh
            // needs to be splitted into multiple draw calls.
            // That is why it is inside a `while` block
            // Exit condition is at the end.
            while (true) {
            
                //var colorFloats = this.colorFloats;

                var a:Float = 0;
                var r:Float = 0;
                var g:Float = 0;
                var b:Float = 0;

                // Single color
                //
                if (meshSingleColor) {

                    if (stencilClip) {
                        a = 1;
                        r = 1;
                        g = 0;
                        b = 0;
                    }
                    else if (meshDrawsRenderTexture || lastComputedBlending == ceramic.Blending.ALPHA) {
                        var meshAlphaColor = meshColors.unsafeGet(0);
                        a = mesh.computedAlpha * meshAlphaColor.alphaFloat;
                        r = meshAlphaColor.redFloat;
                        g = meshAlphaColor.greenFloat;
                        b = meshAlphaColor.blueFloat;
                        if (mesh.blending == ceramic.Blending.ADD && lastComputedBlending != ceramic.Blending.ADD) a = 0;
                    }
                    else {
                        var meshAlphaColor = meshColors.unsafeGet(0);
                        a = mesh.computedAlpha * meshAlphaColor.alphaFloat;
                        r = meshAlphaColor.redFloat * a;
                        g = meshAlphaColor.greenFloat * a;
                        b = meshAlphaColor.blueFloat * a;
                        if (mesh.blending == ceramic.Blending.ADD && lastComputedBlending != ceramic.Blending.ADD) a = 0;
                    }
                }

                var i = startVertices;
                var numPos = draw.getNumPos();
                while (i < endVertices) {

                    var j = meshIndices.unsafeGet(i);
                    var k = j * 2;
                    var l = j * (2 + meshCustomFloatAttributesSize);

                    // Position
                    //
                    var x = meshVertices.unsafeGet(l++);
                    var y = meshVertices.unsafeGet(l++);

                    draw.putIndice(numPos);
                    numPos++;

                    if (textureSlot != -1) {
                        draw.putPosAndTextureSlot(
                            matTX + matA * x + matC * y,
                            matTY + matB * x + matD * y,
                            z,
                            textureSlot
                        );
                    }
                    else {
                        draw.putPos(
                            matTX + matA * x + matC * y,
                            matTY + matB * x + matD * y,
                            z
                        );
                    }

                    //draw.putInPosList(posList, posFloats, 0);

                    // Color
                    //
                    if (!meshSingleColor) {
                        var meshAlphaColor:AlphaColor = meshIndicesColor ? meshColors.unsafeGet(i) : meshColors.unsafeGet(j);

                        if (meshDrawsRenderTexture || lastComputedBlending == ceramic.Blending.ALPHA) {
                            a = mesh.computedAlpha * meshAlphaColor.alphaFloat;
                            r = meshAlphaColor.redFloat;
                            g = meshAlphaColor.greenFloat;
                            b = meshAlphaColor.blueFloat;
                            if (mesh.blending == ceramic.Blending.ADD && lastComputedBlending != ceramic.Blending.ADD) a = 0;
                        }
                        else {
                            a = mesh.computedAlpha * meshAlphaColor.alphaFloat;
                            r = meshAlphaColor.redFloat * a;
                            g = meshAlphaColor.greenFloat * a;
                            b = meshAlphaColor.blueFloat * a;
                            if (mesh.blending == ceramic.Blending.ADD && lastComputedBlending != ceramic.Blending.ADD) a = 0;
                        }
                    }
                    draw.putColor(r, g, b, a);

                    // UV
                    //
                    if (texture != null) {
                        var uvX:Float = meshUvs.unsafeGet(k) * uvFactorX;
                        var uvY:Float = meshUvs.unsafeGet(k + 1) * uvFactorY;
                        draw.putUVs(uvX, uvY);
                    }
                    else {
                        draw.putUVs(0, 0);
                    }

                    // Custom (float) attributes
                    //
                    if (customFloatAttributesSize != 0) {
                        draw.beginFloatAttributes();
                        for (n in 0...customFloatAttributesSize) {
                            if (n < meshCustomFloatAttributesSize) {
                                draw.putFloatAttribute(n, meshVertices.unsafeGet(l++));
                            }
                            else {
                                draw.putFloatAttribute(n, 0.0);
                            }
                        }
                        draw.endFloatAttributes();
                    }

                    i++;
                }

                if (endVertices == visualNumVertices) {
                    // No need to submit more data, exit loop
                    break;
                }
                else {
                    
                    // There is still data left that needs to be submitted.
                    // Flush pending buffers and iterate once more.

                    flushAndCleanState();
                    textureSlot = activeShaderCanBatchMultipleTextures ? activeTextureSlot : -1;

                    startVertices = endVertices;
                    endVertices = startVertices + Std.int(Math.min(draw.remainingVertices(), draw.remainingIndices()));
                    endVertices = Std.int(endVertices / 3) * 3;
                    if (endVertices > visualNumVertices) {
                        endVertices = visualNumVertices;
                    }
                }

            }

        }

        batchMeshVertices();

        // Let backend know we did finish sending quad data
        draw.endDrawMesh();

        // Increase counts
        this.z = z + 0.001;

    }
#end

    #if (!ceramic_debug_draw && !ceramic_soft_inline) inline #end function flush(draw:backend.Draw):Bool {

        if (!draw.hasAnythingToFlush()) {
            return false;
        }

        draw.flush();
        drawCalls++;

    #if ceramic_debug_draw
        var flushingQuadsNow = drawnQuads - flushedQuads;
        var flushingMeshesNow = drawnMeshes - flushedMeshes;
        if (debugDraw) {
            log.info('flush - #$drawCalls(${flushingQuadsNow + flushingMeshesNow}) / $lastTexture / $lastShader / $lastRenderTarget / $lastComputedBlending / $lastClip');
        }
        flushedQuads = drawnQuads;
        flushedMeshes = drawnMeshes;
    #end

        return true;

    }

#else
    public var maxVerts:Int = 16384;

    var posFloats:Int = 0;
    var uvFloats:Int = 0;
    var colorFloats:Int = 0;

    var drawCalls:Int = 0;

    var activeShader:backend.Shader = null;
    var customFloatAttributesSize:Int = 0;

    var stencilClip:Bool = false;

    var lastTexture:ceramic.Texture = null;
    var lastTextureId:backend.TextureId = backend.TextureId.DEFAULT;
    var lastShader:ceramic.Shader = null;
    var lastRenderTarget:ceramic.RenderTexture = null;
    var lastComputedBlending:ceramic.Blending = ceramic.Blending.PREMULTIPLIED_ALPHA;
    var lastClip:ceramic.Visual = null;
    var activeTextureSlot:Int = 0;

    var backendTextures:backend.Textures;
    var backendShaders:backend.Shaders;

    var texWidth:Int = 0;
    var texHeight:Int = 0;
    var texWidthActual:Int = 0;
    var texHeightActual:Int = 0;

    //var defaultPlainShader:backend.Shader = null;
    var defaultTexturedShader:backend.Shader = null;
    var defaultWhiteTexture:ceramic.Texture = null;

    var maxVertFloats:Int = 0;

    var quad:ceramic.Quad = null;
    var mesh:ceramic.Mesh = null;

    var stateDirty:Bool = true;

    var z:Float = 0;

    var usedTextureIndexes:Array<Int> = [];
    var usedTextures:Int = 0;
    var maxUsableTexturesInBatch:Int = -1;
    var activeShaderCanBatchMultipleTextures:Bool = false;

    #if ceramic_debug_draw
    var lastDebugTime:Float = -1;
    var debugDraw:Bool = false;
    var drawnQuads:Int = 0;
    var drawnMeshes:Int = 0;
    var flushedQuads:Int = 0;
    var flushedMeshes:Int = 0;
    #end

    #if ceramic_debug_rendering_option
    var lastDebugRendering = ceramic.DebugRendering.DEFAULT;
    #end

    public function new() {

        super();

    }

    public function render(isMainRender:Bool, ceramicVisuals:Array<Visual>):Void {

        var draw = app.backend.draw;
        backendTextures = app.backend.textures;
        backendShaders = app.backend.shaders;

        //defaultPlainShader = ceramic.App.app.defaultColorShader.backendItem;
        defaultTexturedShader = ceramic.App.app.defaultTexturedShader.backendItem;
        defaultWhiteTexture = ceramic.App.app.defaultWhiteTexture;
        
        maxUsableTexturesInBatch = Std.int(Math.min(
            backendTextures.maxTexturesByBatch(),
            backendShaders.maxIfStatementsByFragmentShader()
        ));
        
        while (usedTextureIndexes.length < maxUsableTexturesInBatch) {
            usedTextureIndexes.push(0);
        }

        #if ceramic_avoid_last_texture_slot
        if (maxUsableTexturesInBatch > 1) {
            // On some devices, we have problems if we use the last texture slot.
            // As a workaround, we avoid using it. I wish I could understand why.
            // That's sad. Very sad.
            maxUsableTexturesInBatch--;
        }
        #end

    #if ceramic_debug_draw
        if (isMainRender) {
            if (ceramic.Timer.now - lastDebugTime > 10) {
                debugDraw = true;
                lastDebugTime = ceramic.Timer.now;
            } else {
                debugDraw = false;
            }
            drawnQuads = 0;
            drawnMeshes = 0;
            flushedQuads = 0;
            flushedMeshes = 0;
        } else {
            debugDraw = false;
        }
    #end

        posFloats = 0;
        uvFloats = 0;
        colorFloats = 0;

        drawCalls = 0;

        maxVertFloats = maxVerts * 4;
        draw.initBuffers(maxVerts);

        quad = null;
        mesh = null;

        lastTexture = null;
        lastTextureId = backend.TextureId.DEFAULT;
        lastShader = null;
        lastRenderTarget = null;
        lastComputedBlending = ceramic.Blending.PREMULTIPLIED_ALPHA;
    #if ceramic_debug_rendering_option
        lastDebugRendering = ceramic.DebugRendering.DEFAULT;
    #end
        lastClip = null;
        usedTextures = 0;

        texWidth = 0;
        texHeight = 0;
        texWidthActual = 0;
        texHeightActual = 0;

        stencilClip = false;
        z = 0;
        stateDirty = true;

        //var defaultPlainShader:backend.Shader = ceramic.App.app.defaultColorShader.backendItem;
        var defaultTexturedShader:backend.Shader = ceramic.App.app.defaultTexturedShader.backendItem;

        // Mark auto-rendering render textures as dirty
        var allRenderTextures = ceramic.App.app.renderTextures;
        for (ii in 0...allRenderTextures.length) {
            var renderTexture = allRenderTextures.unsafeGet(ii);
            if (renderTexture.autoRender) {
                renderTexture.renderDirty = true;
            }
        }

        draw.beginRender();

        // Initialize default state
        draw.setActiveTexture(0);
        activeTextureSlot = 0;
        draw.setRenderTarget(null, true);
        draw.enableBlending();
        activeShader = null;
        lastShader = null;
        useShader(draw, null);

        // Default blending
        draw.setBlendFuncSeparate(
            backend.BlendMode.ONE,
            backend.BlendMode.ONE_MINUS_SRC_ALPHA,
            backend.BlendMode.ONE,
            backend.BlendMode.ONE_MINUS_SRC_ALPHA
        );
        lastComputedBlending = ceramic.Blending.PREMULTIPLIED_ALPHA;

        // Default stencil test
        draw.drawWithoutStencilTest();

        // For each ceramic visual in the list
        //
        if (ceramicVisuals != null) {

            for (ii in 0...ceramicVisuals.length) {
                var visual = ceramicVisuals.unsafeGet(ii);
                var quad = visual.asQuad;
                var mesh = visual.asMesh;

                // If it's valid to be drawn
                if (visual.computedVisible) {

                    // If it should be redrawn anyway
                    if (visual.computedRenderTarget == null || visual.computedRenderTarget.renderDirty) {

                        var clip:ceramic.Visual;
                        #if !ceramic_no_clip
                        if (visual.computedClip) {
                            // Get new clip and compare with last
                            var clippingVisual = visual;
                            while (clippingVisual != null && clippingVisual.clip == null) {
                                clippingVisual = clippingVisual.parent;
                            }
                            clip = clippingVisual != null ? clippingVisual.clip : null;

                        } else {
                        #end
                            clip = null;
                        #if !ceramic_no_clip
                        }
                        #end

                        if (clip != lastClip) {

                            flush(draw);
                            unbindUsedTextures(draw);
                            stateDirty = true;

                            if (lastClip != null) {
                                lastRenderTarget = lastClip.computedRenderTarget;
                                useRenderTarget(draw, lastRenderTarget);

                                // Finish clipping
                                draw.drawWithoutStencilTest();
                            }

                            lastClip = clip;

                            if (lastClip != null) {
                                // Update stencil buffer
                                
                                lastRenderTarget = lastClip.computedRenderTarget;
                                useRenderTarget(draw, lastRenderTarget);

                                draw.beginDrawingInStencilBuffer();

                                if (lastClip.asQuad != null) {
                                    quad = lastClip.asQuad;
                                    stencilClip = true;
                                    drawQuad(draw, quad);
                                    stencilClip = false;
                                    quad = visual.asQuad;
                                }
                                else if (lastClip.asMesh != null) {
                                    mesh = lastClip.asMesh;
                                    stencilClip = true;
                                    drawMesh(draw, mesh);
                                    stencilClip = false;
                                    mesh = visual.asMesh;
                                }

                                // Next things to be drawn will be clipped
                                flush(draw);
                                unbindUsedTextures(draw);
                                stateDirty = true;

                                draw.endDrawingInStencilBuffer();
                                draw.drawWithStencilTest();
                            }
                        }

                        if (quad != null && !quad.transparent) {

                            drawQuad(draw, quad);

                        }

                        else if (mesh != null) {

                            drawMesh(draw, mesh);

                        }
                    }
                }
            }

            flush(draw);
            unbindUsedTextures(draw);
            stateDirty = true;
        }

    #if ceramic_debug_draw
        if (debugDraw) {
            log.success(' -- $drawCalls draw call' + (drawCalls > 1 ? 's' : '') + ' / $drawnQuads quad' + (drawnQuads > 1 ? 's' : '') + ' / $drawnMeshes mesh' + (drawnMeshes > 1 ? 'es' : '') + '');
        }
    #end

    }

    #if (!ceramic_debug_draw && !ceramic_soft_inline) inline #end function flushAndCleanQuadState(draw:backend.Draw, quad:ceramic.Quad) {

        flush(draw);
        unbindUsedTextures(draw);

        // Update texture
        lastTexture = quad.texture;
        useFirstTextureInBatch(draw, lastTexture);

#if ceramic_debug_rendering_option
        lastDebugRendering = quad.debugRendering;
        draw.setRenderWireframe(lastDebugRendering == ceramic.DebugRendering.WIREFRAME);
#end

        // Update render target
        if (quad.computedRenderTarget != lastRenderTarget) {
            lastRenderTarget = quad.computedRenderTarget;
            useRenderTarget(draw, lastRenderTarget);
        }

        // Update shader
        lastShader = quad.shader;
        useShader(draw, lastShader != null ? lastShader.backendItem : null);

        // Update blending
        lastComputedBlending = computeQuadBlending(quad);
        useBlending(draw, lastComputedBlending);

        stateDirty = false;

    }

    #if (!ceramic_debug_draw && !ceramic_soft_inline) inline #end function drawQuad(draw:backend.Draw, quad:ceramic.Quad):Void {

    #if ceramic_debug_draw
        drawnQuads++;
    #end

        if (stencilClip) {
            // Special case of drawing into stencil buffer

            // No texture
            unbindUsedTextures(draw);
            useFirstTextureInBatch(draw, null);

            // Default blending
            draw.setBlendFuncSeparate(
                backend.BlendMode.ONE,
                backend.BlendMode.ONE_MINUS_SRC_ALPHA,
                backend.BlendMode.ONE,
                backend.BlendMode.ONE_MINUS_SRC_ALPHA
            );
            lastComputedBlending = ceramic.Blending.PREMULTIPLIED_ALPHA;

            // No render target when writing to stencil buffer
            lastRenderTarget = quad.computedRenderTarget;
            useRenderTarget(draw, lastRenderTarget);

            // Use default shader
            lastShader = null;
            useShader(draw, null);

            stateDirty = false;
        }
        else {
            // Check if state is dirty
            var textureToUseInSameBatch = null;
            if (!stateDirty) {
                var newComputedBlending = computeQuadBlending(quad);
                stateDirty =
                    !isSameShader(quad.shader, lastShader) ||
                    newComputedBlending != lastComputedBlending ||
    #if ceramic_debug_rendering_option
                    quad.debugRendering != lastDebugRendering ||
    #end
                    quad.computedRenderTarget != lastRenderTarget;
    #if ceramic_debug_draw_flush_reason
                if (debugDraw && stateDirty) {
                    if (!isSameShader(quad.shader, lastShader))
                        log.debug('- dirty: shader');
                    if (newComputedBlending != lastComputedBlending)
                        log.debug('- dirty: blending $lastComputedBlending -> $newComputedBlending');
                    if (quad.computedRenderTarget != lastRenderTarget)
                        log.debug('- dirty: render target');
                }
    #end
                if (!stateDirty) {
                    if (quad.texture != lastTexture) {
                        if (quad.texture != null && lastTexture != null) {
                            // Different ceramic textures could use the same backend texture
                            if (!draw.textureBackendItemMatchesId(quad.texture.backendItem, lastTextureId)) {
                                // We could use multiple texture in same batch
                                if (!canUseTextureInSameBatch(draw, quad.texture)) {
                                    stateDirty = true;
                                }
                                else {
                                    textureToUseInSameBatch = quad.texture;
                                }
                            }
                        } else {
                            // We could use multiple texture in same batch
                            if (!canUseTextureInSameBatch(draw, quad.texture)) {
                                stateDirty = true;
                            }
                            else {
                                textureToUseInSameBatch = quad.texture != null ? quad.texture : defaultWhiteTexture;
                            }
                        }
                    }
    #if ceramic_debug_draw_flush_reason
                    if (debugDraw && stateDirty) {
                        log.debug('- dirty: texture not matching');
                    }
    #end
                }
            }

            if (stateDirty) {
                flushAndCleanQuadState(draw, quad);
            }
            else {
                if (textureToUseInSameBatch != null) {
                    useTextureInSameBatch(draw, textureToUseInSameBatch);
                }
            }
        }

        // Update num vertices
        var posFloats = this.posFloats;
        var uvFloats = this.uvFloats;
        var customFloatAttributesSize = this.customFloatAttributesSize;
        var visualNumVertices = 6;
        var posFloatsAfter = posFloats + visualNumVertices * (4 + customFloatAttributesSize);
        var uvFloatsAfter = uvFloats + visualNumVertices * 4;

        // Submit the current batch if we exceed the max buffer size
        if (posFloatsAfter > maxVertFloats || uvFloatsAfter > maxVertFloats) {
            flushAndCleanQuadState(draw, quad);
            posFloats = this.posFloats;
            uvFloats = this.uvFloats;
        }

        // Update size
        var w:Float = quad.width;
        var h:Float = quad.height;

        // Fetch matrix
        //
        var matA:Float = quad.matA;
        var matB:Float = quad.matB;
        var matC:Float = quad.matC;
        var matD:Float = quad.matD;
        var matTX:Float = quad.matTX;
        var matTY:Float = quad.matTY;
        var z:Float = this.z;
        var posList = draw.getPosList();
        var textureSlot:Float = activeShaderCanBatchMultipleTextures ? activeTextureSlot : -1;
        var quadDrawsRenderTexture:Bool = quad.texture != null && quad.texture.isRenderTexture;

    #if ceramic_debug_draw
        if (debugDraw && #if ceramic_debug_draw_all true #elseif ceramic_debug_multitexture activeShaderCanBatchMultipleTextures #else quad.id != null #end) {
            log.warning('* drawQuad(${quad.id != null ? quad.id : ''}) slot=$textureSlot texture=${lastTexture} stencil=$stencilClip clip=$lastClip');
        }
    #end

        // Let backend know we will start sending quad data
        draw.beginDrawQuad(quad);

        /** Using an inline internal function because we want to use similar code multiple times,
            and let haxe compiler evaluate `hasCustomAttributes` and `hasTextureSlot`
            at compile time. */
        inline function batchQuadVertices(hasCustomAttributes:Bool, hasTextureSlot:Bool) {

            //tl
            draw.putInPosList(posList, posFloats, matTX);
            posFloats++;
            draw.putInPosList(posList, posFloats, matTY);
            posFloats++;
            draw.putInPosList(posList, posFloats, z);
            posFloats++;
            if (hasTextureSlot) {
                draw.putInPosList(posList, posFloats, textureSlot);
                posFloats++;
            }
            if (hasCustomAttributes) {
                for (l in 0...customFloatAttributesSize) {
                    draw.putInPosList(posList, posFloats, 0.0);
                    posFloats++;
                }
            }

            //tr
            draw.putInPosList(posList, posFloats, matTX + matA * w);
            posFloats++;
            draw.putInPosList(posList, posFloats, matTY + matB * w);
            posFloats++;
            draw.putInPosList(posList, posFloats, z);
            posFloats++;
            if (hasTextureSlot) {
                draw.putInPosList(posList, posFloats, textureSlot);
                posFloats++;
            }
            if (hasCustomAttributes) {
                for (l in 0...customFloatAttributesSize) {
                    draw.putInPosList(posList, posFloats, 0.0);
                    posFloats++;
                }
            }

            //br
            var n8 = matTX + matA * w + matC * h;
            var n9 = matTY + matB * w + matD * h;

            draw.putInPosList(posList, posFloats, n8);
            posFloats++;
            draw.putInPosList(posList, posFloats, n9);
            posFloats++;
            draw.putInPosList(posList, posFloats, z);
            posFloats++;
            if (hasTextureSlot) {
                draw.putInPosList(posList, posFloats, textureSlot);
                posFloats++;
            }
            if (hasCustomAttributes) {
                for (l in 0...customFloatAttributesSize) {
                    draw.putInPosList(posList, posFloats, 0.0);
                    posFloats++;
                }
            }

            //bl
            draw.putInPosList(posList, posFloats, matTX + matC * h);
            posFloats++;
            draw.putInPosList(posList, posFloats, matTY + matD * h);
            posFloats++;
            draw.putInPosList(posList, posFloats, z);
            posFloats++;
            if (hasTextureSlot) {
                draw.putInPosList(posList, posFloats, textureSlot);
                posFloats++;
            }
            if (hasCustomAttributes) {
                for (l in 0...customFloatAttributesSize) {
                    draw.putInPosList(posList, posFloats, 0.0);
                    posFloats++;
                }
            }

            //tl2
            draw.putInPosList(posList, posFloats, matTX);
            posFloats++;
            draw.putInPosList(posList, posFloats, matTY);
            posFloats++;
            draw.putInPosList(posList, posFloats, z);
            posFloats++;
            if (hasTextureSlot) {
                draw.putInPosList(posList, posFloats, textureSlot);
                posFloats++;
            }
            if (hasCustomAttributes) {
                for (l in 0...customFloatAttributesSize) {
                    draw.putInPosList(posList, posFloats, 0.0);
                    posFloats++;
                }
            }

            //br2
            draw.putInPosList(posList, posFloats, n8);
            posFloats++;
            draw.putInPosList(posList, posFloats, n9);
            posFloats++;
            draw.putInPosList(posList, posFloats, z);
            posFloats++;
            if (hasTextureSlot) {
                draw.putInPosList(posList, posFloats, textureSlot);
                posFloats++;
            }
            if (hasCustomAttributes) {
                for (l in 0...customFloatAttributesSize) {
                    draw.putInPosList(posList, posFloats, 0.0);
                    posFloats++;
                }
            }

        }

        // Position
        var n = posFloats;
        if (customFloatAttributesSize == 0) {
            if (textureSlot != -1) {
                batchQuadVertices(false, true);
            }
            else {
                batchQuadVertices(false, false);
            }
        }
        else {
            if (textureSlot != -1) {
                batchQuadVertices(true, true);
            }
            else {
                batchQuadVertices(true, false);
            }
        }

        this.posFloats = posFloats;

        var uvX:Float = 0;
        var uvY:Float = 0;
        var uvW:Float = 0;
        var uvH:Float = 0;

        if (quad.texture != null) {

            var texWidthActual = this.texWidthActual;
            var texHeightActual = this.texHeightActual;
            var texDensity = quad.texture.density;

            // UV
            //
            uvX = (quad.frameX * texDensity) / texWidthActual;
            uvY = (quad.frameY * texDensity) / texHeightActual;
            uvW = (quad.frameWidth * texDensity) / texWidthActual;
            uvH = (quad.frameHeight * texDensity) / texHeightActual;

            var uvList = draw.getUvList();

            //tl
            draw.putInUvList(uvList, uvFloats, uvX);
            uvFloats++;
            draw.putInUvList(uvList, uvFloats, uvY);
            uvFloats++;
            draw.putInUvList(uvList, uvFloats, 0);
            uvFloats++;
            draw.putInUvList(uvList, uvFloats, 0);
            uvFloats++;
            //tr
            draw.putInUvList(uvList, uvFloats, uvX + uvW);
            uvFloats++;
            draw.putInUvList(uvList, uvFloats, uvY);
            uvFloats++;
            draw.putInUvList(uvList, uvFloats, 0);
            uvFloats++;
            draw.putInUvList(uvList, uvFloats, 0);
            uvFloats++;
            //br
            draw.putInUvList(uvList, uvFloats, uvX + uvW);
            uvFloats++;
            draw.putInUvList(uvList, uvFloats, uvY + uvH);
            uvFloats++;
            draw.putInUvList(uvList, uvFloats, 0);
            uvFloats++;
            draw.putInUvList(uvList, uvFloats, 0);
            uvFloats++;
            //bl
            draw.putInUvList(uvList, uvFloats, uvX);
            uvFloats++;
            draw.putInUvList(uvList, uvFloats, uvY + uvH);
            uvFloats++;
            draw.putInUvList(uvList, uvFloats, 0);
            uvFloats++;
            draw.putInUvList(uvList, uvFloats, 0);
            uvFloats++;
            //tl2
            draw.putInUvList(uvList, uvFloats, uvX);
            uvFloats++;
            draw.putInUvList(uvList, uvFloats, uvY);
            uvFloats++;
            draw.putInUvList(uvList, uvFloats, 0);
            uvFloats++;
            draw.putInUvList(uvList, uvFloats, 0);
            uvFloats++;
            //br2
            draw.putInUvList(uvList, uvFloats, uvX + uvW);
            uvFloats++;
            draw.putInUvList(uvList, uvFloats, uvY + uvH);
            uvFloats++;
            draw.putInUvList(uvList, uvFloats, 0);
            uvFloats++;
            draw.putInUvList(uvList, uvFloats, 0);
            uvFloats++;

        } else {
            var uvList = draw.getUvList();
            var i = 0;
            while (i++ < 24) {
                draw.putInUvList(uvList, uvFloats, 0);
                uvFloats++;
            }
        }

        this.uvFloats = uvFloats;

        // Colors
        //
        var r:Float;
        var g:Float;
        var b:Float;
        var a:Float;

        if (stencilClip) {
            a = 1;
            r = 1;
            g = 0;
            b = 0;
        }
        else if (quadDrawsRenderTexture || lastComputedBlending == ceramic.Blending.ALPHA) {
            a = quad.computedAlpha;
            r = quad.color.redFloat;
            g = quad.color.greenFloat;
            b = quad.color.blueFloat;
            if (quad.blending == ceramic.Blending.ADD && lastComputedBlending != ceramic.Blending.ADD) a = 0;
        }
        else {
            a = quad.computedAlpha;
            r = quad.color.redFloat * a;
            g = quad.color.greenFloat * a;
            b = quad.color.blueFloat * a;
            if (quad.blending == ceramic.Blending.ADD && lastComputedBlending != ceramic.Blending.ADD) a = 0;
        }

        var colorFloats = this.colorFloats; 
        var colorList = draw.getColorList();

        var i = 0;
        while (i < 24) {
            draw.putInColorList(colorList, colorFloats, r);
            colorFloats++;
            draw.putInColorList(colorList, colorFloats, g);
            colorFloats++;
            draw.putInColorList(colorList, colorFloats, b);
            colorFloats++;
            draw.putInColorList(colorList, colorFloats, a);
            colorFloats++;
            i += 4;
        }

        this.colorFloats = colorFloats;

        // Let backend know we did finish sending quad data
        draw.endDrawQuad();

        // Increase counts
        this.z = z + 0.001;

    }

    #if (!ceramic_debug_draw && !ceramic_soft_inline) inline #end function flushAndCleanMeshState(draw:backend.Draw, mesh:ceramic.Mesh) {

        flush(draw);
        unbindUsedTextures(draw);

        // Update texture
        lastTexture = mesh.texture;
        useFirstTextureInBatch(draw, lastTexture);

#if ceramic_debug_rendering_option
        lastDebugRendering = mesh.debugRendering;
        draw.setRenderWireframe(lastDebugRendering == ceramic.DebugRendering.WIREFRAME);
#end

        // Update render target
        if (mesh.computedRenderTarget != lastRenderTarget) {
            lastRenderTarget = mesh.computedRenderTarget;
            useRenderTarget(draw, lastRenderTarget);
        }

        // Update shader
        lastShader = mesh.shader;
        useShader(draw, lastShader != null ? lastShader.backendItem : null);

        // Update blending
        lastComputedBlending = computeMeshBlending(mesh);
        useBlending(draw, lastComputedBlending);

        stateDirty = false;

    }

    #if (!ceramic_debug_draw && !ceramic_soft_inline) inline #end function drawMesh(draw:backend.Draw, mesh:ceramic.Mesh):Void {

    #if ceramic_debug_draw
        drawnMeshes++;
    #end
        // The following code is doing pretty much the same thing as quads, but for meshes.
        // We could try to refactor to prevent redundancy but this is not required as our
        // main concern here is raw performance and anyway this code won't be updated often.

        if (stencilClip) {
            // Special case of drawing into stencil buffer

            // No texture
            unbindUsedTextures(draw);
            useFirstTextureInBatch(draw, null);

            // Default blending
            draw.setBlendFuncSeparate(
                backend.BlendMode.ONE,
                backend.BlendMode.ONE_MINUS_SRC_ALPHA,
                backend.BlendMode.ONE,
                backend.BlendMode.ONE_MINUS_SRC_ALPHA
            );
            lastComputedBlending = ceramic.Blending.PREMULTIPLIED_ALPHA;

            // No render target when writing to stencil buffer
            lastRenderTarget = quad.computedRenderTarget;
            useRenderTarget(draw, lastRenderTarget);

            // Use default shader
            lastShader = null;
            useShader(draw, null);

            stateDirty = false;
        }
        else {
            // Check if state is dirty
            var textureToUseInSameBatch = null;
            if (!stateDirty) {
                var newComputedBlending = computeMeshBlending(mesh);
                stateDirty =
                    !isSameShader(mesh.shader, lastShader) ||
                    newComputedBlending != lastComputedBlending ||
    #if ceramic_debug_rendering_option
                    mesh.debugRendering != lastDebugRendering ||
    #end
                    mesh.computedRenderTarget != lastRenderTarget;
    #if ceramic_debug_draw_flush_reason
                if (debugDraw && stateDirty) {
                    if (!isSameShader(mesh.shader, lastShader))
                        log.debug('- dirty: shader');
                    if (newComputedBlending != lastComputedBlending)
                        log.debug('- dirty: blending $lastComputedBlending -> $newComputedBlending');
                    if (mesh.computedRenderTarget != lastRenderTarget)
                        log.debug('- dirty: render target');
                }
    #end
                if (!stateDirty) {
                    if (mesh.texture != lastTexture) {
                        if (mesh.texture != null && lastTexture != null) {
                            // Different ceramic textures could use the same backend texture
                            if (!draw.textureBackendItemMatchesId(mesh.texture.backendItem, lastTextureId)) {
                                // We could use multiple texture in same batch
                                if (!canUseTextureInSameBatch(draw, mesh.texture)) {
                                    stateDirty = true;
                                }
                                else {
                                    textureToUseInSameBatch = mesh.texture;
                                }
                            }
                        } else {
                            // We could use multiple texture in same batch
                            if (!canUseTextureInSameBatch(draw, mesh.texture)) {
                                stateDirty = true;
                            }
                            else {
                                textureToUseInSameBatch = mesh.texture != null ? mesh.texture : defaultWhiteTexture;
                            }
                        }
                    }
    #if ceramic_debug_draw_flush_reason
                    if (debugDraw && stateDirty) {
                        log.debug('- dirty: texture not matching');
                    }
    #end
                }
            }

            if (stateDirty) {
                flushAndCleanMeshState(draw, mesh);
            }
            else {
                if (textureToUseInSameBatch != null) {
                    useTextureInSameBatch(draw, textureToUseInSameBatch);
                }
            }
        }

        // Fetch matrix
        //
        var matA:Float = mesh.matA;
        var matB:Float = mesh.matB;
        var matC:Float = mesh.matC;
        var matD:Float = mesh.matD;
        var matTX:Float = mesh.matTX;
        var matTY:Float = mesh.matTY;
        var z:Float = this.z;
        var textureSlot:Float = activeShaderCanBatchMultipleTextures ? activeTextureSlot : -1;

    #if ceramic_debug_draw
        if (debugDraw && #if ceramic_debug_draw_all true #elseif ceramic_debug_multitexture activeShaderCanBatchMultipleTextures #else mesh.id != null #end) {
            log.warning('* drawMesh(${mesh.id != null ? mesh.id : ''}) slot=$textureSlot texture=${lastTexture} stencil=$stencilClip clip=$lastClip');
        }
    #end

        // Color
        var meshColors = mesh.colors;
        var meshSingleColor = stencilClip || mesh.colorMapping == MESH;
        var meshIndicesColor = !stencilClip && mesh.colorMapping == INDICES;

        // Data
        var meshUvs = mesh.uvs;
        var meshVertices = mesh.vertices;
        var meshIndices = mesh.indices;

        // Let backend know we will start sending mesh data
        draw.beginDrawMesh(mesh); // TODO pass mesh info

    #if ceramic_debug_rendering_option
        // TODO avoid allocating an array
        if (lastDebugRendering == ceramic.DebugRendering.WIREFRAME) {
            meshIndices = [];
            var i = 0;
            while (i < mesh.indices.length) {
                meshIndices.push(mesh.indices[i]);
                meshIndices.push(mesh.indices[i+1]);
                meshIndices.push(mesh.indices[i+1]);
                meshIndices.push(mesh.indices[i+2]);
                meshIndices.push(mesh.indices[i+2]);
                meshIndices.push(mesh.indices[i]);
                i += 3;
            }
            meshSingleColor = true;
        }
    #end

        // Update num vertices
        var visualNumVertices = meshIndices.length;
        var posFloats = this.posFloats;
        var uvFloats = this.uvFloats;
        var posList = draw.getPosList();
        var customFloatAttributesSize = this.customFloatAttributesSize;
        var meshCustomFloatAttributesSize = mesh.customFloatAttributesSize;
        var floatsPerVertex = (4 + customFloatAttributesSize);
        var posFloatsAdd = visualNumVertices * floatsPerVertex;
        var posFloatsAfter = posFloats + posFloatsAdd;
        var uvFloatsAfter = uvFloats + visualNumVertices * 4;
        var startVertices = 0;
        var meshDrawsRenderTexture:Bool = mesh.texture != null && mesh.texture.isRenderTexture;
        var endVertices = visualNumVertices;
        // Divide and multiply by 3 (a triangle has 3 vertices, we want to split between 2 triangles)
        var maxVertices = Std.int((maxVertFloats / floatsPerVertex) / 3) * 3;

        // Submit the current batch if we exceed the max buffer size
        if (posFloatsAfter > maxVertFloats || uvFloatsAfter > maxVertFloats) {
            flushAndCleanMeshState(draw, mesh);
            textureSlot = activeShaderCanBatchMultipleTextures ? activeTextureSlot : -1;
            posFloats = this.posFloats;
            uvFloats = this.uvFloats;
            posFloatsAfter = posFloats + posFloatsAdd;
            uvFloatsAfter = uvFloats + visualNumVertices * 4;

            // Check that our mesh is still not too large
            if (posFloatsAfter > maxVertFloats || uvFloatsAfter > maxVertFloats) {
                endVertices = maxVertices;
            }
        }

        // Actual texture size may differ from its logical one.
        // Keep factor values to generate UV mapping that matches the real texture.
        var texture = mesh.texture;
        var uvFactorX:Float = 0;
        var uvFactorY:Float = 0;
        if (texture != null) {
            uvFactorX = texWidth / texWidthActual;
            uvFactorY = texHeight / texHeightActual;
        }

        var uvList = draw.getUvList();
        var colorList = draw.getColorList();

        inline function batchMeshVertices() {

            // We may run this code multiple times if the mesh
            // needs to be splitted into multiple draw calls.
            // That is why it is inside a `while` block
            // Exit condition is at the end.
            while (true) {
            
                var colorFloats = this.colorFloats;

                var i = startVertices;
                while (i < endVertices) {

                    var j = meshIndices.unsafeGet(i);
                    var k = j * 2;
                    var l = j * (2 + meshCustomFloatAttributesSize);

                    // Position
                    //
                    var x = meshVertices.unsafeGet(l++);
                    var y = meshVertices.unsafeGet(l++);

                    draw.putInPosList(posList, posFloats, matTX + matA * x + matC * y);
                    posFloats++;
                    draw.putInPosList(posList, posFloats, matTY + matB * x + matD * y);
                    posFloats++;
                    draw.putInPosList(posList, posFloats, z);
                    posFloats++;
                    if (textureSlot != -1) {
                        draw.putInPosList(posList, posFloats, textureSlot);
                        posFloats++;
                    }
                    //draw.putInPosList(posList, posFloats, 0);

                    // Custom (float) attributes
                    //
                    if (customFloatAttributesSize != 0) {
                        for (n in 0...customFloatAttributesSize) {
                            if (n < meshCustomFloatAttributesSize) {
                                draw.putInPosList(posList, posFloats, meshVertices.unsafeGet(l++));
                            }
                            else {
                                draw.putInPosList(posList, posFloats, 0.0);
                            }
                            posFloats++;
                        }
                    }

                    // UV
                    //
                    if (texture != null) {
                        var uvX:Float = meshUvs.unsafeGet(k) * uvFactorX;
                        var uvY:Float = meshUvs.unsafeGet(k + 1) * uvFactorY;
                        draw.putInUvList(uvList, uvFloats, uvX);
                        uvFloats++;
                        draw.putInUvList(uvList, uvFloats, uvY);
                        uvFloats++;
                        draw.putInUvList(uvList, uvFloats, 0);
                        uvFloats++;
                        draw.putInUvList(uvList, uvFloats, 0);
                        uvFloats++;
                    }

                    // Color
                    //
                    if (!meshSingleColor) {
                        var meshAlphaColor:AlphaColor = meshIndicesColor ? meshColors.unsafeGet(i) : meshColors.unsafeGet(j);

                        var a:Float;
                        var r:Float;
                        var g:Float;
                        var b:Float;
                        if (meshDrawsRenderTexture || lastComputedBlending == ceramic.Blending.ALPHA) {
                            a = mesh.computedAlpha * meshAlphaColor.alphaFloat;
                            r = meshAlphaColor.redFloat;
                            g = meshAlphaColor.greenFloat;
                            b = meshAlphaColor.blueFloat;
                            if (mesh.blending == ceramic.Blending.ADD && lastComputedBlending != ceramic.Blending.ADD) a = 0;
                        }
                        else {
                            a = mesh.computedAlpha * meshAlphaColor.alphaFloat;
                            r = meshAlphaColor.redFloat * a;
                            g = meshAlphaColor.greenFloat * a;
                            b = meshAlphaColor.blueFloat * a;
                            if (mesh.blending == ceramic.Blending.ADD && lastComputedBlending != ceramic.Blending.ADD) a = 0;
                        }

                        draw.putInColorList(colorList, colorFloats, r);
                        colorFloats++;
                        draw.putInColorList(colorList, colorFloats, g);
                        colorFloats++;
                        draw.putInColorList(colorList, colorFloats, b);
                        colorFloats++;
                        draw.putInColorList(colorList, colorFloats, a);
                        colorFloats++;
                    }

                    i++;
                }

                this.posFloats = posFloats;
                var uvList = draw.getUvList();

                // No texture, all uvs to zero
                //
                if (texture == null) {
                    i = startVertices;
                    while (i < endVertices) {
                        draw.putInUvList(uvList, uvFloats, 0);
                        uvFloats++;
                        draw.putInUvList(uvList, uvFloats, 0);
                        uvFloats++;
                        draw.putInUvList(uvList, uvFloats, 0);
                        uvFloats++;
                        draw.putInUvList(uvList, uvFloats, 0);
                        uvFloats++;
                        i++;
                    }
                }

                this.uvFloats = uvFloats;

                // Single color
                //
                if (meshSingleColor) {

                    var r:Float;
                    var g:Float;
                    var b:Float;
                    var a:Float;

                    if (stencilClip) {
                        a = 1;
                        r = 1;
                        g = 0;
                        b = 0;
                    }
                    else if (meshDrawsRenderTexture || lastComputedBlending == ceramic.Blending.ALPHA) {
                        var meshAlphaColor = meshColors.unsafeGet(0);
                        a = mesh.computedAlpha * meshAlphaColor.alphaFloat;
                        r = meshAlphaColor.redFloat;
                        g = meshAlphaColor.greenFloat;
                        b = meshAlphaColor.blueFloat;
                        if (mesh.blending == ceramic.Blending.ADD && lastComputedBlending != ceramic.Blending.ADD) a = 0;
                    }
                    else {
                        var meshAlphaColor = meshColors.unsafeGet(0);
                        a = mesh.computedAlpha * meshAlphaColor.alphaFloat;
                        r = meshAlphaColor.redFloat * a;
                        g = meshAlphaColor.greenFloat * a;
                        b = meshAlphaColor.blueFloat * a;
                        if (mesh.blending == ceramic.Blending.ADD && lastComputedBlending != ceramic.Blending.ADD) a = 0;
                    }

                    var colorList = draw.getColorList();
                    i = startVertices;
                    while (i < endVertices) {
                        draw.putInColorList(colorList, colorFloats, r);
                        colorFloats++;
                        draw.putInColorList(colorList, colorFloats, g);
                        colorFloats++;
                        draw.putInColorList(colorList, colorFloats, b);
                        colorFloats++;
                        draw.putInColorList(colorList, colorFloats, a);
                        colorFloats++;
                        i++;
                    }
                }

                this.colorFloats = colorFloats;

                if (endVertices == visualNumVertices) {
                    // No need to submit more data, exit loop
                    break;
                }
                else {
                    
                    // There is still data left that needs to be submitted.
                    // Flush pending buffers and iterate once more.

                    flushAndCleanMeshState(draw, mesh);
                    textureSlot = activeShaderCanBatchMultipleTextures ? activeTextureSlot : -1;
                    posFloats = this.posFloats;
                    uvFloats = this.uvFloats;

                    startVertices = endVertices;
                    endVertices = startVertices + maxVertices;
                    if (endVertices > visualNumVertices) {
                        endVertices = visualNumVertices;
                    }
                }

            }

        }

        batchMeshVertices();

        // Let backend know we did finish sending quad data
        draw.endDrawMesh();

        // Increase counts
        this.z = z + 0.001;

    }

    #if (!ceramic_debug_draw && !ceramic_soft_inline) inline #end function flush(draw:backend.Draw):Bool {

        var posFloats = this.posFloats;

        if (posFloats == 0) {
            return false;
        }

        if (posFloats > draw.maxPosFloats()) {
            throw 'Too many floats are being submitted: max=${draw.maxPosFloats()} attempt=${this.posFloats}).';
        }

        draw.flush(posFloats, uvFloats, colorFloats);

        drawCalls++;

        this.posFloats = 0;
        this.uvFloats = 0;
        this.colorFloats = 0;

    #if ceramic_debug_draw
        var flushingQuadsNow = drawnQuads - flushedQuads;
        var flushingMeshesNow = drawnMeshes - flushedMeshes;
        if (debugDraw) {
            log.info('flush - #$drawCalls(${flushingQuadsNow + flushingMeshesNow}/$posFloats) / $lastTexture / $lastShader / $lastRenderTarget / $lastComputedBlending / $lastClip');
        }
        flushedQuads = drawnQuads;
        flushedMeshes = drawnMeshes;
    #end

        return true;

    }
#end

    #if (!ceramic_debug_draw && !ceramic_soft_inline) inline #end function computeQuadBlending(quad:ceramic.Quad):ceramic.Blending {

        var blending = quad.blending;

        /*if (blending == ceramic.Blending.PREMULTIPLIED_ALPHA) {
            // Keep explicit blending
        }*/
        /*else if (blending == ceramic.Blending.AUTO && quad.texture != null && quad.texture.isRenderTexture) {
            blending = ceramic.Blending.ALPHA;
        }
        else */
        if (blending == ceramic.Blending.AUTO || blending == ceramic.Blending.ADD) {
            if (quad.computedRenderTarget != null) {
                blending = ceramic.Blending.RENDER_TO_TEXTURE;
            }
            else {
                blending = ceramic.Blending.PREMULTIPLIED_ALPHA;
            }
        }

        return blending;

    }

    #if (!ceramic_debug_draw && !ceramic_soft_inline) inline #end function computeMeshBlending(mesh:ceramic.Mesh):ceramic.Blending {

        var blending = mesh.blending;

        /*
        if (blending == ceramic.Blending.PREMULTIPLIED_ALPHA) {
            // Keep explicit blending
        }
        else if (blending == ceramic.Blending.AUTO && mesh.texture != null && mesh.texture.isRenderTexture) {
            blending = ceramic.Blending.ALPHA;
        }
        else if (blending == ceramic.Blending.ADD && (mesh.texture == null || !mesh.texture.isRenderTexture)) {
            blending = ceramic.Blending.PREMULTIPLIED_ALPHA;
        }
        */
        if (blending == ceramic.Blending.AUTO || blending == ceramic.Blending.ADD) {
            if (mesh.computedRenderTarget != null) {
                blending = ceramic.Blending.RENDER_TO_TEXTURE;
            }
            else {
                blending = ceramic.Blending.PREMULTIPLIED_ALPHA;
            }
        }

        return blending;

    }

    #if (!ceramic_debug_draw && !ceramic_soft_inline) inline #end function isSameShader(shaderA:ceramic.Shader, shaderB:ceramic.Shader):Bool {

        var backendItemA = shaderA != null ? shaderA.backendItem : defaultTexturedShader;
        var backendItemB = shaderB != null ? shaderB.backendItem : defaultTexturedShader;

        return backendItemA == backendItemB;

    }

    #if (!ceramic_debug_draw && !ceramic_soft_inline) inline #end function useShader(draw:backend.Draw, shader:backend.Shader):Void {

        #if ceramic_debug_draw_shader_use
        if (debugDraw) {
            log.debug('(use shader $shader)');
        }
        #end

        if (shader == null) {
            shader = defaultTexturedShader;
        }

        //if (activeShader != shader) {
            activeShader = shader;
            draw.useShader(shader);
            activeShaderCanBatchMultipleTextures = backendShaders.canBatchWithMultipleTextures(shader);
            customFloatAttributesSize = backendShaders.customFloatAttributesSize(shader);
        //}

    }

    #if (!ceramic_debug_draw && !ceramic_soft_inline) inline #end function useBlending(draw:backend.Draw, blending:ceramic.Blending):Void {

        #if ceramic_debug_draw_blending_use
        if (debugDraw) {
            log.debug('(use blending $blending)');
        }
        #end

        switch blending {
            case PREMULTIPLIED_ALPHA:
                draw.setBlendFuncSeparate(
                    backend.BlendMode.ONE,
                    backend.BlendMode.ONE_MINUS_SRC_ALPHA,
                    backend.BlendMode.ONE,
                    backend.BlendMode.ONE_MINUS_SRC_ALPHA
                );
            case ADD:
                draw.setBlendFuncSeparate(
                    backend.BlendMode.ONE,
                    backend.BlendMode.ONE,
                    backend.BlendMode.ONE,
                    backend.BlendMode.ONE
                );
            case SET:
                draw.setBlendFuncSeparate(
                    backend.BlendMode.ONE,
                    backend.BlendMode.SRC_ALPHA,
                    backend.BlendMode.ONE,
                    backend.BlendMode.SRC_ALPHA
                );
            case RENDER_TO_TEXTURE:
                draw.setBlendFuncSeparate(
                    backend.BlendMode.ONE,
                    backend.BlendMode.ONE_MINUS_SRC_ALPHA,
                    backend.BlendMode.ONE_MINUS_DST_ALPHA,
                    backend.BlendMode.ONE
                );
            case ALPHA:
                draw.setBlendFuncSeparate(
                    backend.BlendMode.SRC_ALPHA,
                    backend.BlendMode.ONE_MINUS_SRC_ALPHA,
                    backend.BlendMode.ONE,
                    backend.BlendMode.ONE_MINUS_SRC_ALPHA
                );
            case AUTO:
                throw 'Cannot apply AUTO blending. Needs to be computed to an actual blending function.';
        }

    }

    #if (!ceramic_debug_draw && !ceramic_soft_inline) inline #end function useRenderTarget(draw:backend.Draw, renderTarget:ceramic.RenderTexture):Void {

        if (renderTarget != null) {
            draw.setRenderTarget(renderTarget);
        }
        else {
            draw.setRenderTarget(null);
        }

    }

    #if (!ceramic_debug_draw && !ceramic_soft_inline) inline #end function useFirstTextureInBatch(draw:backend.Draw, texture:ceramic.Texture):Void {

        //if (texture != null) {
            if (texture == null) {
                texture = defaultWhiteTexture;
            }
            usedTextures = 1;
            var textureIndex = backendTextures.getTextureIndex(texture.backendItem);
            usedTextureIndexes.unsafeSet(0, textureIndex);
            draw.setActiveTexture(0);
            activeTextureSlot = 0;
            useTexture(draw, texture, false);
        /*}
        else {
            usedTextures = 0;
            draw.setActiveTexture(0);
            activeTextureSlot = 0;
            useTexture(draw, null);
        }*/

    }

    #if (!ceramic_debug_draw && !ceramic_soft_inline) inline #end function useTexture(draw:backend.Draw, texture:ceramic.Texture, reusing:Bool):Void {

        if (texture != null) {
    #if (ceramic_debug_draw && ceramic_debug_multitexture)
            if (debugDraw && activeShaderCanBatchMultipleTextures) {
                if (reusing) {
                    log.success('REUSE Texture(${draw.getActiveTexture()}) -> ${texture}');
                }
                else {
                    log.success('BIND Texture(${draw.getActiveTexture()}) -> ${texture}');
                }
            }
    #end
            lastTexture = texture;
            lastTextureId = draw.getTextureId(texture.backendItem);
            texWidth = draw.getTextureWidth(texture.backendItem);
            texHeight = draw.getTextureHeight(texture.backendItem);
            texWidthActual = draw.getTextureWidthActual(texture.backendItem);
            texHeightActual = draw.getTextureHeightActual(texture.backendItem);
            if (!reusing) {
                draw.bindTexture(texture.backendItem);
            }
        }
        else {
            lastTexture = null;
            lastTextureId = backend.TextureId.DEFAULT;
            draw.bindNoTexture();
        }

    }

    #if (!ceramic_debug_draw && !ceramic_soft_inline) inline #end function canUseTextureInSameBatch(draw:backend.Draw, texture:ceramic.Texture):Bool {

        var canKeepSameState = false;

        if (texture == null) {
            texture = defaultWhiteTexture;
        }

        if (usedTextures > 0) {

            if (activeShaderCanBatchMultipleTextures) {

                var textureIndex = backendTextures.getTextureIndex(texture.backendItem);

                for (slot in 0...usedTextures) {
                    if (textureIndex == usedTextureIndexes.unsafeGet(slot)) {
                        // Texture already used in batch, all good
                        canKeepSameState = true;
                        break;
                    }
                }

                if (!canKeepSameState && usedTextures < maxUsableTexturesInBatch) {
                    canKeepSameState = true;
                }
            }
            else if (lastTexture == texture) {

                canKeepSameState = true;
            }
        }

        return canKeepSameState;

    }

    #if (!ceramic_debug_draw && !ceramic_soft_inline) inline #end function useTextureInSameBatch(draw:backend.Draw, texture:ceramic.Texture):Void {

        var alreadyUsed = false;

        if (texture == null) {
            texture = defaultWhiteTexture;
        }

        if (activeShaderCanBatchMultipleTextures) {

            var textureIndex = backendTextures.getTextureIndex(texture.backendItem);

            for (slot in 0...usedTextures) {
                if (textureIndex == usedTextureIndexes.unsafeGet(slot)) {
                    // Texture already used in batch, all good
                    draw.setActiveTexture(slot);
                    activeTextureSlot = slot;
                    useTexture(draw, texture, true);
                    alreadyUsed = true;
                    break;
                }
            }

            if (!alreadyUsed && usedTextures < maxUsableTexturesInBatch) {
                var slot = usedTextures++;
                usedTextureIndexes.unsafeSet(slot, textureIndex);
                draw.setActiveTexture(slot);
                activeTextureSlot = slot;
                useTexture(draw, texture, false);
            }
        }

    }

    #if (!ceramic_debug_draw && !ceramic_soft_inline) inline #end function unbindUsedTextures(draw:backend.Draw):Void {

        while (usedTextures > 0) {
            usedTextures--;
            draw.setActiveTexture(usedTextures);
            draw.bindNoTexture();
        }
        draw.setActiveTexture(0);
        activeTextureSlot = 0;
        useTexture(draw, null, false);

    }
    
}
