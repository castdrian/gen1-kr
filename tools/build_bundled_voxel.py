import argparse
import re
import shutil
from pathlib import Path


REGISTRY = '''
local entityModels = {}
local entityModelSequence = 0
local worldEffects = {}
local worldEffectSequence = 0

function VoxelScene.registerEntityModel(id, callback, priority)
  assert(type(id) == "string" and id ~= "", "entity model id is required")
  assert(type(callback) == "function", "entity model callback is required")
  entityModelSequence = entityModelSequence + 1
  local entry = {
    id = id,
    callback = callback,
    priority = priority or 0,
    sequence = entityModelSequence,
  }
  entityModels[#entityModels + 1] = entry
  table.sort(entityModels, function(a, b)
    if a.priority == b.priority then return a.sequence < b.sequence end
    return a.priority > b.priority
  end)
  return function()
    for i, candidate in ipairs(entityModels) do
      if candidate == entry then
        table.remove(entityModels, i)
        break
      end
    end
  end
end

function VoxelScene.drawEntityModel(context)
  for _, entry in ipairs(entityModels) do
    local ok, handled = pcall(entry.callback, context)
    if not ok then
      Logger.warn("[%s] voxel entity model failed: %s", entry.id,
                  tostring(handled))
    elseif handled then
      return true
    end
  end
  return false
end

function VoxelScene.registerWorldEffect(callback, priority)
  assert(type(callback) == "function", "world effect callback is required")
  worldEffectSequence = worldEffectSequence + 1
  local entry = {
    callback = callback,
    priority = priority or 0,
    sequence = worldEffectSequence,
  }
  worldEffects[#worldEffects + 1] = entry
  table.sort(worldEffects, function(a, b)
    if a.priority == b.priority then return a.sequence < b.sequence end
    return a.priority > b.priority
  end)
  return function()
    for i, candidate in ipairs(worldEffects) do
      if candidate == entry then
        table.remove(worldEffects, i)
        break
      end
    end
  end
end

function VoxelScene.drawWorldEffects(context)
  for _, entry in ipairs(worldEffects) do
    local ok, result = pcall(entry.callback, context)
    if not ok then
      Logger.warn("voxel world effect failed: %s", tostring(result))
    end
  end
end
'''


MODEL_CONTEXT = '''
local function modelContext(pass, sprite, px, py, facing, phase, flip,
                            gh, colors, lift, moving)
  return {
    pass = pass,
    sprite = sprite,
    def = sprite.def,
    px = px,
    py = py,
    facing = facing,
    phase = phase,
    flip = flip,
    ground = gh,
    lift = lift or 0,
    colors = colors,
    moving = moving and true or false,
    voxel = Voxel3D,
    mat4 = Mat4,
    newMesh = Voxel3D.newMesh,
    draw = Voxel3D.draw,
    shadow = ShadowMap.draw,
    pull = billboardPull(),
  }
end
'''


def replace_once(text, old, new):
    if old not in text:
        raise ValueError("missing source anchor: " + old[:80])
    return text.replace(old, new, 1)


