local MOD_ID = "gen1_kr"

local MUSIC = {
  Original = { id = "Music_Gen1KR_Original", file = "audio/original.ogg" },
  KR2008 = { id = "Music_Gen1KR_KR2008", file = "audio/kr2008.ogg" },
}

local ENGINE_FILES = {
  Original = "audio/engine.ogg",
  KR2008 = "audio/kr2008_engine.ogg",
}
local SCANNER_FILE = "audio/scanner.ogg"
local KARR_SCANNER_FILE = "audio/karr-scanner.ogg"
local WILHELM_FILE = "audio/wilhelm.ogg"
local CRASH_FILE = "audio/car_crash.ogg"
local CRASH_IMPACT_OFFSET = 1.66
local CRASH_PRE_ROLL = 0.75
local TURBO_FILE = "audio/turbo.ogg"
local LASER_FILE = "audio/laser.ogg"
local LASER_TEXTURE_FILE = "assets/laser.png"
local SKI_FILE = "audio/ski_mode.ogg"
local POWER_UP_FILE = "audio/power_up.ogg"
local POWER_DOWN_FILE = "audio/power_down.ogg"
local POWER_DOWN_DURATION = 3.35
local SKI_ACTIVATION_DELAY = 0.3
local TURBO_ACTIVATION_DELAY = 0.18
local TURBO_HOP_FRAMES = 36
local TURBO_DISTANCE = 96
local ATTACK_TRANSFORM_FILE = "audio/attack-transform.ogg"
local ATTACK_TRANSFORM_DURATION = 5.02
local VOICE_FILES = {
  Original = {
    nominal = "audio/kitt-2000-nominal.ogg",
    turbo = "audio/kitt-2000-turbo.ogg",
    collision = {
      "audio/kitt-2000-collision.ogg",
      "audio/kitt-2000-turbo.ogg",
      "audio/kitt-2000-property-damage.ogg",
      "audio/kitt-2000-inadvisable.ogg",
    },
  },
  KR2008 = {
    nominal = "audio/kitt-3000-nominal.ogg",
    turbo = "audio/kitt-3000-turbo.ogg",
    collision = {
      "audio/kitt-3000-collision.ogg",
      "audio/kitt-3000-turbo.ogg",
      "audio/kitt-3000-driving-strategy.ogg",
      "audio/kitt-3000-threat-assessment.ogg",
      "audio/kitt-3000-enjoying-this.ogg",
    },
  },
}
local COLLISION_RADIUS = 22
local COLLISION_HALF_WIDTH = 7
local VOXEL_LEVEL = 4
local MODEL_FILES = {
  Original = "assets/kitt_model.lua",
  KR2008 = "assets/mustang_model.lua",
  KR2008Attack = "assets/kitt-3000-attack-model.lua",
}
local PALETTE_FILES = {
  Original = {
    "assets/kitt_palette_0.png",
    "assets/kitt_palette_1.png",
    "assets/kitt_palette_2.png",
    "assets/kitt_palette_3.png",
  },
  OriginalKarr = {
    "assets/karr_palette_0.png",
    "assets/karr_palette_1.png",
    "assets/karr_palette_2.png",
    "assets/karr_palette_3.png",
  },
  KR2008 = "assets/mustang_texture.png",
  KR2008Attack = "assets/kitt-3000-attack-texture.png",
}
local SCANNER_LIGHT_FILES = {
  KITT = {
    "assets/scanner_dim.png",
    "assets/scanner_medium.png",
    "assets/scanner_bright.png",
  },
  KARR2000 = {
    "assets/karr2000_scanner_dim.png",
    "assets/karr2000_scanner_medium.png",
    "assets/karr2000_scanner_bright.png",
  },
  KARR3000 = {
    "assets/karr3000_scanner_dim.png",
    "assets/karr3000_scanner_medium.png",
    "assets/karr3000_scanner_bright.png",
  },
}
local CAR_ICON_FILES = {
  Original = { KITT = "assets/kitt-2000-icon.png", KARR = "assets/karr-2000-icon.png" },
  KR2008 = { KITT = "assets/kitt-3000-icon.png", KARR = "assets/karr-3000-icon.png" },
}
local SKI_ICON_FILE = "assets/ski-mode-icon.png"
local ATTACK_ICON_FILE = "assets/attack-mode-icon.png"
local SPEED_MULTIPLIERS = {
  SLOW = 0.52,
  NORMAL = 0.42,
  FAST = 0.34,
}
local SPEED_CHOICES = { "SLOW", "NORMAL", "FAST" }

