-- Sound Blaster 2.0 digital playback at 220h, using IRQ 5 and 8-bit DMA 1.
local SoundBlaster = { BASE = 0x220, IRQ = 5, DMA = 1 }
SoundBlaster.__index = SoundBlaster

local PARAMETERS = { [0x10] = 1, [0x14] = 2, [0x40] = 1, [0x48] = 2, [0x80] = 2, [0xE0] = 1, [0xE4] = 1 }

function SoundBlaster.new(bus, dma, clockRate, request)
	return setmetatable({
		bus = bus,
		dma = dma,
		clockRate = clockRate,
		request = request,
		responses = {},
		period = clockRate / 8000,
		block = 1,
		level = 128,
		enabled = false,
		resetHigh = false,
		irqPending = false,
		nextAt = math.huge,
		remaining = 0,
		test = 0,
	}, SoundBlaster)
end

function SoundBlaster:setLevel(value, now)
	self.level = value
	if self.audio then
		self.audio:setDac(self.enabled and (value - 128) / 160 or 0, now)
	end
end

function SoundBlaster:interrupt()
	if not self.irqPending then
		self.irqPending = true
		self.request()
	end
end

function SoundBlaster:read(port)
	local offset = port - SoundBlaster.BASE
	if offset == 0xA then
		return table.remove(self.responses, 1) or 0xFF
	elseif offset == 0xC then
		return 0 -- The command input is ready.
	elseif offset == 0xE then
		self.irqPending = false
		return #self.responses > 0 and 0x80 or 0
	end
	return 0xFF
end

function SoundBlaster:start(length, automatic, now)
	self.remaining, self.automatic = length, automatic
	self.paused, self.silence = false, false
	self.nextAt = now + self.period
end

function SoundBlaster:execute(command, low, high, now)
	if command == 0x10 then
		self:setLevel(low, now)
	elseif command == 0x14 then
		self:start(high * 256 + low + 1, false, now)
	elseif command == 0x1C or command == 0x90 or command == 0x91 then
		self:start(self.block, command ~= 0x91, now)
	elseif command == 0x40 then
		self.period = self.clockRate * ((256 - low) / 1_000_000)
	elseif command == 0x48 then
		self.block = high * 256 + low + 1
	elseif command == 0x80 then
		self:start(high * 256 + low + 1, false, now)
		self.silence = true
	elseif command == 0xD0 then
		self.paused = self.remaining > 0
		self.nextAt = math.huge
		self:setLevel(128, now)
	elseif command == 0xD4 and self.paused then
		self.paused = false
		self.nextAt = now + self.period
	elseif command == 0xD1 or command == 0xD3 then
		self.enabled = command == 0xD1
		self:setLevel(self.level, now)
	elseif command == 0xD8 then
		table.insert(self.responses, self.enabled and 0xFF or 0)
	elseif command == 0xDA then
		self.automatic = false
	elseif command == 0xE0 then
		table.insert(self.responses, 255 - low)
	elseif command == 0xE1 then
		table.insert(self.responses, 2)
		table.insert(self.responses, 1)
	elseif command == 0xE4 then
		self.test = low
	elseif command == 0xE8 then
		table.insert(self.responses, self.test)
	elseif command == 0xF2 then
		self:interrupt()
	end
end

function SoundBlaster:write(port, value, now)
	local offset = port - SoundBlaster.BASE
	if offset == 6 then
		if self.resetHigh and value % 2 == 0 then
			table.clear(self.responses)
			self.responses[1] = 0xAA
			self.command, self.low = nil, nil
			self.remaining, self.nextAt, self.block = 0, math.huge, 1
			self.period = self.clockRate / 8000
			self.enabled, self.irqPending, self.paused, self.silence = false, false, false, false
			self:setLevel(128, now)
		end
		self.resetHigh = value % 2 ~= 0
	elseif offset == 0xC and not self.resetHigh then
		local command = self.command
		if command then
			if PARAMETERS[command] == 2 and self.low == nil then
				self.low = value
			else
				self:execute(command, self.low or value, value, now)
				self.command, self.low = nil, nil
			end
		elseif PARAMETERS[value] then
			self.command = value
		else
			self:execute(value, 0, 0, now)
		end
	end
end

function SoundBlaster:advance(now)
	while self.nextAt <= now do
		local time = self.nextAt
		if self.remaining == 0 then
			self.nextAt = math.huge
			self:setLevel(128, time)
			return
		end
		local value = if self.silence then 128 else self.dma:readAudioByte(self.bus, SoundBlaster.DMA)
		if value == nil then
			self.nextAt = now + self.period
			return
		end
		self:setLevel(value, time)
		self.remaining -= 1
		self.nextAt += self.period
		if self.remaining == 0 then
			self.silence = false
			if self.automatic then
				self.remaining = self.block
			end
			self:interrupt()
		end
	end
end

return SoundBlaster