def patch_scene(text):
    text = replace_once(
        text,
        'local Map = require("src.world.Map")',
        'local Map = require("src.world.Map")\nlocal Logger = require("src.core.Logger")')
    text = replace_once(text, "local VoxelScene = {}\n",
                        "local VoxelScene = {}\n" + REGISTRY + "\n")
    text = replace_once(text, "local function drawEntity(sprite, px, py, facing, phase, flip, gh, colors,\n                          lift)\n  local def = sprite.def",
                        "local function drawEntity(sprite, px, py, facing, phase, flip, gh, colors,\n                          lift, moving)\n  if VoxelScene.drawEntityModel(modelContext(\n      \"scene\", sprite, px, py, facing, phase, flip, gh, colors, lift,\n      moving)) then\n    return true\n  end\n  local def = sprite.def")
    text = replace_once(text, "local function drawGhost(p)\n  local def = p.sprite.def",
                        "local function drawGhost(p)\n  if VoxelScene.drawEntityModel(modelContext(\n      \"ghost\", p.sprite, p.px, p.py, viewFacing(p), p.phase, p.flip,\n      p.gh, p.colors, p.lift, p.moving)) then\n    return\n  end\n  local def = p.sprite.def")
    text = replace_once(text, "local function drawEntity(sprite, px, py, facing, phase, flip, gh, colors,\n                          lift, moving)\n",
                        MODEL_CONTEXT + "\nlocal function drawEntity(sprite, px, py, facing, phase, flip, gh, colors,\n                          lift, moving)\n")
    text = replace_once(text,
                        "drawEntity(p.sprite, p.px, p.py, viewFacing(p), p.phase, p.flip, p.gh,\n                 p.colors, p.lift)",
                        "drawEntity(p.sprite, p.px, p.py, viewFacing(p), p.phase, p.flip, p.gh,\n                 p.colors, p.lift, p.moving)")
    text = replace_once(text,
                        "lift = g.npc.py - vy, colors = spriteColors(g.map or state.map),",
                        "lift = g.npc.py - vy, moving = g.npc.moving,\n      colors = spriteColors(g.map or state.map),")
    text = replace_once(text,
                        "lift = e.py - vy, colors = colors,",
                        "lift = e.py - vy, moving = e.moving, colors = colors,")
    text = replace_once(
        text,
        "  drawCast(state, posed, atlasFor)\n",
        "  drawCast(state, posed, atlasFor)\n  VoxelScene.drawWorldEffects({\n    state = state, map = state.map, camera = state.camera,\n    voxel = Voxel3D, mat4 = Mat4, newMesh = Voxel3D.newMesh,\n    draw = Voxel3D.draw, shadow = ShadowMap.draw,\n    pull = VoxelScene.pull(math.max(leanAngle(), 0.05)),\n  })\n")
    cast_start = text.index("local function castShadows")
    loop_start = text.index("  for _, p in ipairs(posed) do", cast_start)
    marker = text.index("  ShadowMap.sprites(false)", loop_start)
    block = text[loop_start:marker]
    body_start = block.index("\n") + 1
    body = block[body_start:]
    body = re.sub(r"\n  end\n\s*$", "\n", body)
    body = "\n".join("  " + line if line else line for line in body.split("\n"))
    custom = '''  for _, p in ipairs(posed) do
    local handled = VoxelScene.drawEntityModel(modelContext(
        "shadow", p.sprite, p.px, p.py, viewFacing(p), p.phase, p.flip,
        p.gh, p.colors, p.lift, p.moving))
    if not handled then
''' + body + '''
    end
  end
'''
    text = text[:loop_start] + custom + text[marker:]
    return text


def patch_main(text):
    text = text.replace("mod.options:define(schema)", "V.optionsSchema = schema", 1)
    text = text.replace('id = "DRAMATIC_SHAPE:" .. self.key,',
                        'id = modId() .. ":" .. self.key,', 1)
    marker = text.rfind("mod.exports.version =")
    if marker < 0:
        raise ValueError("missing voxel main export anchor")
    text = text[:marker] + "mod.exports.lib = V\n"
    text += "\nreturn { V = V, VoxelScene = VoxelScene, settings = V.optionsSchema }\n"
    return text


def build(source, output):
    source = source.resolve()
    output = output.resolve()
    if not (source / "main.lua").is_file():
        raise SystemExit("Dramatic Shape submodule is not initialized")
    output.mkdir(parents=True, exist_ok=True)
    for folder in ("lib", "data"):
        target = output / folder
        shutil.copytree(source / folder, target, dirs_exist_ok=True)
    scene = output / "lib" / "VoxelScene.lua"
    scene.write_text(patch_scene(scene.read_text(encoding="utf-8-sig")),
                     encoding="utf-8", newline="\n")
    setting = output / "lib" / "ModSetting.lua"
    setting.write_text(setting.read_text(encoding="utf-8-sig").replace(
        'id = "DRAMATIC_SHAPE:" .. self.key,',
        'id = modId() .. ":" .. self.key,'), encoding="utf-8", newline="\n")
    main = patch_main((source / "main.lua").read_text(
        encoding="utf-8-sig"))
    (output / "voxel_main.lua").write_text(main, encoding="utf-8", newline="\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    build(args.source, args.output)


if __name__ == "__main__":
    main()
