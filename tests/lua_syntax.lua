local files = { "main.lua" }
for _, path in ipairs(files) do
  local chunk, err = loadfile(path)
  assert(chunk, err)
end
print("lua syntax ok")
local model = dofile("assets/kitt_model.lua")
assert(model.paletteWidth == 16)
assert(type(model.materials) == "table" and #model.materials > 0)
assert(type(model.vertices) == "table" and #model.vertices > 0)
assert(#model.vertices % 3 == 0)
assert(type(model.wheels) == "table" and #model.wheels == 4)
for _, wheel in ipairs(model.wheels) do
  assert(type(wheel.vertices) == "table" and #wheel.vertices % 3 == 0)
  assert(#wheel.vertices / 3 >= 500)
  assert(type(wheel.center) == "table" and #wheel.center == 3)
end
assert(model.wheels[1].center[1] < 0 and model.wheels[3].center[1] > 0)
print("voxel model data ok")
local mustang = dofile("assets/mustang_model.lua")
assert(mustang.texture == true)
assert(type(mustang.vertices) == "table" and #mustang.vertices > 0)
assert(#mustang.vertices % 3 == 0)
assert(#mustang.vertices / 3 >= 3000)
for _, vertex in ipairs(mustang.vertices) do
  assert(vertex[4] >= 0 and vertex[4] <= 1)
  assert(vertex[5] >= 0 and vertex[5] <= 1)
end
assert(type(mustang.wheels) == "table" and #mustang.wheels == 4)
for _, wheel in ipairs(mustang.wheels) do
  assert(#wheel.vertices / 3 >= 800 and #wheel.vertices / 3 <= 950)
end
local bounds = { { math.huge, -math.huge }, { math.huge, -math.huge }, { math.huge, -math.huge } }
for _, vertex in ipairs(mustang.vertices) do
  for axis = 1, 3 do
    bounds[axis][1] = math.min(bounds[axis][1], vertex[axis])
    bounds[axis][2] = math.max(bounds[axis][2], vertex[axis])
  end
end
assert(math.abs(bounds[1][1] + bounds[1][2]) < 0.01)
assert(bounds[1][2] - bounds[1][1] > 17 and bounds[1][2] - bounds[1][1] < 19)
assert(bounds[2][2] - bounds[2][1] > 7 and bounds[2][2] - bounds[2][1] < 9)
assert(bounds[3][2] - bounds[3][1] > 40 and bounds[3][2] - bounds[3][1] < 42)
for index = 0, 3 do
  local handle = assert(io.open("assets/kitt_palette_" .. index .. ".png", "rb"))
  handle:close()
end
local handle = assert(io.open("assets/mustang_texture.png", "rb"))
handle:close()
for _, path in ipairs({ "assets/scanner_dim.png", "assets/scanner_medium.png", "assets/scanner_bright.png" }) do
  local handle = assert(io.open(path, "rb"))
  handle:close()
end
for _, path in ipairs({
  "assets/karr2000_scanner_dim.png",
  "assets/karr2000_scanner_medium.png",
  "assets/karr2000_scanner_bright.png",
  "assets/karr3000_scanner_dim.png",
  "assets/karr3000_scanner_medium.png",
  "assets/karr3000_scanner_bright.png",
  "assets/karr-2000-icon.png",
  "assets/karr-3000-icon.png",
  "audio/karr-scanner.ogg",
}) do
  local handle = assert(io.open(path, "rb"))
  handle:close()
end
for index = 0, 3 do
  local handle = assert(io.open("assets/karr_palette_" .. index .. ".png", "rb"))
  handle:close()
end
local impact = assert(io.open("audio/impact.ogg", "rb"))
impact:close()
local skiSound = assert(io.open("audio/ski_mode.ogg", "rb"))
skiSound:close()
for _, path in ipairs({ "audio/power_up.ogg", "audio/power_down.ogg" }) do
  local handle = assert(io.open(path, "rb"))
  handle:close()
end
for _, path in ipairs({ "assets/ski-mode-icon.svg", "assets/ski-mode-icon.png", "assets/ski_palette.png" }) do
  local handle = assert(io.open(path, "rb"))
  handle:close()
end
for _, path in ipairs({
  "assets/kitt-3000-attack-model.lua",
  "assets/kitt-3000-attack-texture.png",
  "assets/attack-mode-icon.svg",
  "assets/attack-mode-icon.png",
  "audio/attack-transform.ogg",
  "audio/kitt-2000-nominal.ogg",
  "audio/kitt-2000-turbo.ogg",
  "audio/kitt-2000-collision.ogg",
  "audio/kitt-3000-nominal.ogg",
  "audio/kitt-3000-turbo.ogg",
  "audio/kitt-3000-collision.ogg",
  "audio/kitt-2000-property-damage.ogg",
  "audio/kitt-2000-inadvisable.ogg",
  "audio/kitt-3000-driving-strategy.ogg",
  "audio/kitt-3000-threat-assessment.ogg",
  "audio/kitt-3000-enjoying-this.ogg",
}) do
  local handle = assert(io.open(path, "rb"))
  handle:close()
end
local main = assert(io.open("main.lua", "rb")):read("*a")
assert(main:find("movement%.collision"))
assert(main:find("getTime%(%) %* 4"))
assert(not main:find("ctx%.voxel%.seams%(", 1))
assert(not main:find("ctx%.voxel%.glass%(", 1))
assert(main:find("heightScale = %(mode == \"KR2008\" or mode == \"KR2008Attack\"%) and 1%.3767 or 1"))
assert(not main:find("wheel%.inset"))
assert(main:find("ctx%.draw%(model%.scannerMesh, texture, scannerMatrix, 0, scannerMatrix%)"))
assert(main:find("ctx%.pass ~= \"scene\""))
local scannerStart = assert(main:find("local function drawScannerSweep"))
local scannerEnd = assert(main:find("local drawExplosions", scannerStart))
local scanner = main:sub(scannerStart, scannerEnd)
assert(scanner:find("ctx%.facing ~= \"down\""))
assert(scanner:find("ctx%.voxel%.depth%(\"always\"%)"))
assert(scanner:find("ctx%.voxel%.depth%(\"test\"%)"))
assert(main:find("m%.translate%(segment%[1%], segment%[2%], segment%[3%]%)"))
assert(main:find("m%.rotateY%(segment%[4%]%)"))
assert(main:find("%{ 0%.38, 0%.01, 0 %}"))
assert(main:find("%{ 0%.75, 0%.04, 0%.005 %}"))
assert(main:find("key == \"space\""))
assert(main:find("key == \"return\""))
assert(main:find("key == \"kpenter\""))
assert(main:find("key = \"kitt\""))
assert(main:find("ui%.start_menu%.items"))
assert(main:find("key = \"kitt\",%s*label = \"K%.I%.T%.T%.\",%s*type = \"toggle\",%s*default = false"))
assert(main:find("value == \"KR2009\""))
assert(main:find("return \"KR2008\""))
assert(not main:find("K%.I%.T%.T%. ON"))
assert(not main:find("K%.I%.T%.T%. OFF"))
assert(main:find("buttonW = math.min%(72"))
assert(main:find("mobilePlatform%(%) and kittEnabled%(%) and liveOverworld%(%)"))
assert(main:find("vehicleSpeed%(%)"))
assert(main:find("key == \"s\""))
assert(not main:find("key == \"v\""))
assert(main:find("requestSkiMode"))
assert(main:find("skiTransform"))
assert(main:find("rotateZ"))
assert(not main:find("VEHICLE_HALF_WIDTH"))
assert(not main:find("m%.rotateX%(skiState%.amount"))
assert(main:find("POWER_UP_FILE"))
assert(main:find("POWER_DOWN_FILE"))
assert(main:find("POWER_DOWN_DURATION"))
assert(main:find("TURBO_HOP_FRAMES = 36"))
assert(main:find("TURBO_DISTANCE = 96"))
assert(main:find("SKI_ACTIVATION_DELAY = 0%.3"))
assert(main:find("progress < 0%.25"))
assert(not main:find("key = \"threeD\""))
assert(not main:find("assets/kitt%.png"))
assert(not main:find("local label = mode == \"Original\" and \"KITT 2000\""))
assert(main:find("if player%.inputLocked then return false end"))
assert(main:find("toggleKarrMode", 1, true))
assert(main:find("KARR_SCANNER_FILE", 1, true))
assert(main:find("local lastVoiceFiles = {}", 1, true))
assert(main:find("candidate ~= last", 1, true))
assert(main:find("local objectCrashKey", 1, true))
assert(main:find("if objectCrashKey ~= key then", 1, true))
assert(main:find("if crashTarget ~= false then stopCrash() end", 1, true))
assert(main:find("playCrash(target, direction, timeToImpact, false)", 1, true))
assert(main:find("touchreleased", 1, true))
assert(main:find("local touchHold = carToggleTouch", 1, true))
assert(main:find("if not touch.activated then", 1, true))
assert(main:find("return active, 1, pulse * 0.55, 0", 1, true))
assert(main:find("if mode == \"KR2008\" and #wheels == 0", 1, true))
assert(main:find("if voiceSource then pcall(voiceSource.stop, voiceSource) end", 1, true))
assert(main:find("local activeTurboSources = {}", 1, true))
assert(main:find("pcall(turboSource.clone, turboSource)", 1, true))
assert(main:find("updateTurboAudio()", 1, true))
assert(main:find("local LASER_FILE = \"audio/laser.ogg\"", 1, true))
assert(main:find("local LASER_TEXTURE_FILE = \"assets/laser.png\"", 1, true))
assert(main:find("local function drawLaserBeam", 1, true))
assert(main:find("local function updateLaser()", 1, true))
assert(main:find("key == \"l\"", 1, true))
assert(main:find("m.translate(0, 4.1, 20.62))", 1, true))
assert(main:find("local outerMatrix = m.mul(beamMatrix, m.scale(2.1, 2.1, 1))", 1, true))
assert(main:find("mode == \"Original\" or mode == \"KR2008\"", 1, true))
assert(main:find("if model.mode == \"Original\" or model.mode == \"OriginalKarr\" then return end", 1, true))
assert(main:find("if not (kittEnabled() and liveOverworld()) then laserState.held = false end", 1, true))
local attack = dofile("assets/kitt-3000-attack-model.lua")
assert(attack.texture == true)
assert(type(attack.vertices) == "table" and #attack.vertices % 3 == 0)
local attackTriangles = #attack.vertices / 3
for _, part in ipairs(attack.parts or {}) do attackTriangles = attackTriangles + #part / 3 end
for _, wheel in ipairs(attack.wheels or {}) do attackTriangles = attackTriangles + #wheel.vertices / 3 end
assert(attackTriangles >= 12000)
assert(type(attack.wheels) == "table" and #attack.wheels == 4)
local exporter = assert(io.open("tools/export_textured_model.py", "rb")):read("*a")
assert(exporter:find("--static-wheels", 1, true))
assert(exporter:find("--material-colors", 1, true))
assert(exporter:find("--wheel-branch", 1, true))
assert(exporter:find("--exclude-branch", 1, true))
assert(exporter:find("Geom3D%.064"))
assert(exporter:find("Geom3D%.065"))
assert(exporter:find("Geom3D%.091"))
print("mustang model data ok")
