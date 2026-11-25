local band, bor, bnot = bit32.band, bit32.bor, bit32.bnot

local function highestPriority(bits)
	return bits == 0 and 0 or band(bits, -bits)
end

local Pic = {}
Pic.__index = Pic

function Pic.new()
	return setmetatable({
		pending = 0,
		inService = 0,
		mask = 0xFF,
		vectorBase = 8,
		init = 0,
		readService = false,
		autoEoi = false,
	}, Pic)
end

function Pic:request(line)
	self.pending = bor(self.pending, 2 ^ line)
end

function Pic:ready()
	if self.pending == 0 then
		return nil
	end
	local nextBit = highestPriority(band(self.pending, bnot(self.mask)))
	local activeBit = highestPriority(self.inService)
	if nextBit == 0 or (activeBit ~= 0 and nextBit >= activeBit) then
		return nil
	end
	return nextBit
end

function Pic:acknowledge()
	local nextBit = self:ready()
	if not nextBit then
		return nil
	end
	self.pending = band(self.pending, bnot(nextBit))
	if not self.autoEoi then
		self.inService = bor(self.inService, nextBit)
	end
	return self.vectorBase + bit32.countrz(nextBit)
end

function Pic:read(port)
	if port == 0x21 then
		return self.mask
	end
	return self.readService and self.inService or self.pending
end

function Pic:write(port, value)
	if port == 0x20 then
		if band(value, 0x10) ~= 0 then
			self.init = 2
			self.hasCascade = band(value, 2) == 0
			self.needsIcw4 = band(value, 1) ~= 0
			self.mask, self.pending, self.inService = 0, 0, 0
			self.readService, self.autoEoi = false, false
		elseif band(value, 0x18) == 8 then
			if band(value, 2) ~= 0 then
				self.readService = band(value, 1) ~= 0
			end
		elseif band(value, 0x20) ~= 0 then
			local line = band(value, 0x40) ~= 0 and 2 ^ band(value, 7) or highestPriority(self.inService)
			self.inService = band(self.inService, bnot(line))
		end
	elseif self.init == 2 then
		self.vectorBase = band(value, 0xF8)
		self.init = self.hasCascade and 3 or (self.needsIcw4 and 4 or 0)
	elseif self.init == 3 then
		self.init = self.needsIcw4 and 4 or 0
	elseif self.init == 4 then
		self.autoEoi = band(value, 2) ~= 0
		self.init = 0
	else
		self.mask = value
	end
end

return Pic
