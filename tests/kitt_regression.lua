local function read(path)
  local handle = assert(io.open(path, "rb"))
  local body = handle:read("*a")
  handle:close()
  return body
end

local function jsonDependencies(body)
  local value = assert(body:match('"dependencies"%s*:%s*%[(.-)%]'))
  return value
end

local manifest = read("manifest.json")
assert(jsonDependencies(manifest):find("DRAMATIC_SHAPE", 1, true))
assert(jsonDependencies(manifest):find(">=1.6.0 <2.0.0", 1, true))
assert(not manifest:find('"conflicts"%s*:%s*%[%s*"DRAMATIC_SHAPE"'))

local originalRequire = require
local modules = {
  ["src.core.Game"] = { stack = { states = {} } },
  ["src.world.Collision"] = {
    DELTA = {
      up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 },
    },
  },
  ["src.world.Map"] = { isOutdoor = function() return true end },
  ["src.core.Music"] = { playMap = function() end },
  ["src.world.Player"] = { pose = function() end, update = function() end },
  ["src.render.SpriteRenderer"] = { new = function() return {} end },
  ["src.render.Pipelines"] = {
    maxLevel = function() return 4 end,
    setLevel = function() end,
    syncOptions = function() end,
  },
}

_G.love = {
  filesystem = { getInfo = function() return { type = "file" } end },
  system = { getOS = function() return "OS X" end },
}

package.loaded["src.core.Game"] = modules["src.core.Game"]
package.loaded["src.world.Collision"] = modules["src.world.Collision"]
package.loaded["src.world.Map"] = modules["src.world.Map"]
package.loaded["src.core.Music"] = modules["src.core.Music"]
package.loaded["src.world.Player"] = modules["src.world.Player"]
package.loaded["src.render.SpriteRenderer"] = modules["src.render.SpriteRenderer"]
package.loaded["src.render.Pipelines"] = modules["src.render.Pipelines"]

local schema, settings, hooks, events = nil, {}, {}, {}
local function drawEntity() end
local function drawGhost() end
local function drawShadow() end
local function drawCast() drawEntity() end
local function render() drawShadow() drawGhost() drawCast() end
local scene = { render = render }
local external = {
  id = "DRAMATIC_SHAPE",
  version = "1.6.0",
  exports = {
    version = "1.6.0",
    lib = {
      require = function(name)
        if name == "VoxelScene" then return scene end
        return {}
      end,
    },
  },
}

local mod = {
  id = "gen1_kr",
  path = "mods/gen1_kr",
  manifest = { version = "0.1.1" },
  content = {
    sprites = { register = function() end },
    music = { register = function() end },
  },
  exports = {},
  options = {
    define = function(_, value) schema = value end,
    get = function(_, key)
      if settings[key] ~= nil then return settings[key] end
      for _, row in ipairs(schema or {}) do
        if row.key == key then return row.default end
      end
    end,
  },
  events = {
    on = function(_, name, callback) events[name] = callback end,
  },
  hooks = {
    wrap = function(_, name, callback) hooks[name] = callback end,
  },
  ui = {
    insertBefore = function(items, label, item)
      local out = {}
      for _, existing in ipairs(items) do
        if existing.label == label then out[#out + 1] = item end
        out[#out + 1] = existing
      end
      return out
    end,
  },
  assets = { path = function(_, path) return path end },
  read = function() return nil end,
  find = function(_, id)
    if id == "DRAMATIC_SHAPE" then return external end
  end,
  log = { warn = function() end },
}

local entry = assert(loadfile("main.lua"))()
entry(mod)

local function upvalue(callback, name)
  for index = 1, math.huge do
    local current, value = debug.getupvalue(callback, index)
    if not current then return nil end
    if current == name then return value end
  end
end

local wrappedDrawCast = assert(upvalue(scene.render, "drawCast"))
local wrappedDrawEntity = assert(upvalue(wrappedDrawCast, "drawEntity"))
assert(debug.getinfo(wrappedDrawEntity, "S").source:find("main.lua", 1, true))

local menuGame = { save = { options = {} }, mods = { modOptions = {} } }
local startItems = hooks["ui.start_menu.items"](function(_, items) return items end,
  menuGame,
  { { label = "OPTION" } })
local kittItem = startItems[1]
assert(kittItem.label == "KITT OFF")
kittItem.onSelect()
assert(kittItem.label == "KITT ON")
assert(menuGame.save.options.modOptions.gen1_kr.kitt == true)
settings.kitt = true

local rows = hooks["ui.options.rows"](function(_, value) return value end,
  { save = { options = {} }, mods = { modOptions = {} } }, {})
local speed
for _, row in ipairs(rows) do
  if row.id == "gen1_kr:speed" then speed = row break end
end
assert(speed and speed.value() == "NORMAL")
local speedPlayer = { surfing = false, fishing = false }
modules["src.core.Game"].overworld = { player = speedPlayer, map = { def = {} } }
assert(hooks["movement.speed"](function() return 100 end,
  1, { player = speedPlayer }) == 42)
settings.speed = "FAST"
assert(hooks["movement.speed"](function() return 100 end,
  1, { player = speedPlayer }) == 34)
settings.speed = "NORMAL"

local source = read("main.lua")
assert(not source:find("loadBundledVoxel", 1, true))
assert(source:find("skiMode", 1, true))
assert(source:find("SKI_FILE", 1, true))
assert(not source:find("VEHICLE_HALF_WIDTH", 1, true))
assert(not source:find("wheel.inset", 1, true))
assert(source:find("installExternalVoxel", 1, true))
assert(source:find("skiTransform", 1, true))
assert(source:find("rotateZ", 1, true))
assert(not source:find("m.rotateX(skiState.amount", 1, true))
assert(source:find("POWER_UP_FILE", 1, true))
assert(source:find("POWER_DOWN_FILE", 1, true))
assert(source:find("POWER_DOWN_DURATION", 1, true))
assert(source:find("-math.cos(math.pi * progress) * 0.32", 1, true))
assert(source:find("requestSkiMode", 1, true))
assert(source:find('key == "s"', 1, true))
assert(not source:find('key == "v"', 1, true))
assert(not source:find('key = "threeD"', 1, true))
assert(not source:find("assets/kitt.png", 1, true))
assert(source:find('ctx.facing ~= "down"', 1, true))
assert(source:find('ctx.voxel.depth("always")', 1, true))

print("gen1 kr regression ok")
