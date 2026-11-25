local FrameBudget = require("../src/FrameBudget")
local Machine = require("../src/Machine")
local decode = require("../src/MediaDecode")

local scheduler = FrameBudget.new(Machine.PIT_HZ)
for _ = 1, 10 do
	local credit, budget = scheduler:beginFrame(1 / 60, true)
	assert(budget == 0.004)
	scheduler:endFrame(credit, 0.002, 0)
end
for _, rate in { 60, 50, 30 } do
	for _ = 1, 120 do
		local credit, budget = scheduler:beginFrame(1 / rate, true)
		assert(credit <= Machine.PIT_HZ / 10, "Catch-up must remain bounded")
		assert(budget >= 0.002 and budget <= 0.012)
		scheduler:endFrame(100, budget, 0)
	end
	local limit = math.min(0.012, 0.5 / rate)
	assert(math.abs(scheduler.budget - limit) < 1e-8, "A lagging guest needs a share of slow and fast frames")
end
scheduler:endFrame(0, scheduler.budget, 0.008)
local _, repaintBudget = scheduler:beginFrame(1 / 30, true)
assert(math.abs(repaintBudget - 0.004) < 1e-9, "A slow repaint must reserve time before the next slice")
for _ = 1, 120 do
	local _, budget = scheduler:beginFrame(1 / 30, true)
	scheduler:endFrame(100, budget, 0)
end
assert(math.abs(scheduler.budget - 0.012) < 1e-9, "Repaint reserve must decay")
local frameTime = scheduler.frameTime
local resumedCredit, _ = scheduler:beginFrame(1, true)
assert(
	scheduler.frameTime == frameTime and resumedCredit <= Machine.PIT_HZ / 10,
	"Pauses must not amplify the estimate"
)
local _, fixedBudget = scheduler:beginFrame(1 / 30, false)
assert(fixedBudget == 0.004, "The baseline should use the fixed budget")
print("Adaptive budget kept working at 30–60 FPS, reserved time for repaint, and bounded catch-up")

local indexed = FrameBudget.new(Machine.PIT_HZ)
for _ = 1, 120 do
	local _, budget = indexed:beginFrame(1 / 30, true, true)
	indexed:endFrame(100, budget, 0.002)
end
assert(math.abs(indexed.budget - 0.014) < 1e-8, "Indexed VGA must reserve time for the display")
local _, planarBudget = indexed:beginFrame(1 / 30, true, false)
assert(math.abs(planarBudget - 0.010) < 1e-8, "Planar VGA must return to the regular CPU budget")

local Pit = require("../src/Pit8253")
local interrupts = 0
local pit = Pit.new(function()
	interrupts += 1
end)
assert(pit:clocksUntilIrq() == math.huge)
pit:write(0x43, 0x10)
pit:write(0x40, 7)
pit:advance(6)
assert(interrupts == 0 and pit:clocksUntilIrq() == 1)
pit:advance(2)
assert(interrupts == 1 and pit:clocksUntilIrq() == math.huge)
pit:advance(90)
assert(interrupts == 1)
pit:write(0x43, 0x14)
pit:write(0x40, 16)
pit:advance(33)
assert(interrupts == 2 and pit:clocksUntilIrq() == 15, "A batch must keep the PIT period aligned")
pit:write(0x43, 0)
assert(pit:clocksUntilIrq() == 15, "Latching a reading must preserve the pending IRQ")
pit:write(0x43, 0x14)
pit:advance(15)
assert(interrupts == 2 and pit:clocksUntilIrq() == math.huge, "Reprogramming the PIT stops the old timer")
pit:write(0x40, 16)
pit:advance(16)
assert(interrupts == 3 and pit:clocksUntilIrq() == 16)
pit:write(0x43, 0x54)
pit:write(0x41, 4)
assert(pit:advance(3) == 0, "DMA refresh must wait for its deadline")
assert(pit:advance(10) == 3 and pit:clocksUntilIrq() == 3, "DMA refresh must retain its own period")
pit:write(0x43, 0x50)
assert(pit:advance(3) == 0 and interrupts == 4, "Reprogramming refresh must leave the IRQ timer running")
print("PIT deadlines preserved one-shot, periodic, latch, and reprogramming behavior")

