local MOD_ID = "gen1_kr"
local SPRITE_ID = "GEN1_KR_KITT"
local VOXEL_MODEL_ID = "GEN1_KR_KITT_VOXEL"

local MUSIC = {
  Original = { id = "Music_Gen1KR_Original", file = "audio/original.ogg" },
  KR2008 = { id = "Music_Gen1KR_KR2008", file = "audio/kr2008.ogg" },
}

local ENGINE_FILES = {
  Original = "audio/engine.ogg",
  KR2008 = "audio/kr2008_engine.ogg",
}
local SCANNER_FILE = "audio/scanner.ogg"
local WILHELM_FILE = "audio/wilhelm.ogg"
local IMPACT_FILE = "audio/impact.ogg"
local TURBO_FILE = "audio/turbo.ogg"
local COLLISION_RADIUS = 44
local VOXEL_LEVEL = 4
local MODEL_FILES = {
  Original = "assets/kitt_model.lua",
  KR2008 = "assets/mustang_model.lua",
}
local PALETTE_FILES = {
  Original = {
    "assets/kitt_palette_0.png",
    "assets/kitt_palette_1.png",
    "assets/kitt_palette_2.png",
    "assets/kitt_palette_3.png",
  },
  KR2008 = "assets/mustang_texture.png",
}
local SCANNER_LIGHT_FILES = {
  "assets/scanner_dim.png",
  "assets/scanner_medium.png",
  "assets/scanner_bright.png",
}

