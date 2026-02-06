local Players = game:GetService("Players")
local player = Players.LocalPlayer

local function findPlot()
	local plots = workspace:FindFirstChild("Plots")
	local plotName = player:GetAttribute("PlotName")
	if plots and plotName then
		return plots:FindFirstChild(plotName)
	end
	-- Fallback: suche Plot mit Owner == player.Name
	if plots then
		for _, p in ipairs(plots:GetChildren()) do
			if p:GetAttribute("Owner") == player.Name then
				return p
			end
		end
	end
	return nil
end

local function findSpawn(plot)
	if not plot then return nil end
	return plot:FindFirstChild("Spawn") or plot:FindFirstChildWhichIsA("BasePart")
end

local function formatIncome(n)
	if n >= 1e9 then
		return string.format("%.1fB", n/1e9)
	elseif n >= 1e6 then
		return string.format("%.1fM", n/1e6)
	elseif n >= 1e3 then
		return string.format("%.1fk", n/1e3)
	else
		return tostring(math.floor(n))
	end
end

local function createBillboard(spawnPart)
	if not spawnPart then return nil end
	local old = spawnPart:FindFirstChild("IncomeBillboard")
	if old then old:Destroy() end

	local bb = Instance.new("BillboardGui")
	bb.Name = "IncomeBillboard"
	bb.Adornee = spawnPart
	bb.Size = UDim2.new(0, 110, 0, 44) -- halb so groß
	bb.StudsOffset = Vector3.new(0, 3, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 250
	bb.Parent = spawnPart

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.BackgroundTransparency = 0.2
	frame.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
	frame.Parent = bb

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 4)
	padding.PaddingBottom = UDim.new(0, 4)
	padding.PaddingLeft = UDim.new(0, 6)
	padding.PaddingRight = UDim.new(0, 6)
	padding.Parent = frame

	local uiList = Instance.new("UIListLayout")
	uiList.FillDirection = Enum.FillDirection.Vertical
	uiList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	uiList.VerticalAlignment = Enum.VerticalAlignment.Center
	uiList.SortOrder = Enum.SortOrder.LayoutOrder
	uiList.Padding = UDim.new(0, 2)
	uiList.Parent = frame

	local mainText = Instance.new("TextLabel")
	mainText.Size = UDim2.new(1, 0, 0, 22)
	mainText.BackgroundTransparency = 1
	mainText.Font = Enum.Font.GothamBlack
	mainText.TextScaled = true
	mainText.Text = "0 /s"
	mainText.TextColor3 = Color3.fromRGB(255, 255, 255)
	mainText.LayoutOrder = 1
	mainText.Parent = frame

	local subText = Instance.new("TextLabel")
	subText.Size = UDim2.new(1, 0, 0, 12)
	subText.BackgroundTransparency = 1
	subText.Font = Enum.Font.Gotham
	subText.TextScaled = true
	subText.Text = "Total Income"
	subText.TextColor3 = Color3.fromRGB(200, 200, 210)
	subText.LayoutOrder = 2
	subText.Parent = frame

	return mainText
end

local function startRainbow(label)
	task.spawn(function()
		local hue = 0
		while label and label.Parent do
			hue = (hue + 0.01) % 1
			label.TextColor3 = Color3.fromHSV(hue, 0.9, 1)
			task.wait(0.05)
		end
	end)
end

task.spawn(function()
	local plot, spawnPart, mainText
	while true do
		plot = findPlot()
		spawnPart = plot and findSpawn(plot)
		if spawnPart then break end
		task.wait(0.5)
	end

	mainText = createBillboard(spawnPart)
	if mainText then startRainbow(mainText) end

	local function update()
		if not mainText then return end
		local v = plot:GetAttribute("IncomePerSec") or 0
		mainText.Text = string.format("%s /s", formatIncome(v))
	end

	if plot then
		plot:GetAttributeChangedSignal("IncomePerSec"):Connect(update)
	end
	update()
end)
