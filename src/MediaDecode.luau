local encodingService
if script then
	local ok, service = pcall(game.GetService, game, "EncodingService")
	if ok then
		encodingService = service
	end
end

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local values = {}
for index = 1, #ALPHABET do
	values[string.byte(ALPHABET, index)] = index - 1
end

local function decode(source, destination, baseOffset)
	local result = destination or buffer.create(source.size)
	baseOffset = baseOffset or 0
	for _, chunk in source.chunks do
		local offset, data = baseOffset + chunk[1], chunk[2]
		if encodingService then
			buffer.copy(result, offset, encodingService:Base64Decode(buffer.fromstring(data)))
			continue
		end
		for index = 1, #data, 4 do
			local a, b, c, d = string.byte(data, index, index + 3)
			local low, high = values[c], values[d]
			local first = values[a] * 4 + math.floor(values[b] / 16)
			buffer.writeu8(result, offset, first)
			offset += 1
			if low ~= nil then
				buffer.writeu8(result, offset, values[b] % 16 * 16 + math.floor(low / 4))
				offset += 1
			end
			if high ~= nil then
				buffer.writeu8(result, offset, low % 4 * 64 + high)
				offset += 1
			end
		end
	end
	return result
end

return decode
