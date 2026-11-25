local band, bor, lshift, rshift = bit32.band, bit32.bor, bit32.lshift, bit32.rshift

local QUEUE_LIMIT = 32
local BYTE_CLOCKS = 8949 -- 1200 baud, one start bit, seven data bits and one stop bit.
local SerialMouse = { BASE = 0x3F8 }
SerialMouse.__index = SerialMouse

function SerialMouse.new(requestInterrupt)
	return setmetatable({
		requestInterrupt = requestInterrupt,
		pending = {},
		bytes = {},
		buttons = 0,
		deliverAt = math.huge,
		divisorLow = 0,
		divisorHigh = 0,
		interruptEnable = 0,
		lineControl = 0,
		modemControl = 0,
		scratch = 0,
	}, SerialMouse)
end

function SerialMouse:interrupt()
	if self.received ~= nil and band(self.interruptEnable, 1) ~= 0 and band(self.modemControl, 8) ~= 0 then
		self.requestInterrupt()
	end
end

function SerialMouse:advance(now)
	local bytes = self.bytes
	if self.received ~= nil or (#bytes == 0 and #self.pending == 0) then
		self.deliverAt = math.huge
		return
	end
	if #bytes == 0 then
		local packet = table.remove(self.pending, 1)
		local dx, dy = band(packet.dx, 255), band(packet.dy, 255)
		self.packetMovedAt = if dx ~= 0 or dy ~= 0 then packet.movedAt else nil
		bytes[1] = bor(0x40, packet.buttons, rshift(band(dy, 0xC0), 4), rshift(dx, 6))
		bytes[2], bytes[3] = band(dx, 63), band(dy, 63)
	end
	self.received = table.remove(bytes, 1)
	if #bytes == 0 then
		self.receivedMotionAt, self.packetMovedAt = self.packetMovedAt, nil
	end
	self.deliverAt = now + BYTE_CLOCKS
	self:interrupt()
end

function SerialMouse:move(dx, dy, buttons, now, movedAt)
	if band(self.modemControl, 0x13) ~= 3 then
		return
	end
	dx, dy = math.round(dx), math.round(dy)
	buttons = band(buttons, 0x30)
	if dx == 0 and dy == 0 and self.buttons == buttons then
		return
	end
	self.buttons = buttons

	-- Coalesce motion until transmission starts. Keep separate reports for
	-- button transitions, even when the cursor has not moved.
	local pending = self.pending
	local last = pending[#pending]
	if last and last.buttons == buttons then
		last.dx = math.clamp(last.dx + dx, -128, 127)
		last.dy = math.clamp(last.dy + dy, -128, 127)
		last.movedAt = last.movedAt or movedAt
	else
		local nextIndex = math.min(#pending + 1, QUEUE_LIMIT)
		pending[nextIndex] = {
			dx = math.clamp(dx, -128, 127),
			dy = math.clamp(dy, -128, 127),
			buttons = buttons,
			movedAt = movedAt,
		}
	end
	if self.received == nil and self.deliverAt == math.huge then
		self.deliverAt = now + BYTE_CLOCKS
	end
end

function SerialMouse:read(port, now)
	local register = port - SerialMouse.BASE
	local divisor = band(self.lineControl, 0x80) ~= 0
	if register == 0 then
		if divisor then
			return self.divisorLow
		end
		local byte = self.received
		self.received = nil
		if self.receivedMotionAt then
			self.lastMotionReadAt, self.receivedMotionAt = self.receivedMotionAt, nil
		end
		if (#self.bytes > 0 or #self.pending > 0) and self.deliverAt == math.huge then
			self.deliverAt = now + BYTE_CLOCKS
		end
		return byte or 0
	elseif register == 1 then
		return if divisor then self.divisorHigh else self.interruptEnable
	elseif register == 2 then
		return if self.received ~= nil and band(self.interruptEnable, 1) ~= 0 then 4 else 1
	elseif register == 3 then
		return self.lineControl
	elseif register == 4 then
		return self.modemControl
	elseif register == 5 then
		return if self.received ~= nil then 0x61 else 0x60
	elseif register == 6 then
		local control = self.modemControl
		if band(control, 0x10) ~= 0 then
			return bor(lshift(band(control, 12), 4), lshift(band(control, 2), 3), lshift(band(control, 1), 5))
		end
		return if band(control, 3) == 3 then 0x30 else 0
	end
	return self.scratch
end

function SerialMouse:write(port, value, now)
	local register = port - SerialMouse.BASE
	local divisor = band(self.lineControl, 0x80) ~= 0
	if register == 0 then
		if divisor then
			self.divisorLow = value
		elseif band(self.modemControl, 0x10) ~= 0 then
			self.received = value
			self:interrupt()
		end
	elseif register == 1 then
		if divisor then
			self.divisorHigh = value
		else
			self.interruptEnable = band(value, 15)
			self:interrupt()
		end
	elseif register == 3 then
		self.lineControl = value
	elseif register == 4 then
		local wasPowered = band(self.modemControl, 0x13) == 3
		local powered = band(value, 0x13) == 3
		self.modemControl = band(value, 31)
		if wasPowered ~= powered then
			table.clear(self.pending)
			table.clear(self.bytes)
			self.buttons = 0
			self.received = nil
			self.packetMovedAt, self.receivedMotionAt, self.lastMotionReadAt = nil, nil, nil
			self.deliverAt = math.huge
			if powered then
				self.bytes[1] = 0x4D -- Microsoft serial mouse identification byte.
				self.deliverAt = now + 3 * BYTE_CLOCKS
			end
		end
		self:interrupt()
	elseif register == 7 then
		self.scratch = value
	end
end

return SerialMouse
