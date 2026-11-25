local band, bor = bit32.band, bit32.bor

local SECTOR_SIZE, SECTORS, HEADS, CYLINDERS = 512, 9, 2, 40
local IMAGE_SIZE = SECTOR_SIZE * SECTORS * HEADS * CYLINDERS
local COMMAND_LENGTH =
	{ [3] = 3, [4] = 2, [5] = 9, [6] = 9, [7] = 2, [8] = 1, [9] = 9, [10] = 2, [12] = 9, [13] = 6, [15] = 3 }

local Floppy = {}
Floppy.__index = Floppy

function Floppy.new(bus, dma, image, requestInterrupt)
	local mountedImage
	if image ~= nil then
		assert(buffer.len(image) == IMAGE_SIZE, "Expected a 360 KiB floppy image")
		mountedImage = buffer.create(IMAGE_SIZE)
		buffer.copy(mountedImage, 0, image)
	end
	return setmetatable({
		bus = bus,
		dma = dma,
		image = mountedImage,
		requestInterrupt = requestInterrupt,
		control = 0,
		command = {},
		result = {},
		resultIndex = 1,
		sense = {},
		cylinder = { 0, 0, 0, 0 },
	}, Floppy)
end

function Floppy:interrupt()
	if band(self.control, 8) ~= 0 then
		self.requestInterrupt(6)
	end
end

function Floppy:controlWrite(value)
	local wasEnabled = band(self.control, 4) ~= 0
	self.control = value
	if band(value, 4) == 0 then
		table.clear(self.command)
		table.clear(self.result)
		table.clear(self.sense)
		self.resultIndex = 1
	elseif not wasEnabled then
		for drive = 0, 3 do
			self.sense[drive + 1] = { 0xC0 + drive, self.cylinder[drive + 1] }
		end
		self:interrupt()
	end
end

function Floppy:resultBytes(...)
	self.result = { ... }
	self.resultIndex = 1
end

function Floppy:transferData(command, drive, selectedHead, writeDisk)
	local cylinder, head, sector, size, endSector = command[3], command[4], command[5], command[6], command[7]
	local status = drive + selectedHead * 4
	if drive ~= 0 or self.image == nil then
		self:resultBytes(bor(status, 0x48), 4, 0, cylinder, head, sector, size)
		return
	end
	if
		cylinder ~= self.cylinder[1]
		or cylinder >= CYLINDERS
		or head >= HEADS
		or head ~= selectedHead
		or sector < 1
		or sector > SECTORS
		or size ~= 2
		or band(self.control, 0x18) ~= 0x18
	then
		self:resultBytes(bor(status, 0x40), 4, 0, cylinder, head, sector, size)
		return
	end

	local terminal = false
	-- A single-sector transfer can reach DMA terminal count even when the
	-- BIOS parameter table advertises an older, shorter track.
	local lastSector = math.clamp(endSector, sector, SECTORS)
	while true do
		local offset = ((cylinder * HEADS + head) * SECTORS + sector - 1) * SECTOR_SIZE
		local amount
		amount, terminal = self.dma:diskTransfer(self.bus, self.image, offset, SECTOR_SIZE, writeDisk)
		if terminal or amount < SECTOR_SIZE then
			break
		end
		if sector == lastSector then
			if band(command[1], 0x80) ~= 0 and head == 0 then
				head, sector = 1, 1
			else
				break
			end
		else
			sector += 1
		end
	end
	if terminal then
		-- The BIOS uses CHRN to calculate how many sectors were transferred.
		if sector == endSector and head == 0 and band(command[1], 0x80) ~= 0 then
			head, sector = 1, 1
		elseif sector == endSector then
			cylinder, head, sector = cylinder + 1, 0, 1
		else
			sector += 1
		end
	end
	self:resultBytes(terminal and status or bor(status, 0x40), terminal and 0 or 0x80, 0, cylinder, head, sector, size)
end

function Floppy:execute(opcode, command)
	local unit = command[2] or 0
	local drive = band(unit, 3)
	local head = bit32.extract(unit, 2)
	if opcode == 3 then -- Specify
		return
	elseif opcode == 4 then -- Sense Drive Status
		local connected = drive == 0 and self.image ~= nil
		local trackZero = self.cylinder[drive + 1] == 0
		self:resultBytes(bor(band(unit, 7), connected and 0x28 or 0, trackZero and 0x10 or 0))
	elseif opcode == 7 or opcode == 15 then -- Recalibrate / Seek
		local cylinder = command[3] or 0
		self.cylinder[drive + 1] = cylinder
		table.clear(self.sense)
		self.sense[1] = { bor(0x20, band(unit, 7), drive == 0 and 0 or 0x50), cylinder }
		self:interrupt()
	elseif opcode == 8 then -- Sense Interrupt Status
		local status = table.remove(self.sense, 1)
		if status then
			self:resultBytes(status[1], status[2])
		else
			self:resultBytes(0x80)
		end
	elseif opcode == 5 or opcode == 6 or opcode == 12 then -- Write Data / Read Data / Read Deleted Data
		self:transferData(command, drive, head, opcode == 5)
		self:interrupt()
	elseif opcode == 10 then -- Read ID
		local connected = drive == 0 and self.image ~= nil
		self:resultBytes(
			bor(band(unit, 7), connected and 0 or 0x48),
			connected and 0 or 4,
			0,
			self.cylinder[drive + 1],
			head,
			1,
			2
		)
		self:interrupt()
	elseif opcode == 9 or opcode == 13 then -- Deleted data marks and track formatting
		self:resultBytes(
			bor(0x40, band(unit, 7)),
			4,
			0,
			self.cylinder[drive + 1],
			head,
			opcode == 9 and command[5] or 1,
			opcode == 9 and command[6] or command[3]
		)
		self:interrupt()
	else
		self:resultBytes(0x80)
	end
end

function Floppy:read(port)
	if port == 0x3F4 then
		if band(self.control, 4) == 0 then
			return 0
		elseif self.resultIndex <= #self.result then
			return 0xD0
		end
		return #self.command > 0 and 0x90 or 0x80
	elseif port == 0x3F5 then
		local value = self.result[self.resultIndex]
		if value ~= nil then
			self.resultIndex += 1
			return value
		end
	end
	return 0xFF
end

function Floppy:write(port, value)
	if port == 0x3F2 then
		self:controlWrite(value)
	elseif port == 0x3F5 and band(self.control, 4) ~= 0 and self.resultIndex > #self.result then
		local command = self.command
		table.insert(command, value)
		local opcode = band(command[1], 0x1F)
		if #command == (COMMAND_LENGTH[opcode] or 1) then
			self:execute(opcode, command)
			table.clear(command)
		end
	end
end

return Floppy
