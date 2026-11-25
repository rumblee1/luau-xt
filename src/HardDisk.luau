local SECTOR_BYTES = 512
local SECTORS_PER_CYLINDER = 16 * 32
local CYLINDER_BYTES = SECTORS_PER_CYLINDER * SECTOR_BYTES
local FIRST_PORT = 0x340
local COMMAND_PORT = 0x347

local HardDisk = {}
HardDisk.__index = HardDisk

function HardDisk.new(bus, image)
	local size = buffer.len(image)
	local cylinders = size / CYLINDER_BYTES
	assert(cylinders >= 1 and cylinders <= 127 and size % CYLINDER_BYTES == 0, "Expected 1–127 whole disk cylinders")
	local mounted = buffer.create(size)
	buffer.copy(mounted, 0, image)
	return setmetatable({
		bus = bus,
		image = mounted,
		cylinders = cylinders,
		registers = buffer.create(7),
		status = 0,
	}, HardDisk)
end

function HardDisk:read(port)
	return port == COMMAND_PORT and self.status or buffer.readu8(self.registers, port - FIRST_PORT)
end

function HardDisk:write(port, byte)
	local registers = self.registers
	if port ~= COMMAND_PORT then
		buffer.writeu8(registers, port - FIRST_PORT, byte)
		return
	end

	if byte == 1 then -- Return the mounted disk's geometry.
		buffer.writeu16(registers, 0, self.cylinders * SECTORS_PER_CYLINDER)
		buffer.writeu8(registers, 2, self.cylinders - 1)
		self.status = 0
		return
	end

	local diskOffset = buffer.readu16(registers, 0) * SECTOR_BYTES
	local length = buffer.readu8(registers, 6) * SECTOR_BYTES
	if byte < 2 or byte > 4 or length == 0 or diskOffset + length > buffer.len(self.image) then
		self.status = 4
		return
	end

	if byte ~= 4 then -- Verify only checks the requested sector range.
		local offset = buffer.readu16(registers, 2)
		local segment = buffer.readu16(registers, 4)
		self.bus:transferDisk(self.image, diskOffset, segment, offset, length, byte == 3)
	end
	self.status = 0
end

return HardDisk
