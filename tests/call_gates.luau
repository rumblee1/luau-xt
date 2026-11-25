local Bus = require("../src/Bus")
local Cpu386 = require("../src/Cpu386")

local function machine()
	local bus = Bus.new(true)
	local memory = bus.memory
	local cpu = Cpu386.new(bus)
	cpu.gdt = { base = 0x1000, limit = 0x7F }
	local function descriptor(slot, lo, hi)
		buffer.writeu32(memory, 0x1000 + slot * 8, lo)
		buffer.writeu32(memory, 0x1004 + slot * 8, hi)
	end
	descriptor(1, 0xFFFF, 0x9A00) -- Ring 0 code
	descriptor(2, 0xFFFF, 0x9200) -- Ring 0 data
	descriptor(3, 0xFFFF, 0xBA00) -- Ring 1 code
	descriptor(4, 0xFFFF, 0xB200) -- Ring 1 data
	descriptor(5, 0x20000067, 0x8100) -- 286 TSS at 0x2000
	descriptor(6, 0x00084000, 0xA401) -- 286 call gate with one parameter
	descriptor(7, 0xFFFF, 0xCF9200) -- Flat 386 data
	descriptor(8, 0x00084000, 0xAC01) -- 386 call gate with one parameter
	buffer.writeu16(memory, 0x2002, 0x8000)
	buffer.writeu16(memory, 0x2004, 0x10)
	cpu.control[0] = 0x11
	return cpu, memory
end

for _, width in { true, 32 } do
	local cpu, memory = machine()
	cpu.tr = cpu:descriptor(0x28)
	cpu.cpl = 1
	cpu:loadSegment(2, 0x19)
	cpu:loadSegment(3, 0x21)
	cpu.r[5] = 0x9000
	cpu.ip = 0x3000
	local gate = if width == 32 then 0x41 else 0x31
	local size = if width == 32 then 4 else 2
	local read = if width == 32 then buffer.readu32 else buffer.readu16
	buffer.writeu32(memory, 0x9000, 0x12345678)
	buffer.writestring(memory, 0x3000, string.char(0x9A, 0, 0, gate, 0))
	local returnBytes = string.char(0xCA, size, 0)
	buffer.writestring(memory, 0x4000, if width == 32 then string.char(0x66) .. returnBytes else returnBytes)
	cpu:step()
	assert(cpu.cpl == 0 and cpu:selector(2) == 0x08 and cpu:selector(3) == 0x10 and cpu.ip == 0x4000)
	local stack = cpu.r[5]
	assert(stack == 0x8000 - 5 * size)
	assert(read(memory, stack) == 0x3005 and read(memory, stack + size) == 0x19)
	assert(read(memory, stack + 2 * size) == (if width == 32 then 0x12345678 else 0x5678))
	assert(read(memory, stack + 3 * size) == 0x9000 and read(memory, stack + 4 * size) == 0x21)
	cpu:loadSegment(4, 0x10)
	cpu:step()
	assert(cpu.cpl == 1 and cpu:selector(2) == 0x19 and cpu:selector(3) == 0x21 and cpu.ip == 0x3005)
	assert(cpu.r[5] == 0x9000 + size and cpu.s[4].unusable)
end

local cpu = machine()
cpu:loadSegment(4, 0x38)
cpu.control[0] = 0x10
cpu:loadSegment(4, 0x20)
assert(cpu.s[4].limit == 0xFFFFFFFF and cpu.s[4].base == 0x200)
cpu:write(cpu.s[4], 0x11000, true, 0xBEEF)
assert(cpu:readLinear(0x11200, 2) == 0xBEEF)
print("386 call gates, outer-level far returns, and cached real-mode limits passed")

-- A demand-loaded code segment raises #NP at the call site with no
-- return address on the stack. The handler can install it and retry.
local caller, memory = machine()
caller:loadSegment(2, 0x08)
caller:loadSegment(3, 0x10)
caller.r[5], caller.ip = 0x9000, 0x3000
caller.idt = { base = 0x1800, limit = 0xFF }
buffer.writeu32(memory, 0x1858, 0x00085000)
buffer.writeu32(memory, 0x185C, 0x8600)
buffer.writeu32(memory, 0x1048, 0xFFFF)
buffer.writeu32(memory, 0x104C, 0x1A00)
buffer.writestring(memory, 0x3000, string.char(0x9A, 0, 0x40, 0x48, 0))
caller:step()
assert(caller.ip == 0x5000 and caller.r[5] == 0x8FF8)
assert(buffer.readu16(memory, 0x8FF8) == 0x48 and buffer.readu16(memory, 0x8FFA) == 0x3000)
buffer.writeu32(memory, 0x104C, 0x9A00)
caller:adjustStack(2)
caller:iret(true)
assert(caller.ip == 0x3000 and caller.r[5] == 0x9000)
caller:step()
assert(caller.ip == 0x4000 and caller.r[5] == 0x8FFC and buffer.readu16(memory, 0x8FFC) == 0x3005)
print("Faulting far calls leave a valid frame for demand loading and retry")
