local VIDEO_BASE = 0xB8000
local COLUMNS, ROWS = 80, 25

local function readScreen(bus, board)
	local start = board and buffer.readu8(board.crtc, 12) * 256 + buffer.readu8(board.crtc, 13) or 0
	local rows = table.create(ROWS)
	local characters = table.create(COLUMNS)
	for row = 0, ROWS - 1 do
		for column = 0, COLUMNS - 1 do
			local code = bus:read8(VIDEO_BASE + bit32.band(start + row * COLUMNS + column, 0x1FFF) * 2)
			characters[column + 1] = code >= 32 and code <= 126 and string.char(code) or " "
		end
		rows[row + 1] = table.concat(characters)
	end
	return table.concat(rows, "\n")
end

return readScreen
