local CgaText = require("../src/CgaText")
local Machine = require("../src/Machine")
local decode = require("../src/MediaDecode")
local readScreen = require("../src/TextScreen")
local keys = require("../src/Keyboard")

local mode = ... or "dos"
assert(mode == "dos" or mode == "grub" or mode == "reboot", "Use dos, grub, or reboot")
local media = "../src/media/"

local function loadImage(name)
	local folder = media .. name .. "/"
	local index = require(folder .. "Index")
	local image = buffer.create(index.size)
	for _, part in index.parts do
		decode(require(folder .. part[2]), image, part[1])
	end
	return image
end

local rom = loadImage("SeaBios")
local vgaRom = decode(require(media .. "SeaVgaBios"))
local floppy = if mode == "dos" then loadImage("vga_disk") else nil
local disk = if mode == "grub" then loadImage("grub_disk") elseif mode == "reboot" then loadImage("full_disk") else nil
local machine = Machine.newSeaBios(rom, vgaRom, floppy, disk)
local bus, board = machine.bus, machine.board
local renderer = CgaText.new(decode(require(media .. "Font")))

local function textRegionHasInk(marker)
	local cell = assert(readScreen(bus, board):find(marker, 1, true), marker)
	local row, column = math.floor((cell - 1) / 81), (cell - 1) % 81
	renderer:update(bus, board)
	for y = row * 8, row * 8 + 7 do
		for x = column * 8, (column + #marker) * 8 - 1 do
			if buffer.readu32(renderer.pixels, (y * CgaText.WIDTH + x) * 4) ~= 0xFF000000 then
				return true
			end
		end
	end
	return false
end

for offset = 0, 15 do
	assert(bus:read8(0xFFFFFFF0 + offset) == buffer.readu8(rom, buffer.len(rom) - 16 + offset))
end

local function runUntil(condition, seconds)
	local deadline = board.pit.now + seconds * Machine.PIT_HZ
	repeat
		for _ = 1, 1024 do
			machine:step(512)
		end
		local screen = readScreen(bus, board)
		if condition(screen) then
			return
		end
	until board.pit.now >= deadline
	error(readScreen(bus, board), 0)
end

local function stepFor(clocks)
	local deadline = board.pit.now + clocks
	while board.pit.now < deadline do
		machine:step(64)
	end
end

local function press(key)
	local scan = assert(keys[key], key)
	board:queueScanCode(scan)
	board:queueScanCode(scan + 128)
	stepFor(8192)
end

runUntil(function(screen)
	return screen:find("SeaBIOS (version rel-1.17.0", 1, true) ~= nil
end, 8)
assert(bus:read8(0xC0000) == 0x55 and bus:read8(0xC0001) == 0xAA, "SeaBIOS must install SeaVGABIOS")
assert(textRegionHasInk("SeaBIOS"), "The SeaBIOS banner must be drawn to the text framebuffer")
bus:readPort(0x3DA)
bus:writePort(0x3C0, 0)
assert(not textRegionHasInk("SeaBIOS"), "VGA blanking must hide text without changing VRAM")
bus:readPort(0x3DA)
bus:writePort(0x3C0, 0x20)
bus:readPort(0x3DA)
assert(textRegionHasInk("SeaBIOS"), "Unblanking VGA must restore the text framebuffer")

if mode == "grub" then
	runUntil(function(screen)
		return screen:find("Luau 386 - GRUB Legacy 0.97", 1, true) and screen:find("Halt machine", 1, true)
	end, 24)
	assert(textRegionHasInk("GNU GRUB"), "The GRUB menu must be drawn to the text framebuffer")
	press("Return")
	runUntil(function(screen)
		return screen:find("GRUB MULTIBOOT HANDOFF PASS", 1, true)
	end, 5)
	print("Unmodified SeaBIOS booted GRUB over IDE and GRUB ran the Multiboot program")
elseif mode == "reboot" then
	local function atPrompt(screen)
		return screen:match("C:\\>%s*$") ~= nil
	end
	local name = "resetmem"
	local specialKeys = { [" "] = "Space", ["."] = "Period", ["\\"] = "BackSlash" }
	local function command(line)
		for character in line:gmatch(".") do
			press(specialKeys[character] or character:upper())
		end
		press("Return")
	end

	runUntil(atPrompt, 24)
	local pciAddress = bus:readIo(0xCF8, 4)
	bus:writeIo(0xCF8, 0x80000600, 4)
	assert(bus:readIo(0xCF8, 4) == 0x80000600 and not bus.pc.resetRequested)
	bus:writeIo(0xCF8, pciAddress, 4)

	command("copy fdos\\bin\\mem.exe " .. name .. ".exe")
	runUntil(function(screen)
		return atPrompt(screen) and screen:lower():find("=>> " .. name .. ".exe", 1, true) ~= nil
	end, 5)
	local mounted = buffer.tostring(board.hardDisk.image)
	assert(mounted ~= buffer.tostring(disk))

	for _, key in { "LeftControl", "LeftAlt", "Delete" } do
		board:queueScanCode(keys[key])
	end
	local deadline = board.pit.now + Machine.PIT_HZ
	local rebooted = false
	while board.pit.now < deadline and not rebooted do
		rebooted = machine:step(64) == true
	end
	assert(rebooted and machine.cpu.ip == 0xFFF0, "SeaBIOS reboot must return to the CPU reset vector")
	bus, board = machine.bus, machine.board
	assert(buffer.tostring(board.hardDisk.image) == mounted, "Guest reset must preserve the mounted IDE disk")

	runUntil(atPrompt, 24)
	command(name)
	runUntil(function(screen)
		return atPrompt(screen) and screen:match("C:\\>" .. name .. "[%s%S]*Conventional") ~= nil
	end, 5)
	print("SeaBIOS rebooted FreeDOS from IDE and the guest ran a file copied before the reset")
else
	local function atPrompt(screen)
		return screen:find("A:\\>", 1, true) ~= nil
	end
	runUntil(atPrompt, 24)
	for _, key in { "V", "E", "R", "Return" } do
		press(key)
	end
	runUntil(function(screen)
		return screen:match("A:\\>ver%s+FreeCom version[^\n]+\nA:\\>") ~= nil
	end, 5)
	assert(textRegionHasInk("A:\\>ver"), "FreeDOS command output must be drawn to the text framebuffer")
	print("Unmodified SeaBIOS booted FreeDOS from floppy and FreeDOS ran VER")
end
