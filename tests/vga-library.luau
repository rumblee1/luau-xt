local Machine = require("../src/Machine")
local decode = require("../src/MediaDecode")
local readScreen = require("../src/TextScreen")
local keys = require("../src/Keyboard")

local media = "../src/media/"
local folder = media .. "vga_hard_disk/"
local index = require(folder .. "Index")
local disk = buffer.create(index.size)
for _, part in index.parts do
	decode(require(folder .. part[2]), disk, part[1])
end

local machine = Machine.new(
	decode(require(media .. "Bios")),
	decode(require(media .. "Disk")),
	decode(require(media .. "DiskRom")),
	disk,
	decode(require(media .. "AtBios")),
	decode(require(media .. "VgaBios"))
)
local bus, board = machine.bus, machine.board
local vga = assert(bus.vga)

local function runUntil(condition, label)
	for _ = 1, 2400 do
		for _ = 1, 4096 do
			machine:step()
		end
		if condition() then
			return
		end
	end
	error(label .. "\n" .. readScreen(bus, board))
end

local function atPrompt()
	return not vga.active and readScreen(bus, board):match("C:\\>%s*$") ~= nil
end

local function pixel(x, y)
	return buffer.readu8(vga.memory, y * 320 + x)
end

local function press(key)
	local scan = assert(keys[key], key)
	board:queueScanCode(scan)
	board:queueScanCode(scan + 0x80)
	for _ = 1, 8192 do
		machine:step()
	end
end

local special = { [" "] = "Space", ["."] = "Period", ["\\"] = "BackSlash" }
local function command(line)
	for char in line:gmatch(".") do
		press(special[char] or char:upper())
	end
	press("Return")
end

local function exitGraphics()
	press("Escape")
	runUntil(atPrompt, "Guest did not return to DOS")
end

runUntil(atPrompt, "VGA disk did not boot")
command("vga")
runUntil(function()
	return atPrompt() and readScreen(bus, board):find("VGA Library", 1, true)
end, "VGA launcher did not list the library")

command("games\\orbit")
runUntil(function()
	return vga.active and pixel(36, 100) == 4 and pixel(66, 100) == 6
end, "Orbit ship and beacon did not draw")
press("Right")
runUntil(function()
	return pixel(14, 10) == 5
end, "Orbit did not register a collected beacon")
press("Space")
exitGraphics()

command("games\\signal")
runUntil(function()
	return vga.active and pixel(66, 24) == 15 and pixel(250, 168) == 1
end, "Signal grid did not draw")
press("Space")
runUntil(function()
	local color = pixel(68, 26)
	return color >= 4 and color <= 11
end, "Signal did not reveal the selected tile")
press("Right")
press("Space")
runUntil(function()
	local color = pixel(116, 26)
	return color >= 4 and color <= 11
end, "Signal did not reveal the second tile")
exitGraphics()

command("apps\\palette")
runUntil(function()
	return vga.active and pixel(203, 164) == 255 and pixel(242, 71) == 255
end, "Palette grid did not draw")
press("Right")
press("Down")
press("Return")
runUntil(function()
	return atPrompt() and readScreen(bus, board):find("VGA palette index 0x11", 1, true)
end, "Palette did not report the selected index")

command("apps\\pixel")
runUntil(function()
	return vga.active and pixel(40, 30) == 15
end, "Pixel editor did not draw")
press("Five")
press("Space")
press("Right")
press("Seven")
press("Space")
runUntil(function()
	return pixel(42, 32) == 5 and pixel(48, 32) == 7
end, "Pixel editor did not paint both cells")
press("S")
runUntil(function()
	return pixel(270, 8) == 5
end, "Pixel editor failed to save")
press("S")
runUntil(function()
	return pixel(270, 8) == 7
end, "Pixel editor should preserve an existing sketch")
exitGraphics()

command("bmpview sketch.bmp")
runUntil(function()
	return vga.active and pixel(80, 52) == 5 and pixel(84, 52) == 7
end, "BMPVIEW could not read the saved sketch")
exitGraphics()

for _, picture in { "sunset", "nebula" } do
	command("bmpview pics\\" .. picture .. ".bmp")
	runUntil(function()
		return vga.active and pixel(130, 110) > 0 and pixel(220, 80) > 0 and pixel(250, 5) > 0
	end, "Could not view " .. picture)
	assert(vga:render(), "Picture should update the VGA display")
	exitGraphics()
end

print(
	"VGA disk booted, both games responded to input, Palette reported a selection, and BMPVIEW displayed the sketch and both pictures"
)
