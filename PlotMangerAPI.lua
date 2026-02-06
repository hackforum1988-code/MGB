-- PlotMangerAPI.lua (ServerScriptService)
-- Platzieren/Restore von Brainrots mit Slot-basierter Yaw (Slots 1-5 = +90°, 6-10 = -90°)
-- Simple Debug-Ausgaben, damit wir sehen, ob Slot/Part/Model/Yaw gefunden werden.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local PERSIST_MODULE_NAME = "PlotPersistence"
local DEBUG = true
local function dprint(...)
	if DEBUG then
		print("[PlotMangerAPI]", ...)
	end
end

local brainrotsFolder = Workspace:FindFirstChild("Brainrots")
if not brainrotsFolder then
	brainrotsFolder = Instance.new("Folder")
	brainrotsFolder.Name = "Brainrots"
	brainrotsFolder.Parent = Workspace
	dprint("Created workspace.Brainrots folder")
end

local PlotManagerAPI = {}

local function findSlotInPlayerPlot(player, slotName)
	local plots = Workspace:FindFirstChild("Plots")
	if not plots then return nil, "no plots" end
	local plotName = player:GetAttribute("PlotName")
	if not plotName then return nil, "no plot for player" end
	local plot = plots:FindFirstChild(plotName)
	if not plot then return nil, "plot not found" end
	local slot = plot:FindFirstChild(slotName)
	if not slot then return nil, "slot not found" end
	return slot
end

local function findWorkspaceBrainrotBySlot(plotSlot, player)
	if not plotSlot then return nil end
	for _, obj in ipairs(brainrotsFolder:GetDescendants()) do
		if obj:IsA("Model") then
			local stored = obj:GetAttribute("StoredInSlot")
			local owner = obj:GetAttribute("Owner")
			if stored == plotSlot.Name and owner == player.Name then
				return obj
			end
		end
	end
	return nil
end

local function normalizePlacedBrainrot(model)
	local hasPrompt = false
	for _, pp in ipairs(model:GetDescendants()) do
		if pp:IsA("ProximityPrompt") then
			pcall(function()
				pp.ActionText = "Aufheben"
				pp.ObjectText = model.Name
				if pp.SetAttribute then pp:SetAttribute("Price", nil) end
			end)
			hasPrompt = true
		end
		if pp:IsA("BasePart") then
			pcall(function() pp.Anchored = true end)
		end
	end
	if not hasPrompt then
		local targetPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		if targetPart then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Aufheben"
			prompt.ObjectText = model.Name
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 10
			prompt.RequiresLineOfSight = false
			prompt.Parent = targetPart
		end
	end
end

-- DEFAULT: Slots 1-5 => +90°, Slots 6-10 => -90°
local DEFAULT_YAW_A = math.rad(90)
local DEFAULT_YAW_B = math.rad(-90)
local function getDefaultYawForSlotName(slotName)
	if type(slotName) ~= "string" then return DEFAULT_YAW_A end
	local num = tonumber(slotName:match("^Slot(%d+)"))
	if num and num >= 6 then
		return DEFAULT_YAW_B
	else
		return DEFAULT_YAW_A
	end
end

local function placeModelAtSlot(model, slotPosPart, slotName, overrideYaw)
	if not (model and slotPosPart) then
		dprint("placeModelAtSlot: missing model or slotPosPart for", slotName)
		return
	end
	local useYaw = overrideYaw
	if useYaw == nil then
		-- prefer model attribute Yaw (if present), else default for slot
		local attrYaw = nil
		pcall(function() attrYaw = model:GetAttribute("Yaw") end)
		if attrYaw ~= nil then
			useYaw = tonumber(attrYaw) or attrYaw
			dprint("placeModelAtSlot: using model attribute Yaw for", model.Name, "->", useYaw)
		else
			useYaw = getDefaultYawForSlotName(slotName)
			dprint("placeModelAtSlot: using default yaw for slot", slotName, "->", useYaw)
		end
	end

	local base = slotPosPart.CFrame * CFrame.new(0, 3, 0) * CFrame.Angles(0, useYaw, 0)
	if model.PrimaryPart then
		pcall(function() model:SetPrimaryPartCFrame(base) end)
	else
		pcall(function() model:PivotTo(base) end)
	end
	local ok = pcall(function() model:SetAttribute("Yaw", useYaw) end)
	dprint("placeModelAtSlot: placed", model.Name, "at", slotPosPart:GetFullName(), "yawUsed=", useYaw, "setAttributeOk=", ok)
end

function PlotManagerAPI.PlaceInSlot(player, slotName, brainrotModelInstance, overrideYaw)
	if not player then return false, "invalid player" end
	local slot, err = findSlotInPlayerPlot(player, slotName)
	if not slot then
		dprint("PlaceInSlot: slot lookup failed:", err)
		return false, err or "no slot"
	end
	dprint("PlaceInSlot: found slot", slot:GetFullName(), "for player", player.Name)

	if findWorkspaceBrainrotBySlot(slot, player) then
		dprint("PlaceInSlot: slot already occupied", slotName)
		return false, "slot occupied"
	end

	if not (brainrotModelInstance and brainrotModelInstance:IsA("Model")) then
		dprint("PlaceInSlot: invalid model instance provided")
		return false, "no model provided"
	end

	local placed = brainrotModelInstance
	placed.Parent = brainrotsFolder

	normalizePlacedBrainrot(placed)

	placed:SetAttribute("StoredInSlot", slot.Name)
	placed:SetAttribute("Owner", player.Name)
	placed:SetAttribute("Owned", true)

	local slotPosPart = nil
	if slot:IsA("BasePart") then slotPosPart = slot end
	if not slotPosPart then
		slotPosPart = slot:FindFirstChild("Placement") or slot:FindFirstChildWhichIsA("BasePart")
	end
	if not slotPosPart then
		dprint("PlaceInSlot: no placement part found for slot", slotName)
	end

	pcall(function()
		placeModelAtSlot(placed, slotPosPart or slot, slot.Name, overrideYaw)
	end)

	-- persist
	local ok, PlotPersistence = pcall(function() return require(game.ServerScriptService:WaitForChild(PERSIST_MODULE_NAME)) end)
	if ok and PlotPersistence and type(PlotPersistence.SavePlayer) == "function" then
		pcall(function() PlotPersistence:SavePlayer(player) end)
		dprint("PlaceInSlot: SavePlayer called for", player.Name)
	else
		dprint("PlaceInSlot: PlotPersistence not available for saving")
	end

	dprint("PlaceInSlot: placed OK", placed.Name, "into", slot:GetFullName(), "for", player.Name)
	return true
end

function PlotManagerAPI.RemoveFromSlot(player, slotName)
	if not player then return false, "invalid player" end
	local slot, err = findSlotInPlayerPlot(player, slotName)
	if not slot then return false, err or "no slot" end

	local found = findWorkspaceBrainrotBySlot(slot, player)
	if not found then
		return false, "no brainrot in slot"
	end

	pcall(function() found:Destroy() end)

	local ok, PlotPersistence = pcall(function() return require(game.ServerScriptService:WaitForChild(PERSIST_MODULE_NAME)) end)
	if ok and PlotPersistence and type(PlotPersistence.SavePlayer) == "function" then
		pcall(function() PlotPersistence:SavePlayer(player) end)
		dprint("RemoveFromSlot: SavePlayer called for", player.Name)
	end

	dprint("RemoveFromSlot: removed for", player.Name, slotName)
	return true
end

return PlotManagerAPI