return function(mod)
  local Game = require("src.core.Game")
  local Collision = require("src.world.Collision")
  local Map = require("src.world.Map")
  local Music = require("src.core.Music")
  local Player = require("src.world.Player")
  local SpriteRenderer = require("src.render.SpriteRenderer")
  local Pipelines = require("src.render.Pipelines")
  local externalVoxel = mod:find("DRAMATIC_SHAPE")
  local VoxelScene
  local Voxel3D
  local VoxelState
  local Mat4
  local ShadowMap
  local turbo

  local tracks = {}
  local function hasFile(relative)
    if not love or not love.filesystem or not love.filesystem.getInfo then
      return true
    end
    local info = love.filesystem.getInfo(mod.path .. "/" .. relative)
    return info ~= nil and (info.type == nil or info.type == "file")
  end

  for name, record in pairs(MUSIC) do
    if hasFile(record.file) then
      mod.content.music:register(record.id, {
        file = mod.path .. "/" .. record.file,
      })
      tracks[name] = record.id
    end
  end

  local ownOptions = {
    {
      key = "kitt",
      label = "K.I.T.T.",
      type = "toggle",
      default = false,
    },
    {
      key = "audio",
      label = "MODE",
      type = "choice",
      default = "Original",
      choices = {
        { "Original", "Original" },
        { "KR2008", "KR2008" },
      },
    },
    {
      key = "speed",
      label = "SPEED",
      type = "choice",
      default = "NORMAL",
      choices = {
        { "SLOW", "SLOW" },
        { "NORMAL", "NORMAL" },
        { "FAST", "FAST" },
      },
    },
    {
      key = "impactCollision",
      label = "COLLISION",
      type = "toggle",
      default = true,
    },
  }
  mod.options:define(ownOptions)
  mod.exports.version = mod.manifest and mod.manifest.version or "0.4.23"
  mod.exports.cameraLevel = VOXEL_LEVEL
  mod.exports.collision = {
    radius = COLLISION_RADIUS,
    horizontalSpeed = 560,
    verticalSpeed = 720,
    duration = 1.35,
    respawnDelay = 5.0,
    burstCount = 64,
  }

  local function optionValue(key, default)
    local value = mod.options:get(key)
    value = value == nil and default or value
    if key == "audio" and value == "KR2009" then
      return "KR2008"
    end
    return value
  end

  local function kittEnabled()
    return optionValue("kitt", false)
  end

  local function karrEnabled()
    return kittEnabled() and optionValue("karr", false)
  end

  local powerDownVisible = false

  local function kittVisible()
    return kittEnabled() or powerDownVisible
  end

  local skiState = { amount = 0 }
  local laserState = { held = false, active = false }
  local attackState = { transition = nil }
  local requestAttackMode

  local function skiEnabled()
    return kittEnabled() and optionValue("skiMode", false)
  end

  local function attackAvailable()
    return kittEnabled() and optionValue("audio", "Original") == "KR2008"
  end

  local function attackVisual()
    local transition = attackState.transition
    if not transition then
      return optionValue("attackMode", false), 1, 0, 0
    end
    local now = love.timer and love.timer.getTime and love.timer.getTime() or transition.started
    local progress = math.max(0, math.min(1, (now - transition.started) / transition.duration))
    local active = progress >= 0.5 and transition.target or transition.from
    local pulse = math.sin(math.pi * progress)
    return active, 1, pulse * 0.55, 0
  end

  local function vehicleSpeed()
    return SPEED_MULTIPLIERS[optionValue("speed", "NORMAL")]
        or SPEED_MULTIPLIERS.NORMAL
  end

  local function updateSkiState(dt)
    local target = skiEnabled() and 1 or 0
    local amount = skiState.amount
    local step = math.max(0, math.min(1, (dt or 1 / 60) * 4))
    skiState.amount = amount + (target - amount) * step
  end

  local function loadExternalVoxel()
    if VoxelScene and Voxel3D and VoxelState and Mat4 and ShadowMap then
      return true
    end
    local exports = externalVoxel and externalVoxel.exports
    local lib = exports and exports.lib
    if type(lib) ~= "table" or type(lib.require) ~= "function" then
      mod.log:warn("Dramatic Shape exports are unavailable")
      return false
    end
    local function loadModule(name)
      local ok, value = pcall(lib.require, name)
      return ok and value or nil
    end
    VoxelScene = loadModule("VoxelScene")
    Voxel3D = loadModule("Voxel3D")
    VoxelState = loadModule("VoxelState")
    Mat4 = loadModule("Mat4")
    ShadowMap = loadModule("ShadowMap")
    if not (VoxelScene and Voxel3D and VoxelState and Mat4 and ShadowMap) then
      mod.log:warn("Dramatic Shape does not provide the required voxel modules")
      return false
    end
    return true
  end

  local function setOption(game, key, value)
    local save = game and game.save and game.save.options
    if save then
      save.modOptions = save.modOptions or {}
      save.modOptions[mod.id] = save.modOptions[mod.id] or {}
      save.modOptions[mod.id][key] = value
    end
    local loader = game and game.mods
    if loader then
      loader.modOptions = loader.modOptions or {}
      loader.modOptions[mod.id] = loader.modOptions[mod.id] or {}
      loader.modOptions[mod.id][key] = value
      if loader.events then
        loader.events:emit("mod.options_changed", {
          mod = mod.id, key = key, value = value,
        })
      end
    end
    if game and game.writeOptions then game:writeOptions() end
  end

  local function setVoxelMode(game)
    Pipelines.setLevel("voxel", math.min(VOXEL_LEVEL, Pipelines.maxLevel("voxel")))
    local opts = game and game.save and game.save.options
    if opts then
      Pipelines.syncOptions(opts)
      if game.writeOptions then game:writeOptions() end
    end
  end

  local function optionRows(next, game, rows)
    local out = next(game, rows)
    if type(out) ~= "table" then return out end
    local filtered = {}
    for _, row in ipairs(out) do
      local id = type(row) == "table" and row.id or nil
      if id ~= "pipeline:voxel" and id ~= "pipeline:tiltshift"
          and not (type(id) == "string" and id:sub(1, #MOD_ID + 1)
                   == MOD_ID .. ":") then
        filtered[#filtered + 1] = row
      end
    end
    local function cycleBoolean(game_, key, default)
      local enabled = optionValue(key, default)
      setOption(game_, key, not enabled)
      return true
    end
    local function cycleChoice(game_, key, choices, default)
      local current = optionValue(key, default)
      local index = 1
      for i, value in ipairs(choices) do
        if value == current then index = i break end
      end
      setOption(game_, key, choices[index % #choices + 1])
      return true
    end
    filtered[#filtered + 1] = {
      id = MOD_ID .. ":kitt",
      label = "K.I.T.T.",
      value = function() return optionValue("kitt", false) and "ON" or "OFF" end,
      step = function(game_) return cycleBoolean(game_, "kitt", false) end,
    }
    filtered[#filtered + 1] = {
      id = MOD_ID .. ":audio",
      label = "MODE",
      value = function() return optionValue("audio", "Original") end,
      step = function(game_)
        local current = optionValue("audio", "Original")
        local value = current == "Original" and "KR2008" or "Original"
        setOption(game_, "audio", value)
        return true
      end,
    }
    filtered[#filtered + 1] = {
      id = MOD_ID .. ":speed",
      label = "SPEED",
      value = function() return optionValue("speed", "NORMAL") end,
      step = function(game_)
        return cycleChoice(game_, "speed", SPEED_CHOICES, "NORMAL")
      end,
    }
    filtered[#filtered + 1] = {
      id = MOD_ID .. ":impactCollision",
      label = "COLLISION",
      value = function() return optionValue("impactCollision", true) and "ON" or "OFF" end,
      step = function(game_) return cycleBoolean(game_, "impactCollision", true) end,
    }
    return filtered
  end

  mod.hooks:wrap("ui.options.rows", optionRows, 1000)

  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local out = next(game, items)
    if type(out) ~= "table" then return out end
    local item = {
      label = kittEnabled() and "KITT ON" or "KITT OFF",
      keepOpen = true,
    }
    item.onSelect = function()
      local enabled = not optionValue("kitt", false)
      setOption(game, "kitt", enabled)
      item.label = enabled and "KITT ON" or "KITT OFF"
    end
    return mod.ui.insertBefore(out, "OPTION", item)
  end, 1000)

  local voxelModels = {}

  local function createWheelMesh(ctx)
    local vertices = {}
    local segments = 12
    local radius = 2.05
    local halfWidth = 0.72
    local u = 13.5 / 16
    local function vertex(x, y, z, shade)
      return { x, y, z, u, 0.5, shade }
    end
    for index = 0, segments - 1 do
      local angle = index / segments * math.pi * 2
      local nextAngle = (index + 1) / segments * math.pi * 2
      local y1, z1 = math.sin(angle) * radius, math.cos(angle) * radius
      local y2, z2 = math.sin(nextAngle) * radius, math.cos(nextAngle) * radius
      local left1 = vertex(-halfWidth, y1, z1, 0.58)
      local right1 = vertex(halfWidth, y1, z1, 0.58)
      local left2 = vertex(-halfWidth, y2, z2, 0.74)
      local right2 = vertex(halfWidth, y2, z2, 0.74)
      vertices[#vertices + 1], vertices[#vertices + 2], vertices[#vertices + 3] = left1, right1, right2
      vertices[#vertices + 1], vertices[#vertices + 2], vertices[#vertices + 3] = left1, right2, left2
      local leftCenter = vertex(-halfWidth, 0, 0, 0.62)
      local rightCenter = vertex(halfWidth, 0, 0, 0.68)
      vertices[#vertices + 1], vertices[#vertices + 2], vertices[#vertices + 3] = leftCenter, left2, left1
      vertices[#vertices + 1], vertices[#vertices + 2], vertices[#vertices + 3] = rightCenter, right1, right2
    end
    local ok, mesh = pcall(ctx.newMesh, vertices, nil)
    return ok and mesh or nil
  end

  local function createScannerMesh(ctx)
    local halfWidth, halfHeight, halfDepth = 0.6, 0.25, 0.07
    local vertices = {}
    local function vertex(x, y, z, u, v)
      return { x, y, z, u, v, 1 }
    end
    local function face(a, b, c, d)
      vertices[#vertices + 1] = a
      vertices[#vertices + 1] = b
      vertices[#vertices + 1] = c
      vertices[#vertices + 1] = a
      vertices[#vertices + 1] = c
      vertices[#vertices + 1] = d
    end
    local left, right = -halfWidth, halfWidth
    local bottom, top = -halfHeight, halfHeight
    local back, front = -halfDepth, halfDepth
    face(vertex(left, bottom, front, 0, 0), vertex(right, bottom, front, 1, 0),
         vertex(right, top, front, 1, 1), vertex(left, top, front, 0, 1))
    face(vertex(right, bottom, back, 0, 0), vertex(left, bottom, back, 1, 0),
         vertex(left, top, back, 1, 1), vertex(right, top, back, 0, 1))
    face(vertex(left, top, front, 0, 0), vertex(right, top, front, 1, 0),
         vertex(right, top, back, 1, 1), vertex(left, top, back, 0, 1))
    face(vertex(left, bottom, back, 0, 0), vertex(right, bottom, back, 1, 0),
         vertex(right, bottom, front, 1, 1), vertex(left, bottom, front, 0, 1))
    face(vertex(left, bottom, back, 0, 0), vertex(left, bottom, front, 1, 0),
         vertex(left, top, front, 1, 1), vertex(left, top, back, 0, 1))
    face(vertex(right, bottom, front, 0, 0), vertex(right, bottom, back, 1, 0),
         vertex(right, top, back, 1, 1), vertex(right, top, front, 0, 1))
    local ok, mesh = pcall(ctx.newMesh, vertices, nil)
    return ok and mesh or nil
  end

  local function createSkiMesh(ctx)
    local halfWidth, halfHeight, halfDepth = 0.48, 0.18, 17.5
    local vertices = {}
    local function vertex(x, y, z, u, v)
      return { x, y, z, u, v, 1 }
    end
    local function face(a, b, c, d)
      vertices[#vertices + 1] = a
      vertices[#vertices + 1] = b
      vertices[#vertices + 1] = c
      vertices[#vertices + 1] = a
      vertices[#vertices + 1] = c
      vertices[#vertices + 1] = d
    end
    local left, right = -halfWidth, halfWidth
    local bottom, top = -halfHeight, halfHeight
    local back, front = -halfDepth, halfDepth
    face(vertex(left, bottom, front, 0, 0), vertex(right, bottom, front, 1, 0),
         vertex(right, top, front, 1, 1), vertex(left, top, front, 0, 1))
    face(vertex(right, bottom, back, 0, 0), vertex(left, bottom, back, 1, 0),
         vertex(left, top, back, 1, 1), vertex(right, top, back, 0, 1))
    face(vertex(left, top, front, 0, 0), vertex(right, top, front, 1, 0),
         vertex(right, top, back, 1, 1), vertex(left, top, back, 0, 1))
    face(vertex(left, bottom, back, 0, 0), vertex(right, bottom, back, 1, 0),
         vertex(right, bottom, front, 1, 1), vertex(left, bottom, front, 0, 1))
    face(vertex(left, bottom, back, 0, 0), vertex(left, bottom, front, 1, 0),
         vertex(left, top, front, 1, 1), vertex(left, top, back, 0, 1))
    face(vertex(right, bottom, front, 0, 0), vertex(right, bottom, back, 1, 0),
         vertex(right, top, back, 1, 1), vertex(right, top, front, 0, 1))
    local ok, mesh = pcall(ctx.newMesh, vertices, nil)
    return ok and mesh or nil
  end

  local function createLaserMesh(ctx)
    local halfWidth, halfHeight, depth = 0.52, 0.32, 144
    local vertices = {}
    local function vertex(x, y, z, u, v)
      return { x, y, z, u, v, 1 }
    end
    local function face(a, b, c, d)
      vertices[#vertices + 1] = a
      vertices[#vertices + 1] = b
      vertices[#vertices + 1] = c
      vertices[#vertices + 1] = a
      vertices[#vertices + 1] = c
      vertices[#vertices + 1] = d
    end
    local left, right = -halfWidth, halfWidth
    local bottom, top = -halfHeight, halfHeight
    face(vertex(left, bottom, 0, 0, 0), vertex(right, bottom, 0, 1, 0),
         vertex(right, top, 0, 1, 1), vertex(left, top, 0, 0, 1))
    face(vertex(right, bottom, depth, 0, 0), vertex(left, bottom, depth, 1, 0),
         vertex(left, top, depth, 1, 1), vertex(right, top, depth, 0, 1))
    face(vertex(left, top, 0, 0, 0), vertex(right, top, 0, 1, 0),
         vertex(right, top, depth, 1, 1), vertex(left, top, depth, 0, 1))
    face(vertex(left, bottom, depth, 0, 0), vertex(right, bottom, depth, 1, 0),
         vertex(right, bottom, 0, 1, 1), vertex(left, bottom, 0, 0, 1))
    local ok, mesh = pcall(ctx.newMesh, vertices, nil)
    return ok and mesh or nil
  end

  local function selectedModel()
    local mode = optionValue("audio", "Original")
    if mode == "KR2008" and attackVisual() then
      return "KR2008Attack", MODEL_FILES.KR2008Attack
    end
    if mode == "Original" and karrEnabled() then
      return "OriginalKarr", MODEL_FILES.Original
    end
    return mode, MODEL_FILES[mode] or MODEL_FILES.Original
  end

  local function loadVoxelModel(ctx)
    local mode, path = selectedModel()
    local cached = voxelModels[mode]
    if cached then return cached end
    local raw = mod:read(path)
    local sourcePath = path
    if not raw and mode ~= "Original" then
      raw = mod:read(MODEL_FILES.Original)
      sourcePath = MODEL_FILES.Original
    end
    if not raw then
      voxelModels[mode] = { failure = sourcePath .. " is missing" }
      return nil
    end
    local ok, chunk = pcall(load, raw, "@" .. mod.path .. "/" .. sourcePath)
    if not ok or not chunk then
      voxelModels[mode] = { failure = tostring(chunk) }
      return nil
    end
    local dataOk, data = pcall(chunk)
    if not dataOk or type(data) ~= "table" then
      voxelModels[mode] = { failure = tostring(data) }
      return nil
    end
    local meshOk, mesh = pcall(ctx.newMesh, data.vertices, nil)
    if not meshOk or not mesh then
      voxelModels[mode] = { failure = "unable to create voxel mesh" }
      return nil
    end
    local meshes = { mesh }
    for _, vertices in ipairs(data.parts or {}) do
      local partOk, part = pcall(ctx.newMesh, vertices, nil)
      if partOk and part then meshes[#meshes + 1] = part end
    end
    local palettes = PALETTE_FILES[mode] or PALETTE_FILES.Original
    if type(palettes) == "string" then palettes = { palettes } end
    local textures = {}
    for _, palette in ipairs(palettes) do
      local textureOk, texture = pcall(love.graphics.newImage,
                                       mod.assets:path(palette))
      if textureOk and texture then
        pcall(texture.setFilter, texture, "nearest", "nearest")
        pcall(texture.setWrap, texture, "clamp", "clamp")
        textures[#textures + 1] = texture
      end
    end
    if #textures == 0 then
      voxelModels[mode] = { failure = "unable to create voxel texture" }
      return nil
    end
    local scannerLightTextures = {}
    if mode == "Original" or mode == "KR2008" or mode == "KR2008Attack"
        or mode == "OriginalKarr" then
      for name, files in pairs(SCANNER_LIGHT_FILES) do
        local texturesForScanner = {}
        for _, path in ipairs(files) do
          local textureOk, texture = pcall(love.graphics.newImage,
                                           mod.assets:path(path))
          if textureOk and texture then
            pcall(texture.setFilter, texture, "nearest", "nearest")
            pcall(texture.setWrap, texture, "clamp", "clamp")
            texturesForScanner[#texturesForScanner + 1] = texture
          end
        end
        if #texturesForScanner == #files then
          scannerLightTextures[name] = texturesForScanner
        end
      end
    end
    local wheels = {}
    for _, wheel in ipairs(data.wheels or {}) do
      local wheelOk, wheelMesh = pcall(ctx.newMesh, wheel.vertices, nil)
      if wheelOk and wheelMesh then
        wheels[#wheels + 1] = {
          center = wheel.center,
          mesh = wheelMesh,
          heightScale = (mode == "KR2008" or mode == "KR2008Attack") and 1.3767 or 1,
        }
      end
    end
    if mode == "KR2008" and #wheels == 0 then
      local wheelMesh = createWheelMesh(ctx)
      if wheelMesh then
        for _, center in ipairs({
          { -7.22063, 2.93237, 9.92484 },
          { -7.22063, 2.93237, -11.3816 },
          { 7.22063, 2.93237, 9.92484 },
          { 7.22063, 2.93237, -11.3816 },
        }) do
          wheels[#wheels + 1] = { center = center, mesh = wheelMesh }
        end
      end
    end
    local model = {
      mode = mode,
      mesh = mesh,
      meshes = meshes,
      texture = textures[1],
      scannerTextures = textures,
      scannerMesh = scannerLightTextures.KITT and createScannerMesh(ctx) or nil,
      laserMesh = scannerLightTextures.KITT and createLaserMesh(ctx) or nil,
      scannerLightTextures = scannerLightTextures,
      skiMesh = createSkiMesh(ctx),
      wheels = wheels,
      scannerFrame = nil,
      wheelAngle = 0,
      wheelClock = nil,
      wheelFrame = nil,
    }
    local laserTextureOk, laserTexture = pcall(love.graphics.newImage,
                                                mod.assets:path(LASER_TEXTURE_FILE))
    if laserTextureOk and laserTexture then
      pcall(laserTexture.setFilter, laserTexture, "nearest", "nearest")
      model.laserTexture = laserTexture
    end
    local skiTextureOk, skiTexture = pcall(love.graphics.newImage,
                                            mod.assets:path("assets/ski_palette.png"))
    if skiTextureOk and skiTexture then
      pcall(skiTexture.setFilter, skiTexture, "nearest", "nearest")
      pcall(skiTexture.setWrap, skiTexture, "clamp", "clamp")
      model.skiTexture = skiTexture
    end
    voxelModels[mode] = model
    return model
  end

  local function updateVoxelWheels(model, moving)
    if not (model and #model.wheels > 0 and love.timer
        and love.timer.getTime) then
      return
    end
    local now = love.timer.getTime()
    local frame = math.floor(now * 60)
    if frame == model.wheelFrame then return end
    if model.wheelClock and moving then
      model.wheelAngle = (model.wheelAngle
        + math.min(now - model.wheelClock, 0.1) * 18) % (2 * math.pi)
    end
    model.wheelClock = now
    model.wheelFrame = frame
  end

  local function updateVoxelScanner(model)
    if not (model and model.scannerTextures and #model.scannerTextures > 1
        and love.timer and love.timer.getTime) then
      return
    end
    local frame = math.floor(love.timer.getTime() * 4)
    if frame == model.scannerFrame then return end
    model.scannerFrame = frame
    model.texture = model.scannerTextures[frame % #model.scannerTextures + 1]
  end

  local function rotateZ(angle)
    local c, s = math.cos(angle), math.sin(angle)
    return { c, -s, 0, 0,
             s, c, 0, 0,
             0, 0, 1, 0,
             0, 0, 0, 1 }
  end

  local function skiTransform(m)
    if skiState.amount < 0.001 then return m.identity() end
    local pivotX, pivotY = -7.1, 2.5
    return m.mul(m.translate(pivotX, pivotY, 0),
      m.mul(rotateZ(skiState.amount * 1.18),
            m.translate(-pivotX, -pivotY, 0)))
  end

  local function voxelModelMatrix(ctx)
    local facing = ctx.bodyFacing or ctx.facing
    local yaw = ({
      down = 0,
      up = math.pi,
      right = math.pi / 2,
      left = -math.pi / 2,
    })[facing] or 0
    local m = ctx.mat4
    local player = Game.overworld and Game.overworld.player
    local progress = player == turbo.player and player.progress
      and math.max(0, math.min(1, player.progress / math.max(1, player.stepFramesCur or 1))) or 0
    local pitch = 0
    if player == turbo.player then
      if progress < 0.25 then
        pitch = -math.cos(progress * math.pi * 2) * 0.32
      elseif progress > 0.75 then
        pitch = math.sin((progress - 0.75) * math.pi * 2) * 0.32
      end
    end
    local _, scale, lift, spin = attackVisual()
    return m.mul(
      m.translate(ctx.px + 8, ctx.ground + ctx.lift + lift, ctx.py + 8),
      m.mul(m.rotateY(yaw + spin),
        m.mul(m.rotateX(pitch), m.mul(m.scale(scale, scale, scale), skiTransform(m)))))
  end

  local function voxelWheelMatrix(ctx, wheel)
    local m = ctx.mat4
    return m.mul(
      voxelModelMatrix(ctx),
      m.mul(m.translate(wheel.center[1], wheel.center[2], wheel.center[3]),
            m.mul(m.rotateX(wheel.angle or 0),
                  m.scale(1, wheel.heightScale or 1, 1))))
  end

  local function drawScannerSweep(ctx, model, matrix)
    if model.mode == "Original" or model.mode == "OriginalKarr" then return end
    local scannerName = karrEnabled()
        and (optionValue("audio", "Original") == "Original" and "KARR2000" or "KARR3000")
        or "KITT"
    local scannerTextures = model.scannerLightTextures[scannerName]
    if ctx.pass ~= "scene" or ctx.facing ~= "down" or not model.scannerMesh
        or not scannerTextures or #scannerTextures ~= 3 then
      return
    end
    local phase = 0
    if love.timer and love.timer.getTime then
      phase = math.floor(love.timer.getTime() * 4) % 4
    end
    local pairs = { { 3, 4 }, { 2, 5 }, { 1, 6 }, { 2, 5 } }
    local active = pairs[phase + 1]
    local segments = {
      { -3.2, 4.82, 18.15, -0.16 },
      { -2.0, 4.9, 18.42, -0.1 },
      { -0.7, 4.95, 18.58, -0.035 },
      { 0.7, 4.95, 18.58, 0.035 },
      { 2.0, 4.9, 18.42, 0.1 },
      { 3.2, 4.82, 18.15, 0.16 },
    }
    local m = ctx.mat4
    local flatten = ctx.voxel.flatten
    ctx.voxel.depth("always")
    for index, segment in ipairs(segments) do
      local distance = math.min(math.abs(index - active[1]),
                                math.abs(index - active[2]))
      local intensity = 3 - math.min(2, distance)
      local texture = scannerTextures[intensity]
      local scannerMatrix = m.mul(matrix,
          m.mul(m.translate(segment[1], segment[2], segment[3]),
                m.rotateY(segment[4])))
      if flatten then
        local colors = karrEnabled() and {
          KARR2000 = { { 0.16, 0.24, 0 }, { 0.5, 0.72, 0.01 }, { 0.86, 1, 0.08 } },
          KARR3000 = { { 0.48, 0.36, 0 }, { 0.84, 0.63, 0.01 }, { 1, 0.86, 0.1 } },
        } or { KITT = { { 0.38, 0.01, 0 }, { 0.75, 0.04, 0.005 }, { 1, 0.12, 0.01 } } }
        local glow = { colors[scannerName][intensity], ({ 0.9, 0.96, 1 })[intensity] }
        flatten(glow[1], glow[2])
      end
      ctx.draw(model.scannerMesh, texture, scannerMatrix, 0, scannerMatrix)
    end
    ctx.voxel.depth("test")
    if flatten then flatten() end
  end

  local function drawSkiRails(ctx, model, matrix)
    if skiState.amount < 0.02 or not model.skiMesh or not model.skiTexture then
      return
    end
    local m = ctx.mat4
    for _, x in ipairs({ -5.7, 5.7 }) do
      local railMatrix = m.mul(matrix,
        m.mul(m.translate(x, -2.3, 0), m.scale(1, 1, skiState.amount)))
      if ctx.pass == "shadow" then
        ctx.shadow(model.skiMesh, model.skiTexture, railMatrix)
      else
        ctx.draw(model.skiMesh, model.skiTexture, railMatrix,
                 ctx.pass == "ghost" and 0 or ctx.pull, railMatrix)
      end
    end
  end

  local function drawLaserBeam(ctx, model, matrix)
    if ctx.pass ~= "scene" or not laserState.active or not model.laserMesh then return end
    local texture = model.laserTexture
    if not texture then return end
    local m = ctx.mat4
    local originY, originZ = 4.95, 18.64
    if model.mode == "Original" or model.mode == "OriginalKarr" then
      originY, originZ = 6, 17.5
    end
    local beamMatrix = m.mul(matrix,
      m.translate(0, originY, originZ))
    pcall(model.laserMesh.setTexture, model.laserMesh, texture)
    local flatten = ctx.voxel.flatten
    ctx.voxel.depth("always")
    local outerMatrix = m.mul(beamMatrix, m.scale(2.1, 2.1, 1))
    if flatten then flatten({ 0.95, 0.015, 0.005 }, 1) end
    ctx.draw(model.laserMesh, texture, outerMatrix, 0, outerMatrix)
    local coreMatrix = m.mul(beamMatrix, m.scale(0.6, 0.6, 1))
    if flatten then flatten({ 1, 0.72, 0.5 }, 1) end
    ctx.draw(model.laserMesh, texture, coreMatrix, 0, coreMatrix)
    ctx.voxel.depth("test")
    if flatten then flatten() end
  end

  local drawExplosions

  local function drawVoxelModel(ctx)
    if not (ctx.sprite and ctx.sprite.__gen1KrKitt) then
      return false
    end
    local model = loadVoxelModel(ctx)
    if not model then return false end
    updateVoxelScanner(model)
    updateVoxelWheels(model, ctx.moving)
    local matrix = voxelModelMatrix(ctx)
    for _, mesh in ipairs(model.meshes or { model.mesh }) do
      pcall(mesh.setTexture, mesh, model.texture)
      if ctx.pass == "shadow" then
        ctx.shadow(mesh, model.texture, matrix)
      else
        ctx.draw(mesh, model.texture, matrix,
                 ctx.pass == "ghost" and 0 or ctx.pull, matrix)
      end
    end
    for _, wheel in ipairs(model.wheels or {}) do
      wheel.angle = model.wheelAngle
      local wheelModel = voxelWheelMatrix(ctx, wheel)
      pcall(wheel.mesh.setTexture, wheel.mesh, model.texture)
      if ctx.pass == "shadow" then
        ctx.shadow(wheel.mesh, model.texture, wheelModel)
      else
        ctx.draw(wheel.mesh, model.texture, wheelModel,
                 ctx.pass == "ghost" and 0 or ctx.pull, wheelModel)
      end
    end
    drawScannerSweep(ctx, model, matrix)
    drawLaserBeam(ctx, model, matrix)
    if ctx.pass == "scene" and drawExplosions then drawExplosions(ctx) end
    return true
  end

  local vanillaPose = Player.__gen1KrVanillaPose or Player.pose
  Player.__gen1KrVanillaPose = vanillaPose
  local vanillaUpdate = Player.__gen1KrVanillaUpdate or Player.update
  Player.__gen1KrVanillaUpdate = vanillaUpdate
  local kittSprites = setmetatable({}, { __mode = "k" })
  turbo = {
    player = nil,
    overworld = nil,
    map = nil,
    direction = nil,
    distance = 0,
    request = nil,
  }
  local clearTurbo
  local requestObjectCollision
  local objectCrashKey
  local function isOutdoorKittVisible(player)
    local overworld = Game.overworld
    return kittVisible() and overworld and overworld.player == player and overworld.map
       and Map.isOutdoor(overworld.map.def)
       and not player.surfing and not player.fishing
  end

  local function isOutdoorPlayer(player)
    return kittEnabled() and isOutdoorKittVisible(player)
  end

  mod.hooks:wrap("movement.speed", function(next, frames, ctx)
    local value = next(frames, ctx)
    if ctx and ctx.player and isOutdoorPlayer(ctx.player) then
      return math.max(1, math.floor(value * vehicleSpeed()))
    end
    return value
  end, 1000)

  mod.hooks:wrap("movement.collision", function(next, allowed, ctx)
    local result = next(allowed, ctx)
    local player = ctx and ctx.mover
    local map = ctx and ctx.map
    if not (player and map and isOutdoorPlayer(player)) then return result end
    if result then objectCrashKey = nil end
    if player.__gen1KrTerrainRecovery then
      if map:isWaterCell(ctx.toX, ctx.toY) then return false end
      if map:isWalkableCell(ctx.toX, ctx.toY) then
        player.__gen1KrTerrainRecovery = nil
      end
      if ctx.reason == "tile" then return true end
      return result
    end
    if not result then
      if ctx.reason == "tile" and requestObjectCollision then requestObjectCollision(ctx) end
      return false
    end
    return true
  end, 1000)

  local function kittSprite(player, baseSprite)
    local sprite = kittSprites[player]
    if sprite then return sprite end
    local def = baseSprite and baseSprite.def
    if not def then return nil end
    sprite = SpriteRenderer.new(def, MOD_ID)
    sprite.__gen1KrKitt = true
    kittSprites[player] = sprite
    return sprite
  end

  local externalVoxelInstalled = false
  local rawShadowDraw

  local function kittSpriteDef(sprite)
    return sprite and sprite.__gen1KrKitt
  end

  local function externalContext(pass, sprite, px, py, facing, phase, flip,
                                 ground, colors, lift, moving)
    local player = Game.overworld and Game.overworld.player
    local bodyFacing = kittSpriteDef(sprite) and player and player.facing or facing
    local angle = VoxelState and VoxelState.angle or 0.05
    return {
      pass = pass,
      sprite = sprite,
      def = sprite and sprite.def,
      px = px,
      py = py,
      facing = facing,
      bodyFacing = bodyFacing or facing,
      phase = phase,
      flip = flip,
      ground = ground or 0,
      colors = colors,
      lift = lift or 0,
      moving = moving and true or false,
      voxel = Voxel3D,
      mat4 = Mat4,
      newMesh = Voxel3D.newMesh,
      draw = Voxel3D.draw,
      shadow = rawShadowDraw or ShadowMap.draw,
      pull = VoxelScene.pull(math.max(angle or 0.05, 0.05)),
    }
  end

  local function replaceUpvalue(callback, name, value)
    if not (debug and debug.getupvalue and debug.setupvalue) then return nil end
    for index = 1, math.huge do
      local current, previous = debug.getupvalue(callback, index)
      if not current then return nil end
      if current == name then
        debug.setupvalue(callback, index, value)
        return previous
      end
    end
  end

  local function findUpvalue(callback, name)
    if not (debug and debug.getupvalue) then return nil end
    for index = 1, math.huge do
      local current, value = debug.getupvalue(callback, index)
      if not current then return nil end
      if current == name then return value end
    end
  end

  local originalDrawEntity
  local originalDrawGhost
  local originalDrawShadow

  local function drawExternalEntity(sprite, px, py, facing, phase, flip, ground,
                                    colors, lift)
    if kittVisible() and kittSpriteDef(sprite) then
      local player = Game.overworld and Game.overworld.player
      local context = externalContext("scene", sprite, px, py, facing, phase,
        flip, ground, colors, lift, player and player.moving)
      if drawVoxelModel(context) then return true end
    end
    return originalDrawEntity(sprite, px, py, facing, phase, flip, ground,
                              colors, lift)
  end

  local function drawExternalGhost(pose)
    if kittVisible() and kittSpriteDef(pose and pose.sprite) then return end
    return originalDrawGhost(pose)
  end

  local function drawExternalShadow(sprite, px, py, facing, phase, flip, ground,
                                     lift)
    if kittVisible() and kittSpriteDef(sprite) then
      local player = Game.overworld and Game.overworld.player
      local context = externalContext("shadow", sprite, px, py, facing, phase,
        flip, ground, nil, lift, player and player.moving)
      if drawVoxelModel(context) then return end
    end
    return originalDrawShadow(sprite, px, py, facing, phase, flip, ground, lift)
  end

  local function drawExternalModelShadow(mesh, texture, model)
    local overworld = Game.overworld
    local player = overworld and overworld.player
    local sprite = player and kittSprites[player]
    if player and isOutdoorKittVisible(player) and sprite
        and texture == sprite:resolveImage() then
      local ground = VoxelScene.groundAt(overworld.map, player.cellX, player.cellY)
      local context = externalContext("shadow", sprite, player.px, player.py,
        player.facing, 0, false, ground, nil, 0, player.moving)
      if drawVoxelModel(context) then return end
    end
    return rawShadowDraw(mesh, texture, model)
  end

  local function installExternalVoxel()
    if externalVoxelInstalled then return true end
    if not loadExternalVoxel() then return false end
    local drawCast = findUpvalue(VoxelScene.render, "drawCast")
    originalDrawEntity = drawCast and replaceUpvalue(drawCast, "drawEntity",
      drawExternalEntity)
    originalDrawGhost = replaceUpvalue(VoxelScene.render, "drawGhost",
      drawExternalGhost)
    originalDrawShadow = replaceUpvalue(VoxelScene.render, "drawShadow",
      drawExternalShadow)
    if not (originalDrawEntity and originalDrawGhost and originalDrawShadow) then
      mod.log:warn("Dramatic Shape render hooks are unavailable")
      return false
    end
    rawShadowDraw = ShadowMap.draw
    ShadowMap.draw = drawExternalModelShadow
    externalVoxelInstalled = true
    return true
  end

  mod.events:on("mods.loaded", installExternalVoxel)
  installExternalVoxel()

  Player.pose = function(self)
    local sprite, px, py, facing, phase, flip, hopping = vanillaPose(self)
    if isOutdoorKittVisible(self) then
      if turbo.player == self then
        local progress = math.max(0, math.min(1,
          (self.progress or 0) / math.max(1, self.stepFramesCur or 1)))
        py = py - math.floor(math.sin(math.pi * progress) * 12)
        hopping = true
      end
      local replacement = kittSprite(self, sprite)
      if replacement then
        return replacement, px, py, facing, phase, flip, hopping
      end
    end
    return sprite, px, py, facing, phase, flip, hopping
  end

  Player.update = function(self)
    if turbo.player == self and self.moving then
      self.stepLanded = false
      if self.hopFrames and self.hopFrames > 0 then
        self.hopFrames = self.hopFrames - 1
      end
      self.progress = self.progress + 1
      self.animClock = (self.animClock or 0) + 1
      local stepLength = self.stepFramesCur or 1
      local delta = Collision.DELTA[self.facing]
      local pixels = math.floor(self.progress * turbo.distance / stepLength)
      self.px = (turbo.originX or self.cellX * 16) + delta[1] * pixels
      self.py = (turbo.originY or self.cellY * 16) + delta[2] * pixels
      if self.progress < stepLength then return false end
      self.cellX, self.cellY = self.targetX, self.targetY
      self.targetX, self.targetY = nil, nil
      self.px, self.py = self.cellX * 16, self.cellY * 16
      self.moving = false
      self.stepFlip = not self.stepFlip
      self.stepLanded = true
      local landedMap = turbo.map
      self.__gen1KrTerrainRecovery = landedMap
          and not landedMap:isWaterCell(self.cellX, self.cellY)
          and not landedMap:isWalkableCell(self.cellX, self.cellY) or nil
      clearTurbo()
      return true
    end
    local landed = vanillaUpdate(self)
    return landed
  end

  local sourceFailures = {}
  local engineSource
  local scannerSource
  local scannerSources = {}
  local wilhelmSource
  local crashSource
  local crashTarget
  local crashDirection
  local crashCollided
  local turboSource
  local laserSource
  local activeTurboSources = {}
  local skiSource
  local attackTransformSource
  local powerUpSource
  local powerDownSource
  local powerDownDeadline
  local voiceSources = {}
  local voiceSource
  local lastVoiceFiles = {}
  local nextVoiceAt
  local skiRequest
  local wilhelmDelay
  local flyingNpcs = setmetatable({}, { __mode = "k" })
  local collisionCooldown = setmetatable({}, { __mode = "k" })
  local explosions = {}
  mod.exports.collision.activeBursts = function() return #explosions end
  local explosionMesh
  local explosionTexture

  local function explosionResources(ctx)
    if explosionMesh or explosionTexture then
      return explosionMesh, explosionTexture
    end
    if not (ctx and ctx.newMesh and love and love.graphics
        and love.graphics.newImage) then
      return nil
    end
    local vertices = {}
    local faces = {
      { { -0.5, -0.5, -0.5, 0, 0, 0.9 }, { 0.5, -0.5, -0.5, 1, 0, 0.9 },
        { 0.5, 0.5, -0.5, 1, 1, 0.9 }, { -0.5, 0.5, -0.5, 0, 1, 0.9 } },
      { { 0.5, -0.5, 0.5, 0, 0, 0.7 }, { -0.5, -0.5, 0.5, 1, 0, 0.7 },
        { -0.5, 0.5, 0.5, 1, 1, 0.7 }, { 0.5, 0.5, 0.5, 0, 1, 0.7 } },
      { { -0.5, 0.5, -0.5, 0, 0, 1 }, { 0.5, 0.5, -0.5, 1, 0, 1 },
        { 0.5, 0.5, 0.5, 1, 1, 1 }, { -0.5, 0.5, 0.5, 0, 1, 1 } },
      { { -0.5, -0.5, 0.5, 0, 0, 0.55 }, { 0.5, -0.5, 0.5, 1, 0, 0.55 },
        { 0.5, -0.5, -0.5, 1, 1, 0.55 }, { -0.5, -0.5, -0.5, 0, 1, 0.55 } },
      { { -0.5, -0.5, 0.5, 0, 0, 0.8 }, { -0.5, -0.5, -0.5, 1, 0, 0.8 },
        { -0.5, 0.5, -0.5, 1, 1, 0.8 }, { -0.5, 0.5, 0.5, 0, 1, 0.8 } },
      { { 0.5, -0.5, -0.5, 0, 0, 0.75 }, { 0.5, -0.5, 0.5, 1, 0, 0.75 },
        { 0.5, 0.5, 0.5, 1, 1, 0.75 }, { 0.5, 0.5, -0.5, 0, 1, 0.75 } },
    }
    for _, face in ipairs(faces) do
      for _, index in ipairs({ 1, 2, 3, 1, 3, 4 }) do
        vertices[#vertices + 1] = face[index]
      end
    end
    local meshOk, mesh = pcall(ctx.newMesh, vertices, nil)
    if not meshOk or not mesh then return nil end
    local textureOk, texture = pcall(love.graphics.newImage,
                                     mod.assets:path("assets/impact_palette.png"))
    if not textureOk or not texture then return nil end
    pcall(texture.setFilter, texture, "nearest", "nearest")
    pcall(texture.setWrap, texture, "clamp", "clamp")
    pcall(mesh.setTexture, mesh, texture)
    explosionMesh, explosionTexture = mesh, texture
    return explosionMesh, explosionTexture
  end

  drawExplosions = function(ctx)
    local mesh, texture = explosionResources(ctx)
    if not mesh then return end
    ctx.voxel.depth("always")
    local m = ctx.mat4
    for _, burst in ipairs(explosions) do
      for _, particle in ipairs(burst.particles) do
        local model = m.mul(
          m.translate(particle.x, particle.y, particle.z),
          m.mul(m.rotateY(particle.ry),
                m.mul(m.rotateX(particle.rx), m.scale(particle.size,
                                                        particle.size,
                                                        particle.size))))
        ctx.draw(mesh, texture, model, ctx.pull, model)
      end
    end
    ctx.voxel.depth("test")
  end

  local function updateExplosions(step)
    for index = #explosions, 1, -1 do
      local burst = explosions[index]
      burst.age = burst.age + step
      if burst.age >= burst.life then
        table.remove(explosions, index)
      else
        for _, particle in ipairs(burst.particles) do
          particle.vy = particle.vy - 360 * step
          particle.x = particle.x + particle.vx * step
          particle.y = particle.y + particle.vy * step
          particle.z = particle.z + particle.vz * step
          particle.rx = particle.rx + particle.vrx * step
          particle.ry = particle.ry + particle.vry * step
        end
      end
    end
  end

  local function spawnExplosionAt(overworld, cellX, cellY, px, py)
    local ground = 0
    if VoxelScene and VoxelScene.groundAt and overworld.map then
      ground = VoxelScene.groundAt(overworld.map, cellX, cellY)
    end
    local particles = {}
    local count = mod.exports.collision.burstCount
    for index = 1, count do
      local angle = index / count * math.pi * 2
      local speed = 34 + (index % 4) * 10
      particles[#particles + 1] = {
        x = px + 8,
        y = ground + 4,
        z = py + 8,
        vx = math.cos(angle) * speed,
        vy = 130 + (index % 5) * 24,
        vz = math.sin(angle) * speed,
        vrx = 4 + index % 3,
        vry = 5 + index % 4,
        rx = index,
        ry = index * 0.7,
        size = 0.9 + (index % 5) * 0.16,
      }
    end
    explosions[#explosions + 1] = {
      age = 0,
      life = 0.85,
      particles = particles,
    }
  end

  local function spawnExplosion(overworld, npc)
    spawnExplosionAt(overworld, npc.cellX, npc.cellY, npc.px, npc.py)
  end

  local function removeNpc(overworld, npc)
    for _, list in ipairs({ overworld.npcs, overworld.entities }) do
      if list then
        for index = #list, 1, -1 do
          if list[index] == npc then table.remove(list, index) end
        end
      end
    end
  end

  local function restoreNpc(state)
    local overworld = state.overworld
    if not overworld or Game.overworld ~= overworld or overworld.map ~= state.map then
      return
    end
    local npc = state.npc
    npc.cellX, npc.cellY = state.cellX, state.cellY
    npc.px, npc.py = state.baseX, state.baseY
    npc.frozen = state.oldFrozen
    npc.passable = state.oldPassable
    npc.moving = state.oldMoving
    overworld.npcs = overworld.npcs or {}
    overworld.entities = overworld.entities or {}
    local present = false
    for _, candidate in ipairs(overworld.npcs or {}) do
      if candidate == npc then present = true break end
    end
    if not present then table.insert(overworld.npcs, npc) end
    present = false
    for _, candidate in ipairs(overworld.entities or {}) do
      if candidate == npc then present = true break end
    end
    if not present then table.insert(overworld.entities, npc) end
  end

  local function source(relative, kind)
    if sourceFailures[relative] or not love or not love.audio then return nil end
    local path = mod.path .. "/" .. relative
    if not hasFile(relative) then
      sourceFailures[relative] = true
      return nil
    end
    local ok, result = pcall(love.audio.newSource, path, kind)
    if not ok or not result then
      sourceFailures[relative] = true
      mod.log:warn("unable to load %s: %s", relative, tostring(result))
      return nil
    end
    return result
  end

  local function stopVoice()
    if voiceSource then pcall(voiceSource.stop, voiceSource) end
    if love.timer and love.timer.getTime then
      nextVoiceAt = love.timer.getTime() + 25 + math.random() * 20
    end
  end

  local function mapOverworld()
    local stack = Game.stack
    local overworld = Game.overworld
    if not (stack and overworld and overworld.map and overworld.player) then
      return nil
    end
    for _, state in ipairs(stack.states or {}) do
      if state and state.isWideBattleLayout then return nil end
    end
    if not Map.isOutdoor(overworld.map.def) then
      return nil
    end
    if overworld.player.surfing then return nil end
    return overworld
  end

  local function liveOverworld()
    local overworld = mapOverworld()
    if not overworld or Game.stack:top() ~= overworld then return nil end
    return overworld
  end

  local function stopEngine()
    if engineSource then
      pcall(engineSource.stop, engineSource)
      engineSource = nil
    end
  end

  local function selectedEngineFile()
    local mode = optionValue("audio", "Original")
    return ENGINE_FILES[mode] or ENGINE_FILES.Original
  end

  local function updateEngine()
    local overworld = mapOverworld()
    if not (kittEnabled() and overworld and overworld.player.moving) then
      stopEngine()
      return
    end
    if not engineSource then
      engineSource = source(selectedEngineFile(), "stream")
      if engineSource then
        pcall(engineSource.setLooping, engineSource, true)
        pcall(engineSource.setVolume, engineSource, 1)
      end
    end
    if engineSource then
      local ok, playing = pcall(engineSource.isPlaying, engineSource)
      if not ok or not playing then pcall(engineSource.play, engineSource) end
    end
  end

  local function playVoice(kind)
    if not (kittEnabled() and liveOverworld()) or attackState.transition or karrEnabled() then
      return false
    end
    if voiceSource then
      local ok, playing = pcall(voiceSource.isPlaying, voiceSource)
      if ok and playing then return false end
    end
    local mode = optionValue("audio", "Original")
    local file = VOICE_FILES[mode] and VOICE_FILES[mode][kind]
    if type(file) == "table" then
      local choices = {}
      local last = lastVoiceFiles[mode .. ":" .. kind]
      for _, candidate in ipairs(file) do
        if candidate ~= last then choices[#choices + 1] = candidate end
      end
      file = choices[math.random(#choices)]
      lastVoiceFiles[mode .. ":" .. kind] = file
    end
    if not file then return false end
    local voice = voiceSources[file]
    if voice == nil then
      voice = source(file, "static") or false
      voiceSources[file] = voice
    end
    if not voice then return false end
    voiceSource = voice
    pcall(voiceSource.stop, voiceSource)
    pcall(voiceSource.setVolume, voiceSource, 1)
    pcall(voiceSource.play, voiceSource)
    return true
  end

  local function scheduleVoice(now)
    nextVoiceAt = now + 35 + math.random() * 35
  end

  local function updateVoiceChatter()
    if not kittEnabled() then
      nextVoiceAt = nil
      return
    end
    if attackState.transition then return end
    local overworld = liveOverworld()
    if not overworld then return end
    local now = love.timer and love.timer.getTime and love.timer.getTime() or 0
    if not nextVoiceAt then
      scheduleVoice(now)
      return
    end
    if now >= nextVoiceAt then
      playVoice("nominal")
      scheduleVoice(now)
    end
  end

  local function playScanner()
    if not (kittEnabled() and liveOverworld()) then return end
    stopVoice()
    local file = karrEnabled() and KARR_SCANNER_FILE or SCANNER_FILE
    local selected = scannerSources[file]
    if selected == nil then
      selected = source(file, "static") or false
      scannerSources[file] = selected
    end
    if scannerSource and scannerSource ~= selected then
      pcall(scannerSource.stop, scannerSource)
    end
    scannerSource = selected
    if scannerSource then
      pcall(scannerSource.stop, scannerSource)
      pcall(scannerSource.play, scannerSource)
    end
  end

  local function playWilhelm()
    if not (kittEnabled() and liveOverworld()) then return end
    wilhelmSource = wilhelmSource or source(WILHELM_FILE, "static")
    if wilhelmSource then
      pcall(wilhelmSource.stop, wilhelmSource)
      pcall(wilhelmSource.play, wilhelmSource)
    end
  end

  local function crashPlaying()
    if not crashSource then return false end
    local ok, playing = pcall(crashSource.isPlaying, crashSource)
    return ok and playing
  end

  local function stopCrash()
    if crashSource then pcall(crashSource.stop, crashSource) end
    crashTarget = nil
    crashDirection = nil
    crashCollided = nil
  end

  local function playCrash(npc, direction, timeToImpact, interruptVoice)
    if not (kittEnabled() and liveOverworld())
        or not optionValue("impactCollision", true) then
      return false
    end
    crashSource = crashSource or source(CRASH_FILE, "static")
    if not crashSource then return false end
    if interruptVoice then stopVoice() end
    pcall(crashSource.stop, crashSource)
    local offset = CRASH_IMPACT_OFFSET
    if timeToImpact and timeToImpact > 0 then
      offset = math.max(0, CRASH_IMPACT_OFFSET - timeToImpact)
    end
    pcall(crashSource.seek, crashSource, offset)
    pcall(crashSource.setVolume, crashSource, 1)
    pcall(crashSource.play, crashSource)
    crashTarget = npc or false
    crashDirection = direction
    crashCollided = false
    return true
  end

  local function markCrashCollision(npc, direction)
    if crashTarget ~= npc or crashDirection ~= direction or not crashPlaying() then
      playCrash(npc, direction, 0, true)
    end
    if crashTarget == npc and crashDirection == direction then
      crashCollided = true
    end
  end

  local function playCollisionVoice()
    if math.random() < 0.35 then playVoice("collision") end
  end

  local objectVoiceAt = 0
  requestObjectCollision = function(ctx)
    local now = love.timer and love.timer.getTime and love.timer.getTime() or 0
    local key = table.concat({ ctx.toX or "", ctx.toY or "", ctx.dir or "" }, ":")
    if objectCrashKey ~= key then
      objectCrashKey = key
      playCrash(false, ctx.dir, 0, false)
    end
    if now >= objectVoiceAt then
      objectVoiceAt = now + 4
      playCollisionVoice()
    end
  end

  local function playTurbo()
    if not (kittEnabled() and liveOverworld()) then return end
    turboSource = turboSource or source(TURBO_FILE, "static")
    if not turboSource then return end
    local ok, effect = pcall(turboSource.clone, turboSource)
    if not ok or not effect then return end
    pcall(effect.setVolume, effect, 1)
    pcall(effect.play, effect)
    activeTurboSources[#activeTurboSources + 1] = effect
  end

  local function updateLaserAudio(active)
    if not active then
      if laserSource then pcall(laserSource.stop, laserSource) end
      return
    end
    laserSource = laserSource or source(LASER_FILE, "static")
    if not laserSource then return end
    pcall(laserSource.setLooping, laserSource, true)
    pcall(laserSource.setVolume, laserSource, 1)
    local ok, playing = pcall(laserSource.isPlaying, laserSource)
    if not ok or not playing then pcall(laserSource.play, laserSource) end
  end

  local function updateTurboAudio()
    for index = #activeTurboSources, 1, -1 do
      local effect = activeTurboSources[index]
      local ok, playing = pcall(effect.isPlaying, effect)
      if not ok or not playing then table.remove(activeTurboSources, index) end
    end
  end

  local function playSki()
    if not (kittEnabled() and liveOverworld()) then return end
    stopVoice()
    skiSource = skiSource or source(SKI_FILE, "static")
    if skiSource then
      pcall(skiSource.stop, skiSource)
      pcall(skiSource.setVolume, skiSource, 1)
      pcall(skiSource.play, skiSource)
    end
  end

  local function playAttackTransform()
    stopVoice()
    attackTransformSource = attackTransformSource or source(ATTACK_TRANSFORM_FILE, "static")
    if attackTransformSource then
      pcall(attackTransformSource.stop, attackTransformSource)
      pcall(attackTransformSource.play, attackTransformSource)
    end
  end

  local function playPowerUp()
    if optionValue("audio", "Original") ~= "Original" then return end
    stopVoice()
    powerUpSource = powerUpSource or source(POWER_UP_FILE, "static")
    if powerUpSource then
      pcall(powerUpSource.stop, powerUpSource)
      pcall(powerUpSource.play, powerUpSource)
    end
  end

  local function playPowerDown()
    if optionValue("audio", "Original") ~= "Original" then
      powerDownVisible = false
      return false
    end
    stopVoice()
    powerDownSource = powerDownSource or source(POWER_DOWN_FILE, "static")
    if not powerDownSource then
      powerDownVisible = false
      return false
    end
    powerDownVisible = true
    local now = love.timer and love.timer.getTime and love.timer.getTime() or 0
    powerDownDeadline = now + POWER_DOWN_DURATION
    pcall(powerDownSource.stop, powerDownSource)
    pcall(powerDownSource.play, powerDownSource)
    return true
  end

  local function updatePowerDown()
    if not powerDownVisible then return end
    local now = love.timer and love.timer.getTime and love.timer.getTime()
    if now and powerDownDeadline and now < powerDownDeadline then return end
    local ok, playing = powerDownSource and pcall(powerDownSource.isPlaying,
                                                    powerDownSource)
    if ok and playing then return end
    powerDownVisible = false
    powerDownDeadline = nil
    local overworld = mapOverworld()
    if overworld then
      Music.playMap(Game.data, overworld.map.id, Game.save.onBike,
                    overworld.player.surfing)
    end
  end

  local function requestSkiMode(game)
    if not kittEnabled() then return false end
    if skiRequest then return false end
    playSki()
    skiRequest = { game = game, remaining = SKI_ACTIVATION_DELAY }
    return true
  end

  local function updateSkiRequest(dt)
    if not skiRequest then return end
    skiRequest.remaining = skiRequest.remaining - (dt or 1 / 60)
    if skiRequest.remaining > 0 then return end
    local game = skiRequest.game
    skiRequest = nil
    setOption(game, "skiMode", not optionValue("skiMode", false))
  end

  requestAttackMode = function(game)
    if not attackAvailable() or attackState.transition then return false end
    local now = love.timer and love.timer.getTime and love.timer.getTime() or 0
    setOption(game, "skiMode", false)
    stopVoice()
    attackState.transition = {
      from = optionValue("attackMode", false),
      target = not optionValue("attackMode", false),
      started = now,
      duration = ATTACK_TRANSFORM_DURATION,
    }
    playAttackTransform()
    return true
  end

  local function updateAttackMode(game)
    local transition = attackState.transition
    if not transition then return end
    local now = love.timer and love.timer.getTime and love.timer.getTime() or transition.started
    if now - transition.started < transition.duration then return end
    attackState.transition = nil
    setOption(game, "attackMode", transition.target)
  end

  clearTurbo = function()
    turbo.player = nil
    turbo.overworld = nil
    turbo.map = nil
    turbo.direction = nil
    turbo.distance = 0
    turbo.originX = nil
    turbo.originY = nil
    turbo.request = nil
  end

  local function turboDirection(input, player)
    for _, direction in ipairs({ "up", "down", "left", "right" }) do
      if input and input:isDown(direction) then return direction end
    end
    return player.facing
  end

  local function requestTurbo(input)
    if not kittEnabled() then return end
    local overworld = liveOverworld()
    local player = overworld and overworld.player
    if not player or turbo.player then return end
    turbo.request = {
      overworld = overworld,
      map = overworld.map,
      direction = turboDirection(input, player),
      remaining = TURBO_ACTIVATION_DELAY,
    }
    playTurbo()
  end

  local function startTurbo(dt)
    if not kittEnabled() then
      clearTurbo()
      return false
    end
    local request = turbo.request
    if not request then return false end
    request.remaining = (request.remaining or 0) - (dt or 1 / 60)
    if request.remaining > 0 then return false end
    local overworld = liveOverworld()
    local player = overworld and overworld.player
    if not player or turbo.player then
      turbo.request = nil
      return false
    end
    if overworld ~= request.overworld or overworld.map ~= request.map then
      turbo.request = nil
      return false
    end
    if player.inputLocked then return false end
    local direction = request.direction
    if not direction then turbo.request = nil return false end
    player.facing = direction
    player.turnTimer = 0
    local delta = Collision.DELTA[direction]
    local originX, originY = player.px, player.py
    local distance = TURBO_DISTANCE
    local targetX = math.floor((originX + delta[1] * distance + 8) / 16)
    local targetY = math.floor((originY + delta[2] * distance + 8) / 16)
    if not overworld.map:inBounds(targetX, targetY) then
      turbo.request = nil
      return false
    end
    turbo.player = player
    turbo.overworld = overworld
    turbo.map = overworld.map
    turbo.direction = direction
    turbo.distance = distance
    turbo.originX = originX
    turbo.originY = originY
    turbo.request = nil
    player.targetX, player.targetY = targetX, targetY
    player.moving = true
    player.progress = 0
    player.stepFramesCur = TURBO_HOP_FRAMES
    player.hopFrames, player.hopTotal = TURBO_HOP_FRAMES, TURBO_HOP_FRAMES
    return true
  end

  local function targetPoint(px, py, direction)
    local dx = direction == "right" and 1 or direction == "left" and -1 or 0
    local dy = direction == "down" and 1 or direction == "up" and -1 or 0
    return px + dx * 16, py + dy * 16
  end

  local function collisionOffset(player, npc, direction)
    local dx = direction == "right" and 1 or direction == "left" and -1 or 0
    local dy = direction == "down" and 1 or direction == "up" and -1 or 0
    local offsetX = npc.px - player.px
    local offsetY = npc.py - player.py
    local forward = offsetX * dx + offsetY * dy
    local lateral = math.abs(offsetX * dy - offsetY * dx)
    return forward, lateral
  end

  local function collisionHit(player, npc, direction)
    local forward, lateral = collisionOffset(player, npc, direction)
    return forward >= -8 and forward <= COLLISION_RADIUS
       and lateral <= COLLISION_HALF_WIDTH
  end

  local function playerSpeed(player)
    local frames = math.max(1, player.stepFramesCur or 16)
    local distance = turbo.player == player and turbo.distance or 16
    return distance * 60 / frames
  end

  local function updateCrashPreRoll(overworld, player, directions)
    if crashCollided then
      if not crashPlaying() then stopCrash() end
      return
    end
    if not player.moving then
      if crashTarget ~= false then stopCrash() end
      return
    end
    local speed = playerSpeed(player)
    local lead = COLLISION_RADIUS + speed * CRASH_PRE_ROLL
    local target, direction, timeToImpact
    for facing in pairs(directions) do
      for _, npc in ipairs(overworld.npcs or {}) do
        if not flyingNpcs[npc] then
          local forward, lateral = collisionOffset(player, npc, facing)
          if lateral <= COLLISION_HALF_WIDTH and forward > COLLISION_RADIUS
              and forward <= lead then
            local candidate = (forward - COLLISION_RADIUS) / speed
            if not timeToImpact or candidate < timeToImpact then
              target, direction, timeToImpact = npc, facing, candidate
            end
          end
        end
      end
    end
    if not target then
      if crashTarget ~= false then stopCrash() end
      return
    end
    if crashTarget ~= target or crashDirection ~= direction or not crashPlaying() then
      playCrash(target, direction, timeToImpact, false)
    end
  end

  local function launchNpc(npc, direction)
    if flyingNpcs[npc] or (collisionCooldown[npc] or 0) > 0 then return end
    local overworld = liveOverworld()
    if not overworld then return end
    local dx = direction == "right" and 1 or direction == "left" and -1 or 0
    local dy = direction == "down" and 1 or direction == "up" and -1 or 0
    local state = {
      baseX = npc.px,
      baseY = npc.py,
      x = npc.px,
      y = npc.py,
      vx = dx * mod.exports.collision.horizontalSpeed,
      vy = dy * 420 - mod.exports.collision.verticalSpeed,
      age = 0,
      oldFrozen = npc.frozen,
      oldPassable = npc.passable,
      oldMoving = npc.moving,
      cellX = npc.cellX,
      cellY = npc.cellY,
      npc = npc,
      overworld = overworld,
      map = overworld.map,
    }
    npc.frozen = true
    npc.passable = true
    npc.moving = false
    flyingNpcs[npc] = state
    collisionCooldown[npc] = math.ceil(mod.exports.collision.respawnDelay * 60)
    removeNpc(overworld, npc)
    spawnExplosion(overworld, npc)
    pcall(require("src.core.Sound").play, Game.data, "Collision")
    markCrashCollision(npc, direction)
    playCollisionVoice()
    wilhelmDelay = 0.42
  end

  local function updateLaser()
    local overworld = liveOverworld()
    local player = overworld and overworld.player
    laserState.active = kittEnabled() and laserState.held and player ~= nil
    updateLaserAudio(laserState.active)
    if not laserState.active then return end
    local direction = player.facing
    if not direction then return end
    for _, npc in ipairs(overworld.npcs or {}) do
      local forward, lateral = collisionOffset(player, npc, direction)
      if forward >= -4 and forward <= 152 and lateral <= 7 then
        launchNpc(npc, direction)
      end
    end
  end

  local function updateCollisions(dt)
    local overworld = liveOverworld()
    local step = dt or 1 / 60
    if wilhelmDelay then
      wilhelmDelay = wilhelmDelay - step
      if wilhelmDelay <= 0 then
        wilhelmDelay = nil
        playWilhelm()
      end
    end
    for npc, frames in pairs(collisionCooldown) do
      collisionCooldown[npc] = math.max(0, frames - 1)
    end
    for npc, state in pairs(flyingNpcs) do
      state.age = state.age + step
      state.vy = state.vy + 420 * step
      state.x = state.x + state.vx * step
      state.y = state.y + state.vy * step
      if state.age >= mod.exports.collision.respawnDelay then
        restoreNpc(state)
        flyingNpcs[npc] = nil
      end
    end
    updateExplosions(step)
    if not kittEnabled() then
      stopCrash()
      wilhelmDelay = nil
      return
    end
    if not overworld or not overworld.player then
      stopCrash()
      return
    end
    if not optionValue("impactCollision", true) then
      stopCrash()
      return
    end
    local input = Game.input
    local directions = {}
    for _, direction in ipairs({ "up", "down", "left", "right" }) do
      if input and input:isDown(direction) then directions[direction] = true end
    end
    if overworld.player.moving and overworld.player.facing then
      directions[overworld.player.facing] = true
    end
    if turbo.player == overworld.player and turbo.direction then
      directions[turbo.direction] = true
    end
    updateCrashPreRoll(overworld, overworld.player, directions)
    for direction in pairs(directions) do
        for _, npc in ipairs(overworld.npcs or {}) do
          if collisionHit(overworld.player, npc, direction) then
            launchNpc(npc, direction)
          end
        end
    end
  end

  local function selectedTrack()
    local value = mod.options:get("audio")
    return tracks[value or "Original"]
  end

  local carToggleRect
  local carToggleTouch
  local carToggleKeyStarted
  local carIcons = {}
  local skiToggleRect
  local attackToggleRect
  local laserToggleRect
  local laserTouch
  local skiIcon
  local attackIcon

  local function carButtonGeometry(width, height)
    local buttonW = math.min(72, math.max(56, math.floor(height * 0.1)))
    local buttonH = math.min(52, math.max(40, math.floor(height * 0.072)))
    local margin = math.max(12, math.floor(width * 0.018))
    local x = width - margin - buttonW
    local y = margin
    return {
      drawX = x,
      drawY = y,
      x = x - 18,
      y = y - 18,
      w = buttonW + 36,
      h = buttonH + 36,
      width = buttonW,
      height = buttonH,
    }
  end

  local function skiButtonGeometry(width, height)
    local controls = Game.touchControls
    local layout = controls and controls.layout and controls:layout()
    local a = layout and layout.a
    local b = layout and layout.b
    if a and b then
      local size = math.max(24, math.min(36, math.floor(math.min(a.w, b.w) * 0.42)))
      local centerX = b.cx - b.w * 0.66
      local centerY = b.cy - b.w * 0.62
      return {
        drawX = centerX - size / 2,
        drawY = centerY - size / 2,
        x = centerX - size / 2 - 10,
        y = centerY - size / 2 - 10,
        w = size + 20,
        h = size + 20,
        size = size,
      }
    end
    local size = math.max(24, math.min(36, math.floor(math.min(width, height) * 0.07)))
    return {
      drawX = width - size * 3,
      drawY = height - size * 2.2,
      x = width - size * 3 - 10,
      y = height - size * 2.2 - 10,
      w = size + 20,
      h = size + 20,
      size = size,
    }
  end

  local function attackButtonGeometry(width, height)
    local controls = Game.touchControls
    local layout = controls and controls.layout and controls:layout()
    local a = layout and layout.a
    if a then
      local size = math.max(24, math.min(36, math.floor(a.w * 0.42)))
      local centerX = a.cx - a.w * 0.62
      local centerY = a.cy - a.w * 0.72
      return {
        drawX = centerX - size / 2,
        drawY = centerY - size / 2,
        x = centerX - size / 2 - 10,
        y = centerY - size / 2 - 10,
        w = size + 20,
        h = size + 20,
        size = size,
      }
    end
    local size = math.max(24, math.min(36, math.floor(math.min(width, height) * 0.07)))
    return {
      drawX = width - size * 4.2,
      drawY = height - size * 3.2,
      x = width - size * 4.2 - 10,
      y = height - size * 3.2 - 10,
      w = size + 20,
      h = size + 20,
      size = size,
    }
  end

  local function laserButtonGeometry(width, height)
    local controls = Game.touchControls
    local layout = controls and controls.layout and controls:layout()
    local a = layout and layout.a
    if a then
      local size = math.max(24, math.min(34, math.floor(a.w * 0.4)))
      local centerX = a.cx - a.w * 0.66
      local centerY = a.cy + a.w * 0.42
      return {
        drawX = centerX - size / 2,
        drawY = centerY - size / 2,
        x = centerX - size / 2 - 10,
        y = centerY - size / 2 - 10,
        w = size + 20,
        h = size + 20,
        size = size,
      }
    end
    local size = math.max(24, math.min(34, math.floor(math.min(width, height) * 0.065)))
    return {
      drawX = width - size * 5.25,
      drawY = height - size * 2.25,
      x = width - size * 5.25 - 10,
      y = height - size * 2.25 - 10,
      w = size + 20,
      h = size + 20,
      size = size,
    }
  end

  local function mobilePlatform()
    local osName = love.system and love.system.getOS and love.system.getOS()
    return osName == "iOS" or osName == "Android"
  end

  local function loadCarIcon(mode)
    local variant = karrEnabled() and "KARR" or "KITT"
    local key = mode .. variant
    local cached = carIcons[key]
    if cached ~= nil then return cached or nil end
    local files = CAR_ICON_FILES[mode] or CAR_ICON_FILES.Original
    local path = files[variant]
    local ok, image = pcall(love.graphics.newImage, mod.assets:path(path))
    if ok and image then
      pcall(image.setFilter, image, "linear", "linear")
      carIcons[key] = image
      return image
    end
    carIcons[key] = false
    return nil
  end

  local function loadSkiIcon()
    if skiIcon ~= nil then return skiIcon or nil end
    local ok, image = pcall(love.graphics.newImage,
                            mod.assets:path(SKI_ICON_FILE))
    if ok and image then
      pcall(image.setFilter, image, "linear", "linear")
      skiIcon = image
      return image
    end
    skiIcon = false
    return nil
  end

  local function loadAttackIcon()
    if attackIcon ~= nil then return attackIcon or nil end
    local ok, image = pcall(love.graphics.newImage,
                            mod.assets:path(ATTACK_ICON_FILE))
    if ok and image then
      pcall(image.setFilter, image, "linear", "linear")
      attackIcon = image
      return image
    end
    attackIcon = false
    return nil
  end

  local function toggleCarMode(game)
    local current = optionValue("audio", "Original")
    setOption(game, "audio", current == "Original" and "KR2008" or "Original")
    playScanner()
  end

  local function toggleKarrMode(game)
    setOption(game, "karr", not optionValue("karr", false))
    playScanner()
  end

  mod.hooks:wrap("render.hud", function(next, game, viewport)
    next(game, viewport)
    if not (mobilePlatform() and kittEnabled() and liveOverworld()) then
      carToggleRect = nil
      carToggleTouch = nil
      skiToggleRect = nil
      attackToggleRect = nil
      laserToggleRect = nil
      laserTouch = nil
      if not (kittEnabled() and liveOverworld()) then laserState.held = false end
      return
    end
    local width = (viewport and viewport.width) or love.graphics.getWidth()
    local height = (viewport and viewport.height) or love.graphics.getHeight()
    local geometry = carButtonGeometry(width, height)
    local skiGeometry = skiButtonGeometry(width, height)
    local attackGeometry = attackButtonGeometry(width, height)
    local laserGeometry = laserButtonGeometry(width, height)
    local x, y = geometry.drawX, geometry.drawY
    carToggleRect = geometry
    local mode = optionValue("audio", "Original")
    local image = loadCarIcon(mode)
    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setColor(0.04, 0.05, 0.07, 0.32)
    love.graphics.rectangle("fill", x, y, geometry.width, geometry.height, 10, 10)
    love.graphics.setColor(0.9, 0.94, 1, 0.34)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, geometry.width - 1,
                            geometry.height - 1, 9, 9)
    if image then
      local scale = math.min(geometry.width / image:getWidth(),
                             geometry.height / image:getHeight())
      local drawW = image:getWidth() * scale
      local drawH = image:getHeight() * scale
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(image, x + (geometry.width - drawW) / 2,
                         y + (geometry.height - drawH) / 2,
                         0, scale, scale)
    end
    skiToggleRect = skiGeometry
    love.graphics.setColor(0.04, 0.05, 0.07, 0.7)
    love.graphics.circle("fill", skiGeometry.drawX + skiGeometry.size / 2,
                         skiGeometry.drawY + skiGeometry.size / 2,
                         skiGeometry.size / 2)
    if skiEnabled() then
      love.graphics.setColor(0.72, 0.92, 1, 0.9)
      love.graphics.setLineWidth(2)
      love.graphics.circle("line", skiGeometry.drawX + skiGeometry.size / 2,
                           skiGeometry.drawY + skiGeometry.size / 2,
                           skiGeometry.size / 2 - 1)
    end
    local icon = loadSkiIcon()
    if icon then
      local scale = (skiGeometry.size * 0.62) / math.max(icon:getWidth(), icon:getHeight())
      love.graphics.setColor(1, 1, 1, 0.95)
      love.graphics.draw(icon,
        skiGeometry.drawX + (skiGeometry.size - icon:getWidth() * scale) / 2,
        skiGeometry.drawY + (skiGeometry.size - icon:getHeight() * scale) / 2,
        0, scale, scale)
    end
    if attackAvailable() then
      attackToggleRect = attackGeometry
      love.graphics.setColor(0.12, 0.04, 0.04, 0.75)
      love.graphics.circle("fill", attackGeometry.drawX + attackGeometry.size / 2,
                           attackGeometry.drawY + attackGeometry.size / 2,
                           attackGeometry.size / 2)
      if attackVisual() then
        love.graphics.setColor(1, 0.3, 0.3, 0.9)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", attackGeometry.drawX + attackGeometry.size / 2,
                             attackGeometry.drawY + attackGeometry.size / 2,
                             attackGeometry.size / 2 - 1)
      end
      local attack = loadAttackIcon()
      if attack then
        local scale = (attackGeometry.size * 0.62) / math.max(attack:getWidth(), attack:getHeight())
        love.graphics.setColor(1, 1, 1, 0.95)
        love.graphics.draw(attack,
          attackGeometry.drawX + (attackGeometry.size - attack:getWidth() * scale) / 2,
          attackGeometry.drawY + (attackGeometry.size - attack:getHeight() * scale) / 2,
          0, scale, scale)
      end
    else
      attackToggleRect = nil
    end
    laserToggleRect = laserGeometry
    love.graphics.setColor(0.12, 0.04, 0.04, 0.75)
    love.graphics.circle("fill", laserGeometry.drawX + laserGeometry.size / 2,
                         laserGeometry.drawY + laserGeometry.size / 2,
                         laserGeometry.size / 2)
    love.graphics.setColor(1, 0.28, 0.2, laserState.active and 1 or 0.86)
    love.graphics.setLineWidth(2)
    local laserX = laserGeometry.drawX + laserGeometry.size / 2
    local laserY = laserGeometry.drawY + laserGeometry.size / 2
    love.graphics.line(laserX - laserGeometry.size * 0.28, laserY,
                       laserX + laserGeometry.size * 0.28, laserY)
    love.graphics.line(laserX - laserGeometry.size * 0.08, laserY - laserGeometry.size * 0.16,
                       laserX + laserGeometry.size * 0.28, laserY)
    love.graphics.line(laserX - laserGeometry.size * 0.08, laserY + laserGeometry.size * 0.16,
                       laserX + laserGeometry.size * 0.28, laserY)
    love.graphics.pop()
  end, 1000)

  local baseTouchpressed = Game.__gen1KrBaseTouchpressed or Game.touchpressed
  Game.__gen1KrBaseTouchpressed = baseTouchpressed
  function Game:touchpressed(id, x, y)
    if mobilePlatform() and kittEnabled() and liveOverworld() then
      if not carToggleRect then
        carToggleRect = carButtonGeometry(love.graphics.getWidth(),
                                          love.graphics.getHeight())
      end
      if not skiToggleRect then
        skiToggleRect = skiButtonGeometry(love.graphics.getWidth(),
                                           love.graphics.getHeight())
      end
      if attackAvailable() and not attackToggleRect then
        attackToggleRect = attackButtonGeometry(love.graphics.getWidth(),
                                                 love.graphics.getHeight())
      end
      if not laserToggleRect then
        laserToggleRect = laserButtonGeometry(love.graphics.getWidth(),
                                              love.graphics.getHeight())
      end
      local attack = attackToggleRect
      if attack and x >= attack.x and x <= attack.x + attack.w
          and y >= attack.y and y <= attack.y + attack.h then
        requestAttackMode(self)
        return
      end
      local ski = skiToggleRect
      if x >= ski.x and x <= ski.x + ski.w and y >= ski.y and y <= ski.y + ski.h then
        requestSkiMode(self)
        return
      end
      local laser = laserToggleRect
      if laser and x >= laser.x and x <= laser.x + laser.w
          and y >= laser.y and y <= laser.y + laser.h then
        laserTouch = id
        laserState.held = true
        return
      end
      local r = carToggleRect
      if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then
        carToggleTouch = {
          id = id,
          started = love.timer and love.timer.getTime and love.timer.getTime() or 0,
        }
        return
      end
    end
    return baseTouchpressed(self, id, x, y)
  end

  local baseTouchreleased = Game.__gen1KrBaseTouchreleased or Game.touchreleased
  Game.__gen1KrBaseTouchreleased = baseTouchreleased
  function Game:touchreleased(id, x, y)
    if laserTouch == id then
      laserTouch = nil
      laserState.held = false
      return
    end
    local touch = carToggleTouch
    if touch and touch.id == id then
      carToggleTouch = nil
      if not touch.activated then
        toggleCarMode(self)
      end
      return
    end
    return baseTouchreleased(self, id, x, y)
  end

  mod.hooks:wrap("music.select", function(next, chosen, ctx)
    local result = next(chosen, ctx)
    if kittEnabled() and ctx and ctx.reason == "map" and ctx.mapId then
      local def = Game.data.maps and Game.data.maps[ctx.mapId]
      if def and Map.isOutdoor(def) then
        local replacement = selectedTrack()
        if replacement then return replacement end
      end
    end
    return result
  end, 1000)

  mod.hooks:wrap("input.step", function(next, game, dt)
    local scannerPressed = false
    local turboPressed = false
    local input = game and game.input
    local keyHold = carToggleKeyStarted
    if keyHold and not keyHold.activated and love.timer and love.timer.getTime
        and love.timer.getTime() - keyHold.started >= 0.5 then
      toggleKarrMode(game)
      keyHold.activated = true
    end
    local touchHold = carToggleTouch
    if touchHold and not touchHold.activated and love.timer and love.timer.getTime
        and love.timer.getTime() - touchHold.started >= 0.5 then
      toggleKarrMode(game)
      touchHold.activated = true
    end
    for _, button in ipairs(input and input.pressQueue or {}) do
      if button == "a" then
        scannerPressed = true
      elseif button == "b" then
        turboPressed = true
      end
    end
    if kittEnabled() and turboPressed then requestTurbo(input) end
    startTurbo(dt)
    updateTurboAudio()
    updateLaser()
    local result = next(game, dt)
    updateSkiRequest(dt)
    updateSkiState(dt)
    updateAttackMode(game)
    updatePowerDown()
    if kittEnabled() and scannerPressed then playScanner() end
    updateEngine()
    updateVoiceChatter()
    updateCollisions(dt)
    return result
  end)

  local baseKeypressed = Game.__gen1KrBaseKeypressed or Game.keypressed
  Game.__gen1KrBaseKeypressed = baseKeypressed
  function Game:keypressed(key)
    if kittEnabled() and liveOverworld() and key == "l" then
      laserState.held = true
      return
    end
    if kittEnabled() and liveOverworld() and key == "space" then
      requestTurbo(self.input)
      return
    end
    if kittEnabled() and liveOverworld()
        and (key == "return" or key == "kpenter") then
      playScanner()
      return
    end
    if kittEnabled() and liveOverworld() and key == "c" then
      if not carToggleKeyStarted then
        carToggleKeyStarted = {
          started = love.timer and love.timer.getTime and love.timer.getTime() or 0,
          activated = false,
        }
      end
      return
    end
    if kittEnabled() and liveOverworld() and key == "s" then
      requestSkiMode(self)
      return
    end
    if kittEnabled() and liveOverworld() and key == "x" then
      requestAttackMode(self)
      return
    end
    local result = baseKeypressed(self, key)
    return result
  end

  local baseKeyreleased = Game.__gen1KrBaseKeyreleased or Game.keyreleased
  Game.__gen1KrBaseKeyreleased = baseKeyreleased
  function Game:keyreleased(key)
    if key == "l" then
      laserState.held = false
      return
    end
    if key == "c" and carToggleKeyStarted then
      local hold = carToggleKeyStarted
      carToggleKeyStarted = nil
      local now = love.timer and love.timer.getTime and love.timer.getTime() or hold.started
      if kittEnabled() and liveOverworld() then
        if not hold.activated and now - hold.started < 0.5 then
          toggleCarMode(self)
        end
        return
      end
    end
    return baseKeyreleased(self, key)
  end

  mod.events:on("mod.options_changed", function(payload)
    if not (payload and payload.mod == mod.id) then
      return
    end
    if payload.key == "kitt" then
      stopEngine()
      clearTurbo()
      skiRequest = nil
      attackState.transition = nil
      stopCrash()
      if scannerSource then pcall(scannerSource.stop, scannerSource) end
      if turboSource then pcall(turboSource.stop, turboSource) end
      if laserSource then pcall(laserSource.stop, laserSource) end
      laserState.held = false
      laserState.active = false
      for _, effect in ipairs(activeTurboSources) do pcall(effect.stop, effect) end
      activeTurboSources = {}
      if skiSource then pcall(skiSource.stop, skiSource) end
      if attackTransformSource then pcall(attackTransformSource.stop, attackTransformSource) end
      stopVoice()
      if payload.value then
        powerDownVisible = false
        powerDownDeadline = nil
        if powerDownSource then pcall(powerDownSource.stop, powerDownSource) end
        playPowerUp()
      elseif playPowerDown() then
        return
      end
      local overworld = mapOverworld()
      if overworld then
        Music.playMap(Game.data, overworld.map.id, Game.save.onBike,
                      overworld.player.surfing)
      end
      return
    end
    if payload.key == "impactCollision" then
      if not payload.value then stopCrash() end
      return
    end
    if payload.key ~= "audio" then return end
    if payload.value ~= "KR2008" then
      attackState.transition = nil
      setOption(Game, "attackMode", false)
    end
    stopEngine()
    local overworld = mapOverworld()
    if overworld then
      Music.playMap(Game.data, overworld.map.id, Game.save.onBike,
                    overworld.player.surfing)
    end
  end)

  mod.events:on("game.ready", function(payload)
    setVoxelMode(payload and payload.game or Game)
  end)
end
