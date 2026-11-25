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

local function runUntil(condition, blocks)
	for block = 1, blocks do
		for _ = 1, 8192 do
			machine:step()
		end
		if condition(block) then
			return
		end
	end
	error(
		string.format(
			"Doom milestone timeout at %04X:%04X\n%s",
			machine.cpu:selector(2),
			machine.cpu.ip,
			readScreen(bus, board)
		)
	)
end

local function atPrompt()
	return readScreen(bus, board):match("C:\\>%s*$") ~= nil
end

local function press(scan)
	board:queueScanCode(scan)
	board:queueScanCode(scan + 0x80)
	for _ = 1, 8192 do
		machine:step()
	end
end

local special = { [" "] = "Space", ["."] = "Period", ["-"] = "Minus", ["1"] = "One" }
local function command(line)
	for char in line:gmatch(".") do
		press(assert(keys[special[char] or char:upper()]))
	end
	press(keys.Return)
end

runUntil(atPrompt, 1800)
command("cd doom")
runUntil(function()
	return readScreen(bus, board):match("C:\\DOOM>%s*$") ~= nil
end, 200)
command("doom -nosound -nomusic -nomouse -warp 1 1")

local frameCount = 0
local displayedPage = nil
runUntil(function(block)
	if block % 32 ~= 0 or not vga.active or not vga.indexed or not vga.dirty then
		return false
	end
	local pixels = assert(vga:render())
	local seen, count = {}, 0
	for offset = 0, buffer.len(pixels) - 4, 20 do
		local color = buffer.readu32(pixels, offset)
		if not seen[color] then
			seen[color] = true
			count += 1
		end
	end
	local page = buffer.readu8(vga.crtc, 0x0C) * 256 + buffer.readu8(vga.crtc, 0x0D)
	if count >= 24 and page ~= displayedPage then
		displayedPage = page
		frameCount += 1
	end
	return frameCount == 2
end, 22000)
print("DOOM 1.9 entered E1M1 and rendered two different 320x200 VGA pages")

press(keys.F10)
for _ = 1, 2000000 do
	machine:step()
end
press(keys.Y)
runUntil(function()
	return not vga.active and readScreen(bus, board):match("C:\\DOOM>%s*$") ~= nil
end, 2000)
print("DOOM handled the quit keys and returned to the DOS prompt")
