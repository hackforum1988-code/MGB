-- PersistenceInit.lua
-- Restore Inventory + Placed Brainrots on PlayerAdded.
-- Inventory restore waits briefly so client-side inventory controller can initialize.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DEBUG = false
local function dprint(...) if DEBUG then print("[PersistenceInit]", ...) end end

local function waitForPlot(player, timeout)
	timeout = timeout or 10
	local t = 0
	while t < timeout do
		local plotName = player:GetAttribute("PlotName")
		if plotName then
			local plotsFolder = workspace:FindFirstChild("Plots")
			if plotsFolder then
				local plot = plotsFolder:FindFirstChild(plotName)
				if plot then return plot end
			end
		end
		task.wait(0.2); t = t + 0.2
	end
	return nil
end

local function waitForSlots(plot, timeout)
	timeout = timeout or 10
	local t = 0
	while t < timeout do
		for _, child in ipairs(plot:GetChildren()) do
			if (type(child.Name) == "string" and child.Name:match("^Slot")) or child:GetAttribute("IsSlot") or child:FindFirstChild("SlotMarker") then
				return true
			end
		end
		task.wait(0.2); t = t + 0.2
	end
	return false
end

local function waitForSpawnFunction(timeout)
	timeout = timeout or 10
	local t = 0
	while t < timeout do
		if type(_G.spawnBrainrotModel) == "function" then return true end
		task.wait(0.2); t = t + 0.2
	end
	return false
end

local function normalizePlacedModel(model)
	if not model then return end
	for _, pp in ipairs(model:GetDescendants()) do
		if pp:IsA("ProximityPrompt") then
			pcall(function()
				pp.ActionText = "Aufheben"
				pp.ObjectText = model.Name
				if pp.SetAttribute then pp:SetAttribute("Price", nil) end
			end)
		end
		if pp:IsA("BasePart") then
			pcall(function() pp.Anchored = true end)
		end
	end
end

local function getDefaultYawForSlotName(slotName)
	if type(slotName) ~= "string" then return math.rad(90) end
	local num = tonumber(slotName:match("^Slot(%d+)"))
	if num and num >= 6 then return math.rad(-90) else return math.rad(90) end
end

local function spawnCallback(plot, slotName, slotInfo)
	if type(_G.spawnBrainrotModel) ~= "function" then return nil end
	if not plot then return nil end
	local slot = plot:FindFirstChild(slotName)
	if not slot then return nil end

	local slotPosPart = nil
	if slot:IsA("BasePart") then slotPosPart = slot else slotPosPart = slot:FindFirstChild("Placement") or slot:FindFirstChildWhichIsA("BasePart") end
	local spawnPos = slot.Position + Vector3.new(0,3,0)
	if slotPosPart then spawnPos = slotPosPart.Position + Vector3.new(0,3,0) end

	local modelName = nil
	if slotInfo and type(slotInfo) == "table" then modelName = slotInfo.ModelName or slotInfo.Model end
	if not modelName then return nil end

	local def = { ModelName = modelName, Rarity = slotInfo and slotInfo.Rarity, MiningPower = slotInfo and slotInfo.MiningPower }
	local ownerName = plot:GetAttribute("Owner")
	local model = _G.spawnBrainrotModel(def.ModelName, def.ModelName, def, ownerName, spawnPos)
	if model then
		local s = model:FindFirstChild("StoredInSlot") or Instance.new("StringValue")
		s.Name = "StoredInSlot"; s.Value = slotName; s.Parent = model

		normalizePlacedModel(model)

		local savedYaw = nil
		if slotInfo and type(slotInfo) == "table" then savedYaw = slotInfo.Yaw or slotInfo.yaw end
		local useYaw = nil
		if savedYaw ~= nil then useYaw = tonumber(savedYaw) or savedYaw else useYaw = getDefaultYawForSlotName(slotName) end

		pcall(function()
			local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
			if primary and slotPosPart then
				local base = slotPosPart.CFrame * CFrame.new(0,3,0) * CFrame.Angles(0, useYaw, 0)
				if model.PrimaryPart then model:SetPrimaryPartCFrame(base) else model:PivotTo(base) end
			else
				local primary2 = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
				if primary2 then primary2.CFrame = CFrame.new(spawnPos) * CFrame.Angles(0, useYaw, 0) end
			end
			if model.SetAttribute then model:SetAttribute("Yaw", useYaw) end
		end)
	end
	return model
end

local function startIncomeCallback(model)
	if type(_G.startIncomeForPlaced) ~= "function" then return end
	pcall(function() _G.startIncomeForPlaced(model) end)
end

Players.PlayerAdded:Connect(function(player)
	player:WaitForChild("leaderstats", 10)

	-- Inventory restore (server-side): load items, wait so client can init, then recreate tools in Backpack
	local okInv, Inventory = pcall(function() return require(game.ServerScriptService:WaitForChild("InventoryServer")) end)
	if okInv and Inventory and type(Inventory.LoadForPlayer) == "function" then
		local okLoad, items = pcall(function() return Inventory:LoadForPlayer(player) end)
		items = okLoad and items or {}
		if type(items) ~= "table" then items = {} end

		-- Wait briefly so client inventory scripts can initialize (prevents missing ChildAdded handling)
		task.wait(0.8)

		local restored = 0
		for _, item in ipairs(items) do
			pcall(function()
				local back = player:FindFirstChild("Backpack") or player:WaitForChild("Backpack", 5)
				if not back then return end
				local tool = Instance.new("Tool")
				tool.Name = item.ModelName or item.Model or "Item"
				tool.RequiresHandle = false
				tool.CanBeDropped = false
				tool:SetAttribute("amount", item.Amount or item.amount or 1)
				tool:SetAttribute("rarity", item.Rarity or "Common")
				tool:SetAttribute("miningPower", item.MiningPower or 0)
				tool:SetAttribute("incomePerSec", item.IncomePerSec or 0)
				tool:SetAttribute("iconId", item.iconId or item.Icon or "")
				tool:SetAttribute("toolAdded", false)
				tool.Parent = back
				restored = restored + 1
			end)
		end
		dprint("PersistenceInit: restored inventory items:", restored)
	else
		dprint("PersistenceInit: InventoryServer missing or LoadForPlayer unavailable")
	end

	-- Plot restore
	local plot = waitForPlot(player)
	if not plot then warn("PersistenceInit: Plot not found for", player.Name); return end

	waitForSlots(plot)
	waitForSpawnFunction()

	task.wait(0.25)
	dprint("PersistenceInit: Starting restore for", player.Name)

	local ok, err = pcall(function()
		local PlotPersistence = require(game.ServerScriptService:WaitForChild("PlotPersistence"))
		if not PlotPersistence then dprint("PersistenceInit: PlotPersistence missing"); return end
		local res, rerr = PlotPersistence:RestorePlayer(player, spawnCallback, startIncomeCallback)
		dprint("PersistenceInit: RestorePlayer returned:", res, "err:", rerr)
	end)
	if not ok then warn("PersistenceInit: Restore failed for", player.Name, err) end
end)

Players.PlayerRemoving:Connect(function(player)
	dprint("PersistenceInit: Saving player on leave", player.Name)
	local ok, err = pcall(function()
		local PlotPersistence = require(game.ServerScriptService:WaitForChild("PlotPersistence"))
		PlotPersistence:SavePlayer(player)
	end)
	if not ok then warn("PersistenceInit: Save failed for", player.Name, err) end
end)