local media = "../src/media/"
local rom, disk, atRom =
	decode(require(media .. "Bios")), decode(require(media .. "Disk")), decode(require(media .. "AtBios"))

local function program(bytes, count, source, target, interrupts)
	local machine = Machine.new(rom, disk, nil, nil, atRom)
	local cpu, memory = machine.cpu, machine.bus.memory
	cpu:loadSegment(2, 0)
	cpu.ip = 0x500
	buffer.writestring(memory, 0x500, bytes)
	cpu:setRegister(1, true, count)
	cpu:setRegister(4, true, 0x7000)
	cpu:setRegister(6, true, source)
	cpu:setRegister(7, true, target)
	cpu.flags = if interrupts then 0x202 else 2
	return machine, cpu, memory
end

local movsb = string.char(0xF3, 0xA4)
local machine, cpu, memory = program(movsb, 80, 0x2000, 0x3000, true)
local source = string.rep("01234567", 10)
buffer.writestring(memory, 0x2000, source)
machine:step()
assert(machine.board.pit.now == 64 and cpu.ip == 0x500 and cpu:getRegister(1, true) == 16)
machine:step()
assert(machine.board.pit.now == 80 and cpu.ip == 0x502 and buffer.readstring(memory, 0x3000, 80) == source)

machine, cpu, memory = program(string.char(0x66, 0xF3, 0xAB), 12, 0, 0x3012, false)
cpu:setRegister(0, 32, 0x7F112233)
machine:step()
assert(machine.board.pit.now == 12 and cpu:getRegister(7, true) == 0x3042)
for offset = 0x3012, 0x3041, 4 do
	assert(buffer.readu32(memory, offset) == 0x7F112233)
end

machine, cpu, memory = program(movsb, 4, 0x2000, 0x2001, true)
buffer.writestring(memory, 0x2000, "ABCDE")
for _ = 1, 4 do
	machine:step()
end
assert(buffer.readstring(memory, 0x2000, 5) == "AAAAA", "An overlapping forward copy must see its own writes")

machine, cpu, memory = program(movsb, 2, 0x2000, 0xFFFF, true)
buffer.writestring(memory, 0x2000, "AB")
machine:step()
machine:step()
assert(buffer.readu8(memory, 0xFFFF) == 65 and buffer.readu8(memory, 0) == 66, "A 16-bit index must wrap")

machine, cpu, memory = program(string.char(0xF3, 0xAA), 4, 0, 0x000E, true)
cpu:loadSegment(1, 0xFFFF)
cpu:setRegister(0, false, 0x34)
for _ = 1, 4 do
	if cpu:getRegister(1, true) == 0 then
		break
	end
	machine:step()
end
assert(buffer.readu16(memory, 0) == 0x3434, "A20 wrap must still map writes to low RAM")

machine.bus.a20 = true
cpu:writeLinear(0x100003, 4, 0xA1B2C3D4)
assert(cpu:readLinear(0x100003, 4) == 0xA1B2C3D4)
machine.bus.a20 = false
buffer.writeu32(memory, 3, 0x12345678)
assert(cpu:readLinear(0x100003, 4) == 0x12345678, "Unpaged extended memory still respects A20")

machine, cpu, memory = program(movsb, 2, 0x2000, 0x500, true)
buffer.writeu8(memory, 0x2000, 0xF4)
machine:step()
assert(cpu:getRegister(1, true) == 1)
machine:step()
assert(cpu.halted, "A write to the running instruction must be visible on the next fetch")

machine, cpu, memory = program(movsb, 32, 0x2000, 0x3000, true)
machine.bus:writePort(0x21, 0xFE)
machine.bus:writePort(0x43, 0x30)
machine.bus:writePort(0x40, 7)
machine.bus:writePort(0x40, 0)
buffer.writeu16(memory, 8 * 4, 0x600)
buffer.writeu8(memory, 0x600, 0xF4)
machine:step()
assert(machine.board.pit.now == 7 and cpu:getRegister(1, true) == 25 and cpu.ip == 0x500)
machine:step()
assert(cpu.halted and buffer.readu16(memory, 0x6FFA) == 0x500, "A PIT IRQ must resume at the REP prefix")
print("386 REP verified RAM copies, fills, overlap, address and A20 wraps, self-modifying code, and IRQ boundaries")
