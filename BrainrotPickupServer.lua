-- BrainrotPickupServer.lua (Server)
-- Held-models are welded to player's hand server-side, but parts are Massless and non-collidable to avoid pushing the player.
-- Robust detach & backpack-representation handling.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local DEBUG = true
local function dprint(...) if DEBUG then print("[BrainrotPickupServer]", ...) end end

local function ensureRemote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then r = Instance.new("RemoteEvent"); r.Name = name; r.Parent = ReplicatedStorage end
	return r
end

local pickupRemote = ensureRemote("BrainrotPickup")
local placeRemote  = ensureRemote("BrainrotPlace")
local equipReq     = ensureRemote("EquipRequest")
local equipResp    = ensureRemote("EquipResponse")

-- Inventory require (if any)
local Inventory = nil
local function tryRequireInventory()
	local ok, mod = pcall(function()
		local obj = game.ServerScriptService:FindFirstChild("InventoryServer")
		if obj then return require(obj) end
		return nil
	end)
	if ok and type(mod) == "table" then Inventory = mod; dprint("InventoryServer required"); return true end
	return false
end
tryRequireInventory()

-- Replicated templates
local modelsFolder = ReplicatedStorage:FindFirstChild("BrainrotModels")
if not modelsFolder then
	modelsFolder = Instance.new("Folder"); modelsFolder.Name = "BrainrotModels"; modelsFolder.Parent = ReplicatedStorage
end

local brainrotsFolder = Workspace:FindFirstChild("Brainrots")
if not brainrotsFolder then brainrotsFolder = Instance.new("Folder"); brainrotsFolder.Name = "Brainrots"; brainrotsFolder.Parent = Workspace end

local heldStorage = Workspace:FindFirstChild("HeldBrainrots")
if not heldStorage then heldStorage = Instance.new("Folder"); heldStorage.Name = "HeldBrainrots"; heldStorage.Parent = Workspace end

-- Helpers
local function ensurePrimary(model)
	if not model.PrimaryPart then
		for _, c in ipairs(model:GetDescendants()) do
			if c:IsA("BasePart") then
				model.PrimaryPart = c
				break
			end
		end
	end
	return model.PrimaryPart
end

local function setPartsMasslessAndNonCollide(model, flag)
	-- flag = true -> set Massless = true and CanCollide = false
	-- flag = false -> attempt to restore CanCollide = true and Massless = false
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			pcall(function()
				if flag then
					if p.SetNetworkOwner then p:SetNetworkOwner(nil) end
					p.CanCollide = false
				else
					p.CanCollide = true
				end
			end)
			pcall(function() p.Massless = (flag == true) end)
		end
	end
end

local function anchorModel(model)
	if not model then return end
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			pcall(function() p.Anchored = true; p.CanCollide = true end)
			pcall(function() if p.SetNetworkOwner then p:SetNetworkOwner(nil) end end)
		end
	end
end

local function unanchorAndGiveNetworkToPlayer(model, player)
	if not model or not player then return end
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			pcall(function() p.Anchored = false; p.CanCollide = false end)
			pcall(function() if p.SetNetworkOwner then p:SetNetworkOwner(player) end end)
		end
	end
end

local function removeWeldsFromPrim(prim)
	for _, child in ipairs(prim:GetChildren()) do
		if child:IsA("WeldConstraint") or child:IsA("Motor6D") then
			pcall(function() child:Destroy() end)
		end
	end
end

