local Machine = require("../src/Machine")
local Vga = require("../src/Vga")
local decode = require("../src/MediaDecode")
local readScreen = require("../src/TextScreen")
local keys = require("../src/Keyboard")

local media = "../src/media/"
local folder = media .. "vga_disk/"
local index = require(folder .. "Index")
local disk = buffer.create(index.size)
for _, part in index.parts do
	decode(require(folder .. part[2]), disk, part[1])
end

local machine = Machine.new(
	decode(require(media .. "Bios")),
	disk,
	nil,
	nil,
	decode(require(media .. "AtBios")),
	decode(require(media .. "VgaBios"))
)
local bus, board = machine.bus, machine.board
local vga = assert(bus.vga)

local function runUntil(condition, blocks)
	for _ = 1, blocks do
		for _ = 1, 1024 do
			machine:step()
		end
		if condition() then
			return
		end
	end
	error(
		string.format(
			"VGA milestone timeout at %04X:%04X\n%s",
			machine.cpu:selector(2),
			machine.cpu.ip,
			readScreen(bus, board)
		)
	)
end

local function atPrompt()
	return readScreen(bus, board):match("A:\\>%s*$") ~= nil
end

local function press(scan)
	board:queueScanCode(scan)
	board:queueScanCode(scan + 0x80)
	for _ = 1, 8192 do
		machine:step()
	end
end

local special = { [" "] = "Space", ["."] = "Period" }
local function command(line)
	for char in line:gmatch(".") do
		press(assert(keys[special[char] or char:upper()]))
	end
	press(keys.Return)
end

runUntil(atPrompt, 16000)
assert(not vga.active and readScreen(bus, board):find("FreeDOS kernel", 1, true))
assert(bus:read8(0x42) == 0 and bus:read8(0x43) == 0xC0, "GLaBIOS should install the VGA ROM's INT 10h handler")

command("bmpview missing.bmp")
runUntil(function()
	return atPrompt() and readScreen(bus, board):find("Cannot open BMP file", 1, true)
end, 1500)

local function pixelIndex(x, y)
	return y * Vga.WIDTH + x
end

local function videoByte(x, y)
	return bus:read8(Vga.MEMORY_BASE + pixelIndex(x, y))
end

command("bmpview sample.bmp")
runUntil(function()
	-- The BMP stores its rows bottom-up. The first pixel of the top row arrives last.
	return vga.active and videoByte(1, 2) == 255
end, 6000)
assert(bus:read8(0x449) == 0x13, "The video BIOS should record mode 13h")
assert(videoByte(210, 100) == 224 and videoByte(318, 197) == 255, "VGA memory should contain the image indices")
assert(videoByte(319, 100) == 0 and videoByte(0, 100) == 0, "BMP row padding should stay outside VRAM")
local pixels = assert(vga:render())
assert(buffer.readu32(pixels, pixelIndex(1, 2) * 4) == 0xFFFFFFFF, "The top-left image pixel should be white")
assert(buffer.readu32(pixels, pixelIndex(210, 100) * 4) == 0xFF0000FF, "The VGA DAC should decode the red bar")
assert(buffer.readu32(pixels, pixelIndex(270, 100) * 4) == 0xFFFF0000, "The VGA DAC should decode the blue bar")
assert(buffer.readu32(pixels, pixelIndex(319, 100) * 4) == 0xFF000000, "The surrounding screen should stay black")
assert(vga:render() == nil, "A static frame should not be rebuilt")
bus:writePort(0x3C7, 224)
assert(bus:readPort(0x3C7) == 3)
assert(bus:readPort(0x3C9) == 63 and bus:readPort(0x3C9) == 0 and bus:readPort(0x3C9) == 0)

press(keys.Return)
runUntil(function()
	return not vga.active and atPrompt()
end, 3000)
assert(bus:read8(0x449) == 3, "The video BIOS should restore DOS text mode")
local restarted = machine:restart()
assert(restarted.bus.vga and restarted.bus.vga ~= vga and not restarted.bus.vga.active)
print("FreeDOS displayed SAMPLE.BMP through VGA VRAM and the DAC, then returned to text mode")