return function(mod)
  local function loadBundledVoxel()
    local raw = mod:read("voxel_main.lua")
    if not raw then return nil end
    local loaded, chunk = pcall(load, raw, "@" .. mod.path .. "/voxel_main.lua")
    if not loaded or not chunk then
      mod.log:warn("bundled voxel renderer failed to compile: %s", tostring(chunk))
      return nil
    end
    local started, result = pcall(chunk, mod)
    if not started then
      mod.log:warn("bundled voxel renderer failed to load: %s", tostring(result))
      return nil
    end
    return result
  end

  local bundledVoxel = loadBundledVoxel()
  local VoxelScene = bundledVoxel and bundledVoxel.VoxelScene
  local Game = require("src.core.Game")
  local Collision = require("src.world.Collision")
  local Map = require("src.world.Map")
  local Music = require("src.core.Music")
  local Player = require("src.world.Player")
  local SpriteRenderer = require("src.render.SpriteRenderer")
  local Pipelines = require("src.render.Pipelines")

  mod.content.sprites:register(SPRITE_ID, {
    image = mod.assets:path("assets/kitt.png"),
    frames = 6,
    walker = true,
    trueColor = true,
  })

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
      key = "threeD",
      label = "3D MODE",
      type = "toggle",
      default = true,
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
    return value == nil and default or value
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

  local function setVoxelMode(game, enabled)
    local level = enabled and math.min(VOXEL_LEVEL, Pipelines.maxLevel("voxel")) or 0
    Pipelines.setLevel("voxel", level)
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
      if key == "threeD" then setVoxelMode(game_, not enabled) end
      return true
    end
    filtered[#filtered + 1] = {
      id = MOD_ID .. ":threeD",
      label = "3D MODE",
      value = function() return optionValue("threeD", true) and "ON" or "OFF" end,
      step = function(game_) return cycleBoolean(game_, "threeD", true) end,
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
      id = MOD_ID .. ":impactCollision",
      label = "COLLISION",
      value = function() return optionValue("impactCollision", true) and "ON" or "OFF" end,
      step = function(game_) return cycleBoolean(game_, "impactCollision", true) end,
    }
    return filtered
  end

  mod.hooks:wrap("ui.options.rows", optionRows, 1000)

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

  local function selectedModel()
    local mode = optionValue("audio", "Original")
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
    if mode == "KR2008" then
      for _, path in ipairs(SCANNER_LIGHT_FILES) do
        local textureOk, texture = pcall(love.graphics.newImage,
                                         mod.assets:path(path))
        if textureOk and texture then
          pcall(texture.setFilter, texture, "nearest", "nearest")
          pcall(texture.setWrap, texture, "clamp", "clamp")
          scannerLightTextures[#scannerLightTextures + 1] = texture
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
          heightScale = mode == "KR2008" and 1.3767 or 1,
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
      mesh = mesh,
      texture = textures[1],
      scannerTextures = textures,
      scannerMesh = #scannerLightTextures == #SCANNER_LIGHT_FILES
          and createScannerMesh(ctx) or nil,
      scannerLightTextures = scannerLightTextures,
      wheels = wheels,
      scannerFrame = nil,
      wheelAngle = 0,
      wheelClock = nil,
      wheelFrame = nil,
    }
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

  local function voxelModelMatrix(ctx)
    local yaw = ({
      down = 0,
      up = math.pi,
      right = math.pi / 2,
      left = -math.pi / 2,
    })[ctx.facing] or 0
    local m = ctx.mat4
    return m.mul(
      m.translate(ctx.px + 8, ctx.ground + ctx.lift, ctx.py + 8),
      m.rotateY(yaw))
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
    if ctx.pass ~= "scene" or ctx.facing ~= "down" or not model.scannerMesh
        or #model.scannerLightTextures ~= #SCANNER_LIGHT_FILES then
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
      local texture = model.scannerLightTextures[intensity]
      local scannerMatrix = m.mul(matrix,
          m.mul(m.translate(segment[1], segment[2], segment[3]),
                m.rotateY(segment[4])))
      if flatten then
        local glow = ({
          { { 0.38, 0.01, 0 }, 0.9 },
          { { 0.75, 0.04, 0.005 }, 0.96 },
          { { 1, 0.12, 0.01 }, 1 },
        })[intensity]
        flatten(glow[1], glow[2])
      end
      ctx.draw(model.scannerMesh, texture, scannerMatrix, 0, scannerMatrix)
    end
    ctx.voxel.depth("test")
    if flatten then flatten() end
  end

  local drawExplosions

  local function drawVoxelModel(ctx)
    if not optionValue("threeD", true) then return false end
    if not ctx.def or ctx.def.image ~= mod.path .. "/assets/kitt.png" then
      return false
    end
    local model = loadVoxelModel(ctx)
    if not model then return false end
    updateVoxelScanner(model)
    updateVoxelWheels(model, ctx.moving)
    pcall(model.mesh.setTexture, model.mesh, model.texture)
    local matrix = voxelModelMatrix(ctx)
    ctx.voxel.seams(false)
    ctx.voxel.glass(false)
    if ctx.pass == "shadow" then
      ctx.shadow(model.mesh, model.texture, matrix)
    else
      ctx.draw(model.mesh, model.texture, matrix,
               ctx.pass == "ghost" and 0 or ctx.pull, matrix)
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
    ctx.voxel.seams(true)
    ctx.voxel.glass(true)
    if ctx.pass == "scene" and drawExplosions then drawExplosions(ctx) end
    return true
  end

  local voxelRegistration
  local function installVoxelModel()
    if voxelRegistration then return end
    if VoxelScene then
      voxelRegistration = VoxelScene.registerEntityModel(
        VOXEL_MODEL_ID, drawVoxelModel, 1000)
      return
    end
    local external = mod:find("DRAMATIC_SHAPE")
    local exports = external and external.exports
    if exports and exports.registerEntityModel then
      voxelRegistration = exports.registerEntityModel(
        VOXEL_MODEL_ID, drawVoxelModel, 1000)
    end
  end

  mod.events:on("mods.loaded", installVoxelModel)
  installVoxelModel()

  local vanillaPose = Player.__gen1KrVanillaPose or Player.pose
  Player.__gen1KrVanillaPose = vanillaPose
  local vanillaUpdate = Player.__gen1KrVanillaUpdate or Player.update
  Player.__gen1KrVanillaUpdate = vanillaUpdate
  local kittSprites = setmetatable({}, { __mode = "k" })
  local turbo = {
    player = nil,
    overworld = nil,
    map = nil,
    direction = nil,
    distance = 0,
    request = nil,
  }
  local clearTurbo

  local function isOutdoorPlayer(player)
    local overworld = Game.overworld
    return overworld and overworld.player == player and overworld.map
       and Map.isOutdoor(overworld.map.def)
       and not player.surfing and not player.fishing
  end

  mod.hooks:wrap("movement.speed", function(next, frames, ctx)
    local value = next(frames, ctx)
    if ctx and ctx.player and isOutdoorPlayer(ctx.player) then
      return math.max(1, math.floor(value * 0.5))
    end
    return value
  end, 1000)

  local function kittSprite(player)
    local sprite = kittSprites[player]
    if sprite then return sprite end
    local def = Game.data and Game.data.sprites and Game.data.sprites[SPRITE_ID]
    if not def then return nil end
    sprite = SpriteRenderer.new(def, MOD_ID)
    kittSprites[player] = sprite
    return sprite
  end

  Player.pose = function(self)
    local sprite, px, py, facing, phase, flip, hopping = vanillaPose(self)
    if isOutdoorPlayer(self) then
      if turbo.player == self then
        py = py - 6
        hopping = true
      end
      local replacement = kittSprite(self)
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
      clearTurbo()
      return true
    end
    local landed = vanillaUpdate(self)
    return landed
  end

  local sourceFailures = {}
  local engineSource
  local scannerSource
  local wilhelmSource
  local impactSource
  local turboSource
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
    ctx.voxel.glass(false)
    ctx.voxel.seams(false)
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
    ctx.voxel.seams(true)
    ctx.voxel.glass(true)
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
    if not (overworld and overworld.player.moving) then
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

  local function playScanner()
    if not liveOverworld() then return end
    scannerSource = scannerSource or source(SCANNER_FILE, "static")
    if scannerSource then
      pcall(scannerSource.stop, scannerSource)
      pcall(scannerSource.play, scannerSource)
    end
  end

  local function playWilhelm()
    if not liveOverworld() then return end
    wilhelmSource = wilhelmSource or source(WILHELM_FILE, "static")
    if wilhelmSource then
      pcall(wilhelmSource.stop, wilhelmSource)
      pcall(wilhelmSource.play, wilhelmSource)
    end
  end

  local function playImpact()
    if not liveOverworld() then return end
    impactSource = impactSource or source(IMPACT_FILE, "static")
    if impactSource then
      pcall(impactSource.stop, impactSource)
      pcall(impactSource.setVolume, impactSource, 1)
      pcall(impactSource.play, impactSource)
    end
  end

  local function playTurbo()
    if not liveOverworld() then return end
    turboSource = turboSource or source(TURBO_FILE, "static")
    if turboSource then
      pcall(turboSource.stop, turboSource)
      pcall(turboSource.play, turboSource)
    end
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
    local overworld = liveOverworld()
    local player = overworld and overworld.player
    if not player or turbo.player then return end
    turbo.request = {
      overworld = overworld,
      map = overworld.map,
      direction = turboDirection(input, player),
    }
  end

  local function startTurbo()
    local request = turbo.request
    if not request then return false end
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
    local distance = 64
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
    player.stepFramesCur = 24
    player.hopFrames, player.hopTotal = 24, 24
    playTurbo()
    return true
  end

  local function targetPoint(px, py, direction)
    local dx = direction == "right" and 1 or direction == "left" and -1 or 0
    local dy = direction == "down" and 1 or direction == "up" and -1 or 0
    return px + dx * 16, py + dy * 16
  end

  local function collisionHit(player, npc, direction)
    local dx = direction == "right" and 1 or direction == "left" and -1 or 0
    local dy = direction == "down" and 1 or direction == "up" and -1 or 0
    local offsetX = npc.px - player.px
    local offsetY = npc.py - player.py
    local forward = offsetX * dx + offsetY * dy
    local lateral = math.abs(offsetX * dy - offsetY * dx)
    return forward >= -10 and forward <= COLLISION_RADIUS and lateral <= 20
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
    playImpact()
    wilhelmDelay = 0.42
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
    if not overworld or not optionValue("impactCollision", true)
        or not overworld.player then
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

  mod.hooks:wrap("music.select", function(next, chosen, ctx)
    local result = next(chosen, ctx)
    if ctx and ctx.reason == "map" and ctx.mapId then
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
    for _, button in ipairs(input and input.pressQueue or {}) do
      if button == "a" then
        scannerPressed = true
      elseif button == "b" then
        turboPressed = true
      end
    end
    if turboPressed then requestTurbo(input) end
    startTurbo()
    local result = next(game, dt)
    if scannerPressed then playScanner() end
    updateEngine()
    updateCollisions(dt)
    return result
  end)

  local baseKeypressed = Game.__gen1KrBaseKeypressed or Game.keypressed
  Game.__gen1KrBaseKeypressed = baseKeypressed
  function Game:keypressed(key)
    if liveOverworld() and key == "space" then
      requestTurbo(self.input)
      return
    end
    if liveOverworld() and (key == "return" or key == "kpenter") then
      playScanner()
      return
    end
    return baseKeypressed(self, key)
  end

  mod.events:on("mod.options_changed", function(payload)
    if not (payload and payload.mod == mod.id) then
      return
    end
    if payload.key == "threeD" then
      setVoxelMode(Game, payload.value and true or false)
    end
    if payload.key ~= "audio" then return end
    stopEngine()
    local overworld = mapOverworld()
    if overworld then
      Music.playMap(Game.data, overworld.map.id, Game.save.onBike,
                    overworld.player.surfing)
    end
  end)

  mod.events:on("game.ready", function(payload)
    setVoxelMode(payload and payload.game or Game,
                 optionValue("threeD", true))
  end)
end