local function attachModelToCharacter(model, player)
	if not model or not player then return end
	local char = player.Character
	if not char then return end

	local targetPart = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm") or char:FindFirstChild("HumanoidRootPart")
	if not targetPart then return end

	local prim = ensurePrimary(model)
	if not prim then return end

	-- Make parts massless/non-collidable so they won't push the player
	setPartsMasslessAndNonCollide(model, true)

	-- Position once
	local offset = CFrame.new(0, -0.5, -0.5) * CFrame.Angles(0, math.rad(180), 0)
	pcall(function() prim.CFrame = targetPart.CFrame * offset end)

	-- remove existing welds on prim
	removeWeldsFromPrim(prim)

	-- Create a weld between prim and the targetPart to keep it stably attached server-side
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = prim
	weld.Part1 = targetPart
	weld.Parent = prim

	-- mark model as held
	pcall(function() model:SetAttribute("HeldBy", player.Name) end)

	dprint("Attached model", model.Name, "to", player.Name, "hand with weld")
end

local function detachModelFromCharacter(model)
	if not model then return end
	-- remove welds
	local prim = ensurePrimary(model)
	if prim then
		removeWeldsFromPrim(prim)
	end
	-- restore networkOwner nil and allow collisions after a short delay
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			pcall(function() if p.SetNetworkOwner then p:SetNetworkOwner(nil) end end)
			pcall(function() p.CanCollide = false end) -- keep false until placed (avoid immediate physics)
			pcall(function() p.Massless = true end)    -- keep massless to avoid sudden shove, will fully restore on placement
		end
	end
	pcall(function() model:SetAttribute("HeldBy", nil) end)
end

-- Tool/backpack helpers
local function backpackHasModel(player, modelName)
	local back = player:FindFirstChild("Backpack")
	if not back then return false end
	for _, t in ipairs(back:GetChildren()) do
		if t:IsA("Tool") then
			local mn = nil
			pcall(function() mn = (t.GetAttribute and (t:GetAttribute("ModelName") or t.Name)) or t.Name end)
			if mn == modelName or t.Name == modelName then return true end
		end
	end
	return false
end

local function giveToolToBackpack(player, item)
	if not player or type(item) ~= "table" then return nil end
	local back = player:FindFirstChild("Backpack") or player:WaitForChild("Backpack", 5)
	if not back then return nil end
	local modelName = item.ModelName or item.Model or item.Name or "Item"
	if backpackHasModel(player, modelName) then return nil end
	local tool = Instance.new("Tool")
	tool.Name = modelName
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	pcall(function() tool:SetAttribute("ModelName", modelName) end)
	pcall(function() tool:SetAttribute("amount", item.Amount or item.amount or 1) end)
	pcall(function() tool:SetAttribute("IncomePerSec", item.IncomePerSec or item.incomePerSec or 0) end)
	tool.Parent = back
	dprint("gave Tool to backpack for", player.Name, "->", tool.Name)
	return tool
end

local function dumpBackpackContents(player)
	local back = player:FindFirstChild("Backpack")
	if not back then return "(no backpack)" end
	local parts = {}
	for _, t in ipairs(back:GetChildren()) do
		if t:IsA("Tool") then
			local mn = nil
			pcall(function() mn = (t.GetAttribute and (t:GetAttribute("ModelName") or t.Name)) or t.Name end)
			table.insert(parts, tostring(t.Name) .. "[ModelName=" .. tostring(mn) .. "]")
		end
	end
	return table.concat(parts, " | ")
end

local function spawnModelByName(modelName, ownerName, spawnCFrame)
	local folder = ReplicatedStorage:FindFirstChild("BrainrotModels")
	if not folder then return nil end
	local template = folder:FindFirstChild(modelName)
	if not template or not template:IsA("Model") then return nil end
	local clone = template:Clone()
	clone.Name = modelName
	local ownerVal = Instance.new("StringValue"); ownerVal.Name = "Owner"; ownerVal.Value = ownerName or ""; ownerVal.Parent = clone
	clone.Parent = brainrotsFolder
	ensurePrimary(clone)
	if spawnCFrame and clone.PrimaryPart then pcall(function() clone:SetPrimaryPartCFrame(spawnCFrame) end) end
	return clone
end

