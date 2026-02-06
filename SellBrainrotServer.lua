local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Catalog = require(game.ServerScriptService:WaitForChild("AssetCatalog"))
local sellRemote = ReplicatedStorage:WaitForChild("BrainrotSell")

local function getPrice(modelName)
	local def = Catalog[modelName]
	if not def then return 0 end
	if def.Price then return def.Price end
	if def.MiningPower then return (tonumber(def.MiningPower) or 0) * 5 end
	return 0
end

local function removeOneTool(player, modelName)
	local function try(container)
		if not container then return false end
		for _, t in ipairs(container:GetChildren()) do
			if t:IsA("Tool") and t.Name == modelName then
				local amt = tonumber(t:GetAttribute("amount")) or 1
				if amt > 1 then
					t:SetAttribute("amount", amt - 1)
				else
					t:Destroy()
				end
				return true
			end
		end
		return false
	end
	if try(player.Character) then return true end
	return try(player:FindFirstChild("Backpack"))
end

sellRemote.OnServerEvent:Connect(function(player, modelName)
	if type(modelName) ~= "string" or modelName == "" then
		sellRemote:FireClient(player, false, "Kein Item ausgerüstet.")
		return
	end
	local price = getPrice(modelName)
	if price <= 0 then
		sellRemote:FireClient(player, false, "Nicht verkaufbar.")
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats")
	local gold = leaderstats and leaderstats:FindFirstChild("Gold")
	if not gold then
		sellRemote:FireClient(player, false, "Gold nicht gefunden.")
		return
	end

	if not removeOneTool(player, modelName) then
		sellRemote:FireClient(player, false, "Kein passendes Tool gefunden.")
		return
	end

	gold.Value += price
	sellRemote:FireClient(player, true, ("Verkauft für %d Gold"):format(price))
end)
