local Bus = require("../src/Bus")
local Cpu8088 = require("../src/Cpu8088")
local diagnosticRom = require("../src/DiagnosticRom")
local readScreen = require("../src/TextScreen")

local bus = Bus.new()
bus:mountSystemRom(diagnosticRom)
assert(bus:read8(0xFFFF0) == 0xEA, "Reset vector must begin with a far jump")
bus:write8(0xFFFF0, 0)
assert(bus:read8(0xFFFF0) == 0xEA, "System ROM must be read-only")
bus:write8(0x100000, 0xA5)
assert(bus:read8(0) == 0xA5, "Bus should wrap at 20 bits")
assert(bus:read8(0xA0000) == 0xFF, "Unmapped memory should read as open bus")

local cpu = Cpu8088.new(bus)
for _ = 1, 512 do
	if cpu.halted then
		break
	end
	cpu:step()
end

assert(cpu.halted, "Guest should reach HLT")
local expected = "8088 DIAGNOSTIC OK"
assert(string.sub(readScreen(bus), 1, #expected) == expected, "Guest should print the diagnostic success message")
assert(bus:read8(0xB8001) == 0x07, "Guest STOSW should write the video attribute")
assert(cpu.r[5] == 0x7000, "INT/IRET should leave the stack balanced")
assert(bus:read8(0x6FFE) == 0x88 and bus:read8(0x6FFF) == 0x80, "BP should address through SS")

-- PUSH SP records the decremented value on the 8088.
bus:write8(0, 0x54)
bus:write8(1, 0x58)
cpu.s[2], cpu.ip, cpu.halted = 0, 0, false
cpu:step()
cpu:step()
assert(cpu.r[1] == 0x6FFE, "PUSH SP should push the decremented SP")
assert(cpu.r[5] == 0x7000, "PUSH/POP should leave the stack balanced")

print(expected)
