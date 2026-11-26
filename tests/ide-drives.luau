local Machine = require("../src/Machine")

local primary = buffer.create(256 * 1024)
local secondary = buffer.create(256 * 1024)
buffer.writeu32(primary, 0, 0x11112222)
buffer.writeu32(secondary, 0, 0x33334444)

local machine = Machine.newSeaBios(buffer.create(256 * 1024), buffer.create(512), nil, primary, secondary)

local function command(bus, drive, operation)
	bus:writePort(0x1F6, 0xE0 + drive * 16)
	bus:writePort(0x1F2, 1)
	bus:writePort(0x1F3, 0)
	bus:writePort(0x1F4, 0)
	bus:writePort(0x1F5, 0)
	bus:writePort(0x1F7, operation)
end

command(machine.bus, 0, 0x20)
assert(machine.bus:readIo(0x1F0, 4) == 0x11112222, "primary LBA read")
command(machine.bus, 1, 0x20)
assert(machine.bus:readIo(0x1F0, 4) == 0x33334444, "secondary LBA read")
command(machine.bus, 1, 0x30)
machine.bus:writeIo(0x1F0, 0x55556666, 4)
for _ = 2, 128 do
	machine.bus:writeIo(0x1F0, 0, 4)
end

machine = machine:restart()
command(machine.bus, 0, 0x20)
assert(machine.bus:readIo(0x1F0, 4) == 0x11112222, "secondary write did not modify the primary disk")
command(machine.bus, 1, 0x20)
assert(machine.bus:readIo(0x1F0, 4) == 0x55556666, "secondary write survived restart")

local oneDisk = Machine.newSeaBios(buffer.create(256 * 1024), buffer.create(512), nil, primary)
command(oneDisk.bus, 1, 0xEC)
assert(oneDisk.bus:readPort(0x1F7) == 0, "an unpopulated secondary slot reads as absent")
print("Primary and secondary IDE reads, writes, and restart passed")