-- Clear previous held model for player (return its representation to Backpack)
local function clearExistingHeld(player)
	for _, m in ipairs(heldStorage:GetChildren()) do
		if m:IsA("Model") then
			local ownerVal = m:FindFirstChild("Owner")
			if ownerVal and ownerVal.Value == player.Name then
				local item = {
					ModelName = m:GetAttribute("ModelName") or m.Name,
					Rarity = m:GetAttribute("Rarity") or "Common",
					IncomePerSec = m:GetAttribute("IncomePerSec") or 0,
				}
				-- detach & remove
				pcall(function() detachModelFromCharacter(m) end)
				pcall(function() m:Destroy() end)
				-- ensure player gets a Tool rep so nothing lost
				pcall(function() giveToolToBackpack(player, item) end)
				dprint("Cleared previous held model for", player.Name)
				return
			end
		end
	end
end

-- remove one tool from backpack
local function removeOneToolFromBackpackByName(player, toolName)
	local back = player:FindFirstChild("Backpack")
	if not back then return false end
	for _, t in ipairs(back:GetChildren()) do
		if t:IsA("Tool") then
			local mn = nil
			pcall(function() mn = (t.GetAttribute and (t:GetAttribute("ModelName") or t.Name)) or t.Name end)
			if mn == toolName or t.Name == toolName then
				pcall(function() t:Destroy() end)
				return true
			end
		end
	end
	return false
end

-- PICKUP
pickupRemote.OnServerEvent:Connect(function(player, targetOrName, modelNameArg)
	local ok, err = pcall(function()
		local modelInstance = nil
		if typeof(targetOrName) == "Instance" then
			local inst = targetOrName
			if inst:IsA("ProximityPrompt") then
				if inst.Parent and inst.Parent:IsA("BasePart") and inst.Parent.Parent then modelInstance = inst.Parent.Parent else modelInstance = inst.Parent end
			elseif inst:IsA("Model") then modelInstance = inst
			elseif inst:IsA("BasePart") then modelInstance = inst.Parent
			else modelInstance = inst:FindFirstAncestorOfClass("Model") end
		elseif type(targetOrName) == "string" and type(modelNameArg) == "string" then
			for _, m in ipairs(brainrotsFolder:GetChildren()) do
				if m:IsA("Model") and m.Name == modelNameArg then
					local ownerVal = m:FindFirstChild("Owner")
					if ownerVal and ownerVal.Value == player.Name then modelInstance = m; break end
				end
			end
		end

		if not modelInstance or not modelInstance:IsA("Model") then pickupRemote:FireClient(player, false, "Ungültiges Ziel."); return end
		local ownerVal = modelInstance:FindFirstChild("Owner")
		if not ownerVal or tostring(ownerVal.Value) ~= player.Name then pickupRemote:FireClient(player, false, "Nicht dein Modell."); return end

		local item = {
			ModelName = modelInstance:GetAttribute("ModelName") or modelInstance.Name,
			Rarity = modelInstance:GetAttribute("Rarity") or "Common",
			MiningPower = modelInstance:GetAttribute("MiningPower") or 0,
			IncomePerSec = modelInstance:GetAttribute("IncomePerSec") or 0,
		}

		local usedInventory = false
		pcall(function()
			if not Inventory then tryRequireInventory() end
			if Inventory and type(Inventory.AddToInventory) == "function" then
				dprint("Pickup: using Inventory:AddToInventory for", player.Name, item.ModelName)
				Inventory:AddToInventory(player, item)
				usedInventory = true
			end
		end)

		-- ensure UI compatibility: create backpack tool representation if needed
		pcall(function() giveToolToBackpack(player, item) end)

		pcall(function() modelInstance:Destroy() end)

		dprint("After pickup, backpack:", dumpBackpackContents(player))
		pickupRemote:FireClient(player, true, "pickedUp")
		dprint(player.Name .. " picked up " .. tostring(item.ModelName) .. " usedInventory=" .. tostring(usedInventory))
	end)
	if not ok then dprint("pickup error:", err); pickupRemote:FireClient(player, false, "Fehler beim Aufheben.") end
end)

