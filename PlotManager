-- PlotManager.lua (ServerScriptService)
local Players = game:GetService("Players")
local plotsFolder = workspace:WaitForChild("Plots")

local function getFreePlot()
	for _, plot in ipairs(plotsFolder:GetChildren()) do
		if not plot:GetAttribute("Taken") then
			return plot
		end
	end
	return nil
end

local playerPlots = {}

Players.PlayerAdded:Connect(function(player)
	print("👤 " .. player.Name .. " joined - searching for plot...")

	if playerPlots[player.UserId] then
		print("⚠️ Player already has a plot assigned:", player.Name)
		return
	end

	local plot = getFreePlot()
	if not plot then
		warn("❌ No free plot for " .. player.Name)
		return
	end

	plot:SetAttribute("Taken", true)
	plot:SetAttribute("Owner", player.Name)
	player:SetAttribute("PlotName", plot.Name)
	playerPlots[player.UserId] = plot

	print("✅ " .. player.Name .. " assigned plot: " .. plot.Name)

	local charConn
	charConn = player.CharacterAdded:Connect(function(char)
		local hrp = char:WaitForChild("HumanoidRootPart", 10)
		local spawnPart = plot:FindFirstChild("Spawn")
		if hrp and spawnPart then
			hrp.CFrame = spawnPart.CFrame + Vector3.new(0, 3, 0)
			print("📍 " .. player.Name .. " spawned on " .. plot.Name)
		else
			warn("⚠️ Spawn part missing or HRP missing for " .. player.Name)
		end
	end)

	player.AncestryChanged:Connect(function()
		if not player:IsDescendantOf(game) then
			if charConn then charConn:Disconnect() end
		end
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	print("👋 " .. player.Name .. " leaving - saving plot state and releasing plot")

	-- 1) Save player state first
	local ok, PlotPersistence = pcall(function() return require(script.Parent:WaitForChild("PlotPersistence")) end)
	if ok and PlotPersistence then
		local saved, err = pcall(function() return PlotPersistence:SavePlayer(player) end)
		if saved then
			print("PlotManager: SavePlayer completed for", player.Name)
		else
			warn("PlotManager: SavePlayer failed for", player.Name, err)
		end
	else
		warn("PlotManager: Could not require PlotPersistence for saving")
	end

	-- 2) Now release the plot
	local plot = playerPlots[player.UserId]
	if plot then
		plot:SetAttribute("Taken", nil)
		plot:SetAttribute("Owner", nil)
		print("🔓 Plot " .. plot.Name .. " released")
		playerPlots[player.UserId] = nil
	else
		for _, p in ipairs(plotsFolder:GetChildren()) do
			if p:GetAttribute("Owner") == player.Name then
				p:SetAttribute("Taken", nil)
				p:SetAttribute("Owner", nil)
				print("🔓 Plot " .. p.Name .. " released (fallback)")
				break
			end
		end
	end
end)

print("🏗️ PlotManager ready")
