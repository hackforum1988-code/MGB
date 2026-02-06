local Players = game:GetService("Players")

local rock = workspace:WaitForChild("SharedGoldRock")
local cd = rock:WaitForChild("ClickDetector")

local PAYOUT = 5       -- Gold pro Klick
local COOLDOWN = 0.3   -- Sekunden pro Spieler
cd.MaxActivationDistance = 16

local debounce = {}

cd.MouseClick:Connect(function(player)
	if debounce[player.UserId] then return end
	debounce[player.UserId] = true
	task.delay(COOLDOWN, function() debounce[player.UserId] = nil end)

	local stats = player:FindFirstChild("leaderstats")
	local gold = stats and stats:FindFirstChild("Gold")
	if gold then
		gold.Value += PAYOUT
	end
end)