command("vgaclip")
runUntil(function()
	return vga.active and videoByte(36, 70) == 1 and videoByte(36, 71) == 1
end, 2000)
local firstFrame = board.pit.now
assert(buffer.readu32(assert(vga:render()), pixelIndex(36, 70) * 4) == 0xFFFFFFFF)
runUntil(function()
	return videoByte(36, 70) == 0 and videoByte(80, 70) == 1
end, 1000)
assert(board.pit.now - firstFrame > 30000, "Animation should wait for the guest BIOS clock")
press(keys.Escape)
runUntil(function()
	return not vga.active and atPrompt()
end, 2000)
assert(not readScreen(bus, board):find("Invalid or truncated", 1, true))
print("VGACLIP streamed multiple frames at the BIOS clock rate and handled Escape")

local function setVideoMode(mode)
	-- Execute the BIOS interrupt on the guest CPU with a private stack.
	local code = 0x90000
	for offset, value in { 0xB8, mode, 0x00, 0xCD, 0x10, 0xFA, 0xF4 } do
		bus:write8(code + offset - 1, value)
	end
	local cpu = machine.cpu
	cpu:loadSegment(2, 0x9000)
	cpu:loadSegment(3, 0x9000)
	cpu:setRegister(4, true, 0xFFFE)
	cpu.halted = false
	cpu.ip = 0
	runUntil(function()
		return cpu.halted and cpu:selector(2) == 0x9000
	end, 500)
end

local function register(port, index, value)
	bus:writePort(port, index)
	bus:writePort(port + 1, value)
end

setVideoMode(0x12)
assert(vga.active and vga.width == 640 and vga.height == 480 and bus:read8(0x449) == 0x12)
local base = Vga.MEMORY_BASE
bus:write8(base, 0x80)
register(0x3C4, 2, 4)
bus:write8(base + 1, 0x80)
register(0x3CE, 4, 2)
assert(bus:read8(base + 1) == 0x80)
register(0x3C4, 2, 15)
register(0x3CE, 5, 1)
bus:write8(base + 2, 0) -- Copy the latched pixel from the previous read.
register(0x3CE, 5, 2)
register(0x3CE, 8, 0x80)
bus:read8(base + 3)
bus:write8(base + 3, 6) -- Expand the low nibble into the four planes.
register(0x3CE, 5, 3)
register(0x3CE, 0, 1)
bus:read8(base + 4)
bus:write8(base + 4, 0x80) -- Apply the mask to the set/reset color.
register(0x3CE, 5, 8)
register(0x3CE, 2, 1)
assert(bus:read8(base + 4) == 0x80, "VGA read mode 1 should compare all enabled planes")
local planar = assert(vga:render())
assert(buffer.len(planar) == 640 * 480 * 4)
assert(buffer.readu32(planar, 0) == 0xFFFFFFFF)
assert(buffer.readu32(planar, 8 * 4) == 0xFF0000AA)
assert(buffer.readu32(planar, 16 * 4) == 0xFF0000AA)
assert(buffer.readu32(planar, 24 * 4) == 0xFF0055AA)
assert(buffer.readu32(planar, 32 * 4) == 0xFFAA0000)

