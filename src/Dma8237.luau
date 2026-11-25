local band, bor, bnot = bit32.band, bit32.bor, bit32.bnot
local PAGE_CHANNEL = { [0x81] = 2, [0x82] = 3, [0x83] = 1, [0x87] = 0 }

local Dma = {}
Dma.__index = Dma

function Dma.new()
	local channels = {}
	for channel = 0, 3 do
		channels[channel] = { address = 0, count = 0, baseAddress = 0, baseCount = 0, page = 0, mode = 0 }
	end
	return setmetatable({
		channels = channels,
		upper = false,
		mask = 0xF,
		status = 0,
		command = 0,
	}, Dma)
end

function Dma:read(port)
	if port < 8 then
		local channel = self.channels[math.floor(port / 2)]
		local value = port % 2 == 0 and channel.address or channel.count
		local result = self.upper and bit32.rshift(value, 8) or band(value, 0xFF)
		self.upper = not self.upper
		return result
	elseif port == 8 then
		local status = self.status
		self.status = 0
		return status
	elseif PAGE_CHANNEL[port] ~= nil then
		return self.channels[PAGE_CHANNEL[port]].page
	end
	return 0xFF
end

function Dma:write(port, value)
	if port < 8 then
		local channel = self.channels[math.floor(port / 2)]
		local current = port % 2 == 0 and channel.address or channel.count
		local result = self.upper and bor(band(current, 0xFF), value * 256) or bor(band(current, 0xFF00), value)
		self.upper = not self.upper
		if port % 2 == 0 then
			channel.address, channel.baseAddress = result, result
		else
			channel.count, channel.baseCount = result, result
		end
	elseif port == 8 then
		self.command = value
	elseif port == 0xA then
		local channelMask = bit32.lshift(1, band(value, 3))
		self.mask = band(value, 4) ~= 0 and bor(self.mask, channelMask) or band(self.mask, bnot(channelMask))
	elseif port == 0xB then
		self.channels[band(value, 3)].mode = value
	elseif port == 0xC then
		self.upper = false
	elseif port == 0xD then
		self.upper, self.mask, self.status, self.command = false, 0xF, 0, 0
	elseif port == 0xE then
		self.mask = 0
	elseif port == 0xF then
		self.mask = band(value, 0xF)
	elseif PAGE_CHANNEL[port] ~= nil then
		self.channels[PAGE_CHANNEL[port]].page = value
	end
end

function Dma:refresh(requests)
	if band(self.mask, 1) ~= 0 or band(self.command, 4) ~= 0 then
		return
	end
	local channel = self.channels[0]
	local direction = band(channel.mode, 0x20) ~= 0 and -1 or 1
	if requests > channel.count then
		self.status = bor(self.status, 1)
		if band(channel.mode, 0x10) ~= 0 then
			requests = (requests - channel.count - 1) % (channel.baseCount + 1)
			channel.address, channel.count = channel.baseAddress, channel.baseCount
		end
	end
	channel.address = band(channel.address + direction * requests, 0xFFFF)
	channel.count = band(channel.count - requests, 0xFFFF)
end

function Dma:readAudioByte(bus, index)
	local mask = bit32.lshift(1, index)
	local channel = self.channels[index]
	if band(self.mask, mask) ~= 0 or band(self.command, 4) ~= 0 or band(channel.mode, 0x0C) ~= 8 then
		return nil
	end
	local value = bus:read8(channel.page * 0x10000 + channel.address)
	local direction = band(channel.mode, 0x20) ~= 0 and -1 or 1
	channel.address = band(channel.address + direction, 0xFFFF)
	if channel.count == 0 then
		self.status = bor(self.status, mask)
		if band(channel.mode, 0x10) ~= 0 then
			channel.address, channel.count = channel.baseAddress, channel.baseCount
		else
			channel.count = 0xFFFF
			self.mask = bor(self.mask, mask)
		end
	else
		channel.count -= 1
	end
	return value
end

function Dma:diskTransfer(bus, image, offset, length, writeDisk)
	local channel = self.channels[2]
	if band(self.mask, 4) ~= 0 or band(self.command, 4) ~= 0 then
		return 0, false
	end
	local mode = band(channel.mode, 0x0C)
	local expectedMode = writeDisk and 8 or 4
	if mode ~= expectedMode and (writeDisk or mode ~= 0) then
		return 0, false
	end
	local amount = math.min(length, channel.count + 1)
	if writeDisk and amount < length then
		-- A short DMA buffer cannot supply a full sector.
		return 0, false
	end
	local direction = band(channel.mode, 0x20) ~= 0 and -1 or 1
	for index = 0, amount - 1 do
		local address = channel.page * 0x10000 + channel.address
		if writeDisk then
			buffer.writeu8(image, offset + index, bus:read8(address))
		elseif mode == 4 then
			bus:write8(address, buffer.readu8(image, offset + index))
		end
		channel.address = band(channel.address + direction, 0xFFFF)
	end
	local terminal = amount == channel.count + 1
	channel.count = band(channel.count - amount, 0xFFFF)
	if terminal then
		self.status = bor(self.status, 4)
		if band(channel.mode, 0x10) ~= 0 then
			channel.address, channel.count = channel.baseAddress, channel.baseCount
		end
	end
	return amount, terminal
end

return Dma
