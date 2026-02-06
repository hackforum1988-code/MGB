-- Leaderstats.lua (ServerScriptService)
local Players = game:GetService("Players")

Players.PlayerAdded:Connect(function(player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"  -- exakt so: kleingeschrieben
	leaderstats.Parent = player

	local gold = Instance.new("IntValue")
	gold.Name = "Gold"
	gold.Value = 0
	gold.Parent = leaderstats

	print("✅ " .. player.Name .. " Leaderstats ready")
end)

Players.PlayerRemoving:Connect(function(player)
	-- optional cleanup
end)

print("🧾 Leaderstats service running")
