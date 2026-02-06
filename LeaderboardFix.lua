local Players = game:GetService("Players")
local model = script.Parent
print("🔍 MAP LEADERBOARD v2 - 6 Spieler pro Instanz")

local gui = nil
for _, child in pairs(model:GetDescendants()) do
	if child:IsA("SurfaceGui") or child:IsA("BillboardGui") then
		gui = child
		print("✅ GUI gefunden:", child.Name)
		break
	end
end

if not gui then
	print("❌ KEINE GUI gefunden!")
	return
end

local frame = gui:FindFirstChild("ScrollingFrame") or gui:FindFirstChild("Frame")
if not frame then
	print("❌ KEIN Frame gefunden!")
	return
end

local function updateLeaderboard()
	for _, child in pairs(frame:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end

	local players = {}
	for _, player in pairs(Players:GetPlayers()) do
		if player.leaderstats and player.leaderstats.Gold then
			table.insert(players, {
				name = player.Name,
				gold = player.leaderstats.Gold.Value,
				rank = player.leaderstats.Rank.Value or 0
			})
		end
	end

	table.sort(players, function(a, b) 
		return a.gold > b.gold 
	end)

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 60)
	title.Text = "🏆 TOP 6 GOLD RUSH"
	title.TextColor3 = Color3.fromRGB(255, 215, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.Parent = frame

	for i, data in ipairs(players) do
		if i > 6 then break end  -- NUR TOP 6!

		local entry = Instance.new("TextLabel")
		entry.Size = UDim2.new(1, 0, 0, 35)
		entry.Position = UDim2.new(0, 0, 0, 65 + (i-1) * 38)
		entry.Text = string.format("#%d %s - %dg (R:%d)", i, data.name, data.gold, data.rank)
		entry.TextColor3 = i <= 3 and Color3.new(1,1,1) or Color3.new(0.8,0.8,0.8)
		entry.BackgroundColor3 = i <= 3 and Color3.fromRGB(50,50,50) or Color3.fromRGB(30,30,30)
		entry.Font = Enum.Font.Gotham
		entry.TextScaled = true
		entry.TextXAlignment = Enum.TextXAlignment.Left
		entry.Parent = frame
	end

	frame.CanvasSize = UDim2.new(0, 0, 0, 65 + math.min(6, #players) * 38)
end

spawn(function()
	while true do
		wait(2)
		pcall(updateLeaderboard)
	end
end)

print("✅ MAP LEADERBOARD v2 LIVE - TOP 6!")