register(0x3CE, 5, 0)
register(0x3CE, 8, 0xFF)
assert(vga:render() == nil, "Writing graphics access registers should not redraw the display")
bus:write8(base + 10 * 80 + 24, 0x80)
bus:write8(base + 100 * 80 + 32, 0x80)
local _, rectangles = vga:render()
assert(table.concat(rectangles, ",") == "192,10,200,11,256,100,264,101", "Updates should follow the changed pixels")
local row = vga:pixelsForRect(192, 10, 8, 1)
assert(buffer.len(row) == 8 * 4 and buffer.readu32(row, 0) == 0xFFFFFFFF)
bus:write8(base + 10 * 80 + 24, 0)
bus:write8(base + 10 * 80 + 24, 0x80)
local _, restored = vga:render()
assert(#restored == 0, "Restoring the presented pixels should require no upload")
bus:write8(base + 0xF000, 0x80)
local _, offscreen = vga:render()
assert(#offscreen == 0, "An offscreen write should not upload pixels")
bus:writePort(0x3C8, 63)
bus:writePort(0x3C9, 0)
local _, paletteRows = vga:render()
assert(table.concat(paletteRows, ",") == "0,0,640,480", "Palette changes should refresh the full frame")
bus:writePort(0x3C8, 63)
bus:writePort(0x3C9, 63)

register(0x3D4, 0x13, 20) -- A 40-group stride makes consecutive rows overlap.
vga:render()
bus:write8(base + 41, 0x80)
local aliased, aliasedRects = vga:render()
assert(table.concat(aliasedRects, ",") == "328,0,336,1,8,1,16,2", "One VRAM group should update both visible rows")
assert(buffer.readu32(aliased, 328 * 4) == 0xFFFFFFFF and buffer.readu32(aliased, (640 + 8) * 4) == 0xFFFFFFFF)

setVideoMode(0x13)
register(0x3C4, 4, 6) -- Unchain VGA memory while keeping 256-color scanout.
register(0x3C4, 2, 4)
bus:write8(base + 0x4000, 63)
register(0x3D4, 0x0C, 0x40)
local page, pageRows = vga:render()
assert(table.concat(pageRows, ",") == "0,0,320,200", "A display page change should refresh the full frame")
assert(buffer.readu32(page, 2 * 4) == 0xFFFFFFFF, "The CRTC start address should select the other VGA page")
register(0x3C4, 2, 1)
bus:write8(base, 63)
register(0x3D4, 0x0C, 0xFF)
register(0x3D4, 0x0D, 0xF0)
local wrapped = assert(vga:render())
assert(buffer.readu32(wrapped, 64 * 4) == 0xFFFFFFFF, "Full scanout should wrap at the end of VRAM")
bus:write8(base + 1, 63)
local _, wrapRects = vga:render()
assert(table.concat(wrapRects, ",") == "64,0,192,1", "Partial scanout should wrap at the end of VRAM")
local wrappedRect = vga:pixelsForRect(64, 0, 128, 1)
assert(buffer.readu32(wrappedRect, 16) == 0xFFFFFFFF)
setVideoMode(3)
assert(not vga.active and bus:read8(0x449) == 3)
print("VGA drew 640x480 planar pixels with hardware latches and flipped an unchained 256-color page")

local serialMouse = assert(board.serialMouse)
bus:writePort(0x3FB, 0x82)
bus:writePort(0x3F8, 96)
bus:writePort(0x3F9, 0)
assert(bus:readPort(0x3F8) == 96)
bus:writePort(0x3FB, 2) -- 1200 baud, seven data bits, one stop bit.
bus:writePort(0x3F9, 1)
bus:writePort(0x3FC, 0x0B)
board:advance(30000)
assert(bus:readPort(0x3FA) == 4 and bit32.band(board.pic.pending, 0x10) ~= 0)
assert(bus:readPort(0x3F8) == 0x4D, "The powered serial mouse should identify itself")
serialMouse:move(-7, 12, 0x20, board.pit.now, 123)
for index, byte in { 0x63, 57, 12 } do
	board:advance(9000)
	assert(bit32.band(bus:readPort(0x3FD), 1) ~= 0)
	assert(serialMouse.lastMotionReadAt == nil)
	assert(bus:readPort(0x3F8) == byte)
	assert(serialMouse.lastMotionReadAt == (if index == 3 then 123 else nil))
end
serialMouse:move(0, 0, 0, board.pit.now)
for _ = 1, 20 do
	serialMouse:move(1, -1, 0, board.pit.now)
end
serialMouse:move(0, 0, 0x20, board.pit.now)
serialMouse:move(0, 0, 0, board.pit.now)
assert(#serialMouse.pending == 3, "Mouse motion should coalesce while button changes remain ordered")
for _, byte in { 0x4C, 20, 44, 0x60, 0, 0, 0x40, 0, 0 } do
	board:advance(9000)
	assert(bit32.band(bus:readPort(0x3FD), 1) ~= 0 and bus:readPort(0x3F8) == byte)
end
print("COM1 coalesced movements and delivered the press and release in order")

board:queueScanCode(keys.F10)
board:queueScanCode(keys.F10 + 0x80)
assert(bus:readPort(0x60) == keys.F10)
board:advance(1100)
assert(bus:readPort(0x60) == keys.F10 + 0x80, "An AT guest should consume keyboard bytes without using the XT latch")
