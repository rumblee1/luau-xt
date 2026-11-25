local Machine = require("../src/Machine")
local decode = require("../src/MediaDecode")
local readScreen = require("../src/TextScreen")
local keys = require("../src/Keyboard")

local boot = ... or "dos"
local postOnly = boot == "post"
local disk
if postOnly then
	disk = buffer.create(8 * 1024 * 1024)
else
	local media = { dos = "full_disk", grub = "grub_disk", linux = "linux_disk" }
	local folder = "../src/media/" .. assert(media[boot], "Use dos, grub, linux, or post") .. "/"
	local index = require(folder .. "Index")
	disk = buffer.create(index.size)
	for _, part in index.parts do
		decode(require(folder .. part[2]), disk, part[1])
	end
end

local machine = Machine.new(
	decode(require("../src/media/Bios")),
	decode(require("../src/media/Disk")),
	decode(require("../src/media/DiskRom")),
	disk,
	decode(require("../src/media/AtBios"))
)

local function runUntil(condition, blocks)
	for _ = 1, blocks do
		for _ = 1, 1024 do
			local cpu = machine.cpu
			local ip, cs = cpu.ip, cpu:selector(2)
			local ok, reason = pcall(machine.step, machine)
			if not ok then
				error(
					string.format("%04X:%08X CR0=%08X A20=%s\n", cs, ip, cpu.control[0], tostring(machine.bus.a20))
						.. tostring(reason)
						.. "\n"
						.. readScreen(machine.bus, machine.board),
					0
				)
			end
		end
		local text = readScreen(machine.bus, machine.board)
		if condition(text) then
			return
		end
	end
	local cpu = machine.cpu
	error(
		string.format(
			"386 milestone timeout at %04X:%08X\n%s",
			cpu:selector(2),
			cpu.ip,
			readScreen(machine.bus, machine.board)
		),
		0
	)
end

if postOnly then
	-- Report a different memory size through the motherboard CMOS.
	buffer.writeu16(machine.board.cmos, 0x17, 7 * 1024)
	buffer.writeu16(machine.board.cmos, 0x30, 7 * 1024)
end

local extended = postOnly and "7 MiB" or "15 MiB"
local capacity = postOnly and "8 MB" or "20 MB"
runUntil(function(text)
	return text:match("CPU%s+%[ i386 %]")
		and text:find("Extended RAM: " .. extended, 1, true)
		and text:find("[ " .. capacity .. " ]", 1, true)
end, 16000)
local post = readScreen(machine.bus, machine.board)
assert(post:find("640 KB", 1, true), post)
print("386 firmware displayed the CPU, conventional RAM, " .. extended .. " extended RAM, and " .. capacity .. " disk")
if postOnly then
	return
end

local function press(scan)
	machine.board:queueScanCode(scan)
	machine.board:queueScanCode(scan + 0x80)
	for _ = 1, 8192 do
		machine:step()
	end
end

local specialKeys = {
	["3"] = "Three",
	["8"] = "Eight",
	["6"] = "Six",
	["-"] = "Minus",
	["/"] = "Slash",
	[" "] = "Space",
}
local function typeText(line)
	for char in line:gmatch(".") do
		press(assert(keys[specialKeys[char] or char:upper()]))
	end
end

local function command(line)
	typeText(line)
	press(keys.Return)
end

if boot == "linux" then
	runUntil(function(text)
		return text:find("Linux 2.0.40 (FREESCO)", 1, true)
	end, 16000)
	press(keys.Return)
	local function atShell(text)
		return text:match("\n[#@] %s*$") ~= nil
	end
	runUntil(atShell, 42000)
	print("Linux 2.0.40 mounted the RAM disk and started ash")
	command("uname -a")
	runUntil(function(text)
		return atShell(text) and text:match("Linux%s+%S+%s+2%.0%.40") ~= nil
	end, 8000)
	command("ls /")
	runUntil(function(text)
		return atShell(text) and text:find("sbin", 1, true) and text:find("proc", 1, true)
	end, 8000)
	command("cd /tmp")
	runUntil(atShell, 8000)
	command("pwd")
	runUntil(function(text)
		return atShell(text) and text:match("\n/tmp%s*\n") ~= nil
	end, 8000)
	local shell = readScreen(machine.bus, machine.board)
	assert(not shell:find("is corrupt", 1, true), shell)
	print("Linux ran uname -a, ls, cd, and pwd without loader warnings")

	local function control(key)
		machine.board:queueScanCode(keys.LeftControl)
		press(keys[key])
		machine.board:queueScanCode(keys.LeftControl + 0x80)
	end

	command("nano /tmp/notes")
	runUntil(function(text)
		return text:find("nano 0.9.23", 1, true) ~= nil
	end, 8000)
	typeText("hello from nano")
	control("O")
	runUntil(function(text)
		return text:find("File Name to write", 1, true) ~= nil
	end, 2000)
	press(keys.Return)
	control("X")
	runUntil(atShell, 8000)
	command("sed -n p /tmp/notes")
	runUntil(function(text)
		return atShell(text) and text:match("\nhello from nano%s*\n") ~= nil
	end, 8000)
	print("GNU nano opened, saved a file and returned to ash")
	return
elseif boot == "grub" then
	runUntil(function(text)
		return text:find("Luau 386 - GRUB Legacy 0.97", 1, true) and text:find("Halt machine", 1, true)
	end, 16000)
	print("GRUB Legacy 0.97 reached its text menu")
	press(keys.Return)
	runUntil(function(text)
		return text:find("GRUB MULTIBOOT HANDOFF PASS", 1, true)
	end, 1000)
	print("GRUB accepted keyboard input and booted a Multiboot program into extended RAM")
	return
end

local function atPrompt(text)
	return text:match("C:\\>%s*$") ~= nil
end

runUntil(atPrompt, 14000)
print("386 booted FreeDOS")
command("cpu386")
runUntil(function(text)
	return text:find("386 REAL MODE PASS", 1, true) and atPrompt(text)
end, 4000)
print("386 real-mode registers, addressing and arithmetic passed")
command("pm386")
runUntil(function(text)
	return text:find("386 PROTECTED MODE AND PAGING PASS", 1, true)
end, 4000)
assert(machine.bus.a20)
assert(machine.cpu.control[2] == 0x401000)
assert(machine.bus:readPhysical32(0x100000) == 0x12345678)
print("386 protected mode, extended RAM, paging, and page fault return passed")
