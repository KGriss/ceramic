package ceramic;

import ceramic.Path;
import ceramic.Shortcuts.*;

using StringTools;
using ceramic.Extensions;

class ShaderAsset extends Asset {

    public var shader:Shader = null;

    override public function new(name:String, ?options:AssetOptions #if ceramic_debug_entity_allocs , ?pos:haxe.PosInfos #end) {

        super('shader', name, options #if ceramic_debug_entity_allocs , pos #end);

    }

    override public function load() {

        status = LOADING;

        if (path == null) {
            log.warning('Cannot load shader asset if path is undefined.');
            status = BROKEN;
            emitComplete(false);
            return;
        }

        var customAttributes:Array<ShaderAttribute> = null;
        if (options.customAttributes != null) {
            customAttributes = [];
            var rawAttributes:Array<Any> = options.customAttributes;
            for (i in 0...rawAttributes.length) {
                var rawAttr:Dynamic = rawAttributes.unsafeGet(i);
                customAttributes.push({
                    size: rawAttr.size,
                    name: rawAttr.name
                });
            }
        }

        var loadOptions:AssetOptions = {};
        if (owner != null) {
            loadOptions.immediate = owner.immediate;
            loadOptions.loadMethod = owner.loadMethod;
        }

#if ceramic_shader_vert_frag
        // Compute vertex and fragment shader paths
        if (path != null && (path.toLowerCase().endsWith('.frag') || path.toLowerCase().endsWith('.vert'))) {
            var paths = Assets.allByName.get(name);
            if (options.fragId == null) {
                for (i in 0...paths.length) {
                    var path = paths.unsafeGet(i);
                    if (path.toLowerCase().endsWith('.frag')) {
                        options.fragId = path;
                        break;
                    }
                }
            }
            if (options.vertId == null) {
                for (i in 0...paths.length) {
                    var path = paths.unsafeGet(i);
                    if (path.toLowerCase().endsWith('.vert')) {
                        options.vertId = path;
                        break;
                    }
                }
            }
            // If no vertex shader is provided, use default (textured one)
            log.info('Load shader' + (options.vertId != null ? ' ' + options.vertId : '') + (options.fragId != null ? ' ' + options.fragId : ''));
        }
        else {
            log.info('Load shader $path');
        }

        if (options.vertId == null) {
            options.vertId = 'textured.vert';
        }

        if (options.fragId == null) {
            status = BROKEN;
            log.error('Missing fragId option to load shader at path: $path');
            emitComplete(false);
            return;
        }

        app.backend.texts.load(Assets.realAssetPath(options.vertId, runtimeAssets), loadOptions, function(vertSource) {
            app.backend.texts.load(Assets.realAssetPath(options.fragId, runtimeAssets), loadOptions, function(fragSource) {

                if (vertSource == null) {
                    status = BROKEN;
                    log.error('Failed to load ' + options.vertId + ' for shader at path: $path');
                    emitComplete(false);
                    return;
                }

                if (fragSource == null) {
                    status = BROKEN;
                    log.error('Failed to load ' + options.fragId + ' for shader at path: $path');
                    emitComplete(false);
                    return;
                }

                var backendItem = app.backend.shaders.fromSource(vertSource, fragSource, customAttributes);
                if (backendItem == null) {
                    status = BROKEN;
                    log.error('Failed to create shader from data at path: $path');
                    emitComplete(false);
                    return;
                }

                this.shader = new Shader(backendItem, customAttributes);
                this.shader.asset = this;
                this.shader.id = 'shader:' + path;
                status = READY;
                emitComplete(true);

            });
        });
#else
        app.backend.shaders.load(Assets.realAssetPath(path, runtimeAssets), customAttributes, function(backendItem) {

            if (backendItem == null) {
                status = BROKEN;
                log.error('Failed to load shader at path: $path');
                emitComplete(false);
                return;
            }

            this.shader = new Shader(backendItem, customAttributes);
            this.shader.asset = this;
            this.shader.id = 'shader:' + path;
            status = READY;
            emitComplete(true);

        });
#end

    }

    override function destroy():Void {

        super.destroy();

        if (shader != null) {
            shader.destroy();
            shader = null;
        }

    }

/// Print

    override function toString():String {

        var className = 'ShaderAsset';

        if (options.vertId != null || options.fragId != null) {
            var vertId = options.vertId != null ? options.vertId : 'default';
            var fragId = options.fragId != null ? options.fragId : 'default';
            return '$className($name $vertId $fragId)';
        }
        else if (path != null && path.trim() != '') {
            return '$className($name $path)';
        } else {
            return '$className($name)';
        }

    }

}
