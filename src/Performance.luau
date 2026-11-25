local Performance = {}
Performance.__index = Performance

local function p95(samples)
	table.sort(samples)
	return samples[math.ceil(#samples * 0.95)]
end

function Performance.new(gui, clockRate)
	local folder = Instance.new("Folder")
	folder.Name = "Performance"
	folder:SetAttribute("AdaptiveCpu", true)

	local marker = Instance.new("BindableEvent")
	marker.Name = "Mark"
	marker.Parent = folder

	local self = setmetatable({
		folder = folder,
		clockRate = clockRate,
		frameSamples = {},
		cpuSamples = {},
		vgaSamples = {},
		vgaConvertSamples = {},
		vgaUploadSamples = {},
		vgaBytes = {},
		mouseSamples = {},
	}, Performance)
	marker.Event:Connect(function(label)
		self:mark(label)
	end)
	folder.Parent = gui
	return self
end

function Performance:clearSamples()
	table.clear(self.frameSamples)
	table.clear(self.cpuSamples)
	table.clear(self.vgaSamples)
	table.clear(self.vgaConvertSamples)
	table.clear(self.vgaUploadSamples)
	table.clear(self.vgaBytes)
	table.clear(self.mouseSamples)
	self.elapsed, self.clocks, self.uploads = 0, 0, 0
end

function Performance:start(profile, poweredAt, startedAt)
	self.poweredAt, self.startedAt = poweredAt, startedAt
	self.doomStartedAt, self.firstVga, self.lastMouseAt, self.pendingMouseAt = nil, false, nil, nil
	self:clearSamples()
	local folder = self.folder
	for _, attribute in
		{
			"FirstVgaMs",
			"WindowsDesktopMs",
			"DoomFirstPlayableMs",
			"RobloxFrameP95Ms",
			"CpuP95Ms",
			"VgaP95Ms",
			"VgaConvertP95Ms",
			"VgaUploadP95Ms",
			"VgaUploadP95KiB",
			"CpuBudgetMs",
			"GuestClockPercent",
			"PresentedVgaFps",
			"MouseToUploadP95Ms",
		}
	do
		folder:SetAttribute(attribute, nil)
	end
	folder:SetAttribute("Profile", profile)
	folder:SetAttribute("DiskLoadMs", (startedAt - poweredAt) * 1000)
end

function Performance:mark(label)
	local now = os.clock()
	if
		label == "Windows desktop"
		and self.poweredAt
		and self.folder:GetAttribute("Profile") == "386 Windows 3.0"
		and self.folder:GetAttribute("WindowsDesktopMs") == nil
	then
		self.folder:SetAttribute("WindowsDesktopMs", (now - self.poweredAt) * 1000)
	elseif label == "Doom command" and self.poweredAt then
		self.doomStartedAt = now
		self.folder:SetAttribute("DoomFirstPlayableMs", nil)
	elseif label == "Doom playable" and self.doomStartedAt then
		self.folder:SetAttribute("DoomFirstPlayableMs", (now - self.doomStartedAt) * 1000)
		self.doomStartedAt = nil
	end
end

function Performance:recordVga(convertSeconds, uploadSeconds, bytes)
	table.insert(self.vgaConvertSamples, convertSeconds * 1000)
	table.insert(self.vgaUploadSamples, uploadSeconds * 1000)
	table.insert(self.vgaBytes, bytes / 1024)
end

function Performance:frame(elapsed, clocks, cpuSeconds, vgaSeconds, budget, presented, mouseAt)
	self.elapsed += elapsed
	self.clocks += clocks
	table.insert(self.frameSamples, elapsed * 1000)
	table.insert(self.cpuSamples, cpuSeconds * 1000)
	table.insert(self.vgaSamples, vgaSeconds * 1000)
	if mouseAt and mouseAt ~= self.lastMouseAt then
		self.lastMouseAt, self.pendingMouseAt = mouseAt, mouseAt
	end
	if presented then
		local now = os.clock()
		self.uploads += 1
		if not self.firstVga then
			self.firstVga = true
			self.folder:SetAttribute("FirstVgaMs", (now - self.startedAt) * 1000)
		end
		if self.pendingMouseAt then
			table.insert(self.mouseSamples, (now - self.pendingMouseAt) * 1000)
			self.pendingMouseAt = nil
		end
	end
	if self.elapsed >= 2 then
		local folder = self.folder
		folder:SetAttribute("RobloxFrameP95Ms", p95(self.frameSamples))
		folder:SetAttribute("CpuP95Ms", p95(self.cpuSamples))
		folder:SetAttribute("VgaP95Ms", p95(self.vgaSamples))
		if #self.vgaBytes > 0 then
			folder:SetAttribute("VgaConvertP95Ms", p95(self.vgaConvertSamples))
			folder:SetAttribute("VgaUploadP95Ms", p95(self.vgaUploadSamples))
			folder:SetAttribute("VgaUploadP95KiB", p95(self.vgaBytes))
		end
		folder:SetAttribute("CpuBudgetMs", budget * 1000)
		folder:SetAttribute("GuestClockPercent", 100 * self.clocks / (self.elapsed * self.clockRate))
		folder:SetAttribute("PresentedVgaFps", self.uploads / self.elapsed)
		local mouseP95 = p95(self.mouseSamples)
		if mouseP95 then
			folder:SetAttribute("MouseToUploadP95Ms", mouseP95)
		end
		self:clearSamples()
	end
end

return Performance