-- EQUIP: spawn workspace model, attach to hand server-side
equipReq.OnServerEvent:Connect(function(player, inventoryIndexOrModelName)
	local ok, err = pcall(function()
		local arg = inventoryIndexOrModelName
		dprint("Equip request from", player.Name, "arg=", tostring(arg))

		-- clear previous held model first
		clearExistingHeld(player)

		-- If client passed model name (string)
		if type(arg) == "string" and arg ~= "" then
			local modelName = arg
			-- try remove from Inventory if present
			pcall(function()
				if not Inventory then tryRequireInventory() end
				if Inventory and type(Inventory.GetInventory) == "function" then
					local inv = Inventory:GetInventory(player) or {}
					for i = 1, #inv do
						local itm = inv[i]
						if itm and (itm.ModelName == modelName or itm.Model == modelName) then
							pcall(function() Inventory:RemoveFromInventory(player, i) end)
							break
						end
					end
				end
			end)
			-- remove backpack tool if exists
			pcall(function() removeOneToolFromBackpackByName(player, modelName) end)

			local spawned = spawnModelByName(modelName, player.Name, CFrame.new(0,5,0))
			if spawned then
				spawned.Parent = heldStorage
				ensurePrimary(spawned)
				attachModelToCharacter(spawned, player)
				equipResp:FireClient(player, true, spawned)
				return
			else
				equipResp:FireClient(player, false, "Kann Modell nicht spawnen: " .. tostring(modelName))
				return
			end
		end

		-- fallback: use first suitable tool in backpack
		local back = player:FindFirstChild("Backpack")
		if back then
			for _, t in ipairs(back:GetChildren()) do
				if t:IsA("Tool") then
					local mn = nil
					pcall(function() mn = (t.GetAttribute and (t:GetAttribute("ModelName") or t.Name)) or t.Name end)
					if mn then
						local folder = ReplicatedStorage:FindFirstChild("BrainrotModels")
						if folder and folder:FindFirstChild(mn) then
							pcall(function() t:Destroy() end)
							local spawned = spawnModelByName(mn, player.Name, CFrame.new(0,5,0))
							if spawned then
								spawned.Parent = heldStorage
								ensurePrimary(spawned)
								attachModelToCharacter(spawned, player)
								equipResp:FireClient(player, true, spawned)
								return
							end
						end
					end
				end
			end
		end

		equipResp:FireClient(player, false, "No equipable item found")
		dprint("Equip failed for", player.Name)
	end)
	if not ok then dprint("equip error:", err); equipResp:FireClient(player, false, "Server equip error") end
end)

