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
local impact = assert(io.open("audio/impact.ogg", "rb"))
impact:close()
local main = assert(io.open("main.lua", "rb")):read("*a")
assert(not main:find("movement%.collision"))
assert(main:find("getTime%(%) %* 4"))
assert(main:find("ctx%.voxel%.seams%(false%)"))
assert(main:find("ctx%.voxel%.glass%(false%)"))
assert(main:find("heightScale = mode == \"KR2008\" and 1%.3767 or 1"))
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
assert(main:find("if player%.inputLocked then return false end"))
local exporter = assert(io.open("tools/export_textured_model.py", "rb")):read("*a")
assert(exporter:find("Geom3D%.064"))
assert(exporter:find("Geom3D%.065"))
assert(exporter:find("Geom3D%.091"))
print("mustang model data ok")