-- PLACE handler: detach weld, restore parts, anchor & finalize
local function handlePlace(player, slotArg, forcedModelName)
	local function reply(ok, msg) placeRemote:FireClient(player, ok, msg) end

	dprint("handlePlace called by", player.Name, "slotArg=", tostring(slotArg), "forcedModelName=", tostring(forcedModelName))
	dprint("Backpack before place:", dumpBackpackContents(player))

	-- resolve plot & slot
	local plotName = player:GetAttribute("PlotName")
	if not plotName then reply(false, "Plot nicht gefunden."); return end
	local plotsFolder = Workspace:FindFirstChild("Plots")
	if not plotsFolder then reply(false, "Plots fehlen."); return end
	local plot = plotsFolder:FindFirstChild(plotName)
	if not plot then reply(false, "Plot nicht in Workspace."); return end

	local slot = nil
	if typeof(slotArg) == "Instance" then slot = slotArg
	elseif type(slotArg) == "string" then slot = plot:FindFirstChild(slotArg) end
	if not slot then reply(false, "Slot nicht gefunden."); return end

	-- occupancy check
	for _, mod in ipairs(brainrotsFolder:GetChildren()) do
		if mod:IsA("Model") then
			local s = mod:FindFirstChild("StoredInSlot")
			local ownerVal = mod:FindFirstChild("Owner")
			if s and ownerVal and ownerVal.Value == player.Name and s.Value == slot.Name then
				reply(false, "Slot bereits belegt.")
				return
			end
		end
	end

	local spawnPos = (slot.Position and (slot.Position + Vector3.new(0,3,0))) or Vector3.new(0,5,0)
	local placedModel = nil

	if type(forcedModelName) == "string" and forcedModelName ~= "" then
		pcall(function() removeOneToolFromBackpackByName(player, forcedModelName) end)
		local spawned = spawnModelByName(forcedModelName, player.Name, CFrame.new(spawnPos))
		if spawned then placedModel = spawned else reply(false, "Kann Modell nicht spawnen: " .. tostring(forcedModelName)); return end
	else
		-- find held model in heldStorage
		local heldFound = nil
		for _, m in ipairs(heldStorage:GetChildren()) do
			local ownerVal = m:FindFirstChild("Owner")
			if ownerVal and ownerVal.Value == player.Name then heldFound = m; break end
		end

		if heldFound then
			-- detach weld and restore safe physical state then anchor
			detachModelFromCharacter(heldFound)
			placedModel = heldFound
			pcall(function() placedModel.Parent = brainrotsFolder end)
			local prim = ensurePrimary(placedModel)
			if prim then pcall(function() placedModel:SetPrimaryPartCFrame(CFrame.new(spawnPos)) end) end
			anchorModel(placedModel)
		else
			-- fallback: consume a backpack tool
			local back = player:FindFirstChild("Backpack")
			local chosenName = nil
			if back then
				for _, t in ipairs(back:GetChildren()) do
					if t:IsA("Tool") then
						local mn = nil
						pcall(function() mn = (t.GetAttribute and (t:GetAttribute("ModelName") or t.Name)) or t.Name end)
						if mn then
							local folder = ReplicatedStorage:FindFirstChild("BrainrotModels")
							if folder and folder:FindFirstChild(mn) then
								chosenName = mn
								pcall(function() t:Destroy() end)
								break
							end
						end
					end
				end
			end
			if chosenName then
				placedModel = spawnModelByName(chosenName, player.Name, CFrame.new(spawnPos))
				if placedModel then anchorModel(placedModel) end
			else
				reply(false, "Kein passendes Item im Rucksack.")
				return
			end
		end
	end

	if placedModel then
		local s = placedModel:FindFirstChild("StoredInSlot") or Instance.new("StringValue")
		s.Name = "StoredInSlot"; s.Value = slot.Name; s.Parent = placedModel
		pcall(function() placedModel:SetAttribute("Yaw", placedModel:GetAttribute("Yaw") or 0) end)
		if type(_G.startIncomeForPlaced) == "function" then pcall(function() _G.startIncomeForPlaced(placedModel) end) end
		reply(true, tostring(placedModel.Name))
		dprint("Placed", tostring(placedModel.Name), "at", slot.Name, "for", player.Name)
		dprint("Backpack after place:", dumpBackpackContents(player))
		return
	end

	reply(false, "Platzierung fehlgeschlagen.")
end

placeRemote.OnServerEvent:Connect(function(player, slotArg, forcedModelName)
	local ok, err = pcall(function() handlePlace(player, slotArg, forcedModelName) end)
	if not ok then dprint("handlePlace error:", err); placeRemote:FireClient(player, false, "Serverfehler beim Platzieren.") end
end)

Players.PlayerRemoving:Connect(function(player)
	-- cleanup held models of leaving player
	for _, m in ipairs(heldStorage:GetChildren()) do
		local ownerVal = m:FindFirstChild("Owner")
		if ownerVal and ownerVal.Value == player.Name then pcall(function() m:Destroy() end) end
	end
end)

dprint("BrainrotPickupServer loaded (weld-to-hand behavior enabled, massless safeguards)")
