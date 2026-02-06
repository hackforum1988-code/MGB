-- BrainrotPickupServer.lua (ServerScriptService)
-- Platzieren: zuerst Tool im Character, sonst im Backpack; ankert platzierte Parts.
-- Platziert: ProximityPrompts auf "Aufheben" (kein Kaufen/0 Gold).
-- Label-Anzeige via attachLabelToModel (nach Platzieren).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DEBUG = true

local Inventory = require(game.ServerScriptService:WaitForChild("InventoryServer"))
local Catalog = require(game.ServerScriptService:WaitForChild("AssetCatalog"))

local function ensureRemote(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = ReplicatedStorage
	end
	return r
end

local pickupRemote = ensureRemote("BrainrotPickup")
local placeRemote  = ensureRemote("BrainrotPlace")
local equipReq     = ensureRemote("EquipRequest")
local equipResp    = ensureRemote("EquipResponse")

local brainrotsFolder = workspace:FindFirstChild("Brainrots")
if not brainrotsFolder then
	error("Brainrots folder missing in workspace")
end

local heldStorage = workspace:FindFirstChild("HeldBrainrots")
if not heldStorage then
	heldStorage = Instance.new("Folder")
	heldStorage.Name = "HeldBrainrots"
	heldStorage.Parent = workspace
end

local modelsFolder = ReplicatedStorage:FindFirstChild("BrainrotModels")
local workspaceModelsFolder = workspace:FindFirstChild("Brainrots") and workspace.Brainrots:FindFirstChild("Brainrot pack1")

local heldByPlayer = {}
local activeIncome = {}
local placeCooldown = {}
local PLACE_COOLDOWN_SEC = 0.5

local rarityColors = {
	Common    = Color3.fromRGB(200,200,200),
	Uncommon  = Color3.fromRGB(100,220,120),
	Rare      = Color3.fromRGB(100,160,255),
	Legendary = Color3.fromRGB(255,180,60),
	Mythic    = Color3.fromRGB(230,80,230),
}

local function dprint(...) if DEBUG then print(...) end end

local function safeSetAttribute(obj, name, value)
	if obj and obj.SetAttribute then
		local ok = pcall(function() obj:SetAttribute(name, value) end)
		if ok then return end
	end
	local existing = obj and obj:FindFirstChild(name)
	if existing and existing:IsA("ValueBase") then
		existing.Value = value
		return
	end
	local v
	if typeof(value) == "number" then
		v = Instance.new("NumberValue")
	elseif typeof(value) == "boolean" then
		v = Instance.new("BoolValue")
	else
		v = Instance.new("StringValue")
	end
	v.Name = name
	v.Value = value
	v.Parent = obj
end

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

local function attachLabelToModel(model)
	if not model then return end
	local primary = ensurePrimary(model)
	if not primary then return end

	local old = primary:FindFirstChild("BrainrotLabel")
	if old then old:Destroy() end

	local size = model:GetExtentsSize()
	local heightBoost = math.clamp(size.Y * 0.6, 3, 12)

	local bb = Instance.new("BillboardGui")
	bb.Name = "BrainrotLabel"
	bb.Adornee = primary
	bb.AlwaysOnTop = true
	bb.Size = UDim2.new(0, 200, 0, 90)
	bb.StudsOffset = Vector3.new(0, heightBoost, 0)
	bb.MaxDistance = 400
	bb.LightInfluence = 0
	bb.Parent = primary

	local rarityVal = model:FindFirstChild("Rarity")
	local priceVal = model:FindFirstChild("Price")
	local incomeVal = model:FindFirstChild("IncomePerSec")
	local rarity = rarityVal and rarityVal.Value or "Common"
	local price = priceVal and priceVal.Value or 0
	local income = incomeVal and incomeVal.Value or 0
	local displayName = model.Name

	local function makeLine(text, order, color)
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 0, 18)
		lbl.Position = UDim2.new(0, 0, 0, order * 18)
		lbl.BackgroundTransparency = 1
		lbl.Text = text
		lbl.Font = Enum.Font.GothamBold
		lbl.TextSize = 14
		lbl.TextColor3 = color or Color3.fromRGB(255,255,255)
		lbl.TextXAlignment = Enum.TextXAlignment.Center
		lbl.Parent = bb

		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Color = Color3.fromRGB(0,0,0)
		stroke.Parent = lbl
	end

	makeLine(tostring(rarity), 0, rarityColors[rarity] or Color3.fromRGB(255,255,255))
	makeLine(tostring(displayName), 1)
	makeLine("Preis: " .. tostring(price), 2)
	makeLine("Income: " .. tostring(income) .. "/s", 3)
end

local function ensurePickupPrompt(model)
	if not model then return end
	local primary = ensurePrimary(model)
	if not primary then return end
	local prompt = nil
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			prompt = d
			break
		end
	end
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Parent = primary
	end
	prompt.Enabled = true
	prompt.ActionText = "Aufheben"
	prompt.ObjectText = model.Name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	safeSetAttribute(prompt, "Price", nil)
	safeSetAttribute(prompt, "ModelName", model:GetAttribute("ModelName") or model.Name)
	return prompt
end

local function findTemplate(modelName)
	if modelsFolder then
		local t = modelsFolder:FindFirstChild(modelName)
		if t then return t end
	end
	if workspaceModelsFolder then
		local t = workspaceModelsFolder:FindFirstChild(modelName)
		if t then return t end
	end
	return nil
end

local function spawnFromCatalog(modelName, ownerName)
	local def = Catalog[modelName]
	if not def then dprint("spawnFromCatalog: no def for", modelName) return nil end
	local template = findTemplate(def.TemplateName or modelName)
	if not template then
		warn("spawnFromCatalog: Template fehlt für", modelName)
		return nil
	end
	local clone = template:Clone()
	clone.Name = def.TemplateName or modelName

	if not clone.PrimaryPart then
		for _, c in ipairs(clone:GetDescendants()) do
			if c:IsA("BasePart") then
				clone.PrimaryPart = c
				break
			end
		end
	end
	if not clone.PrimaryPart then
		local p = Instance.new("Part")
		p.Name = "Primary"
		p.Size = Vector3.new(1,1,1)
		p.Transparency = 1
		p.CanCollide = false
		p.Anchored = true
		p.Parent = clone
		clone.PrimaryPart = p
	end

	local mining = def.MiningPower or 1
	local price  = def.Price or (mining * 5)
	local income = def.IncomePerSec or math.max(1, math.floor(mining * 0.5))
	local rarity = def.Rarity or "Common"

	local ownerVal  = Instance.new("StringValue"); ownerVal.Name  = "Owner";        ownerVal.Value  = ownerName; ownerVal.Parent  = clone
	local powerVal  = Instance.new("IntValue");   powerVal.Name  = "MiningPower";  powerVal.Value  = mining;    powerVal.Parent  = clone
	local rarityVal = Instance.new("StringValue");rarityVal.Name = "Rarity";       rarityVal.Value = rarity;    rarityVal.Parent = clone
	local priceVal  = Instance.new("IntValue");   priceVal.Name  = "Price";        priceVal.Value  = price;     priceVal.Parent  = clone
	local incomeVal = Instance.new("IntValue");   incomeVal.Name = "IncomePerSec"; incomeVal.Value = income;    incomeVal.Parent = clone

	return clone
end

local function storeOriginalTransparencies(model)
	local meta = { partOrigTransparency = {}, anchoredStates = {}, originalParent = model.Parent }
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			meta.partOrigTransparency[p] = p.Transparency or 0
			meta.anchoredStates[p] = p.Anchored
		end
	end
	return meta
end

local function restoreTransparenciesAndAnchors(meta)
	if not meta then return false end
	local ok = true
	for part, orig in pairs(meta.partOrigTransparency or {}) do
		if part and part.Parent then
			local s, e = pcall(function() part.Transparency = orig or 0 end)
			if not s then ok = false warn(e) end
		end
	end
	for part, anchored in pairs(meta.anchoredStates or {}) do
		if part and part.Parent then
			local s, e = pcall(function() part.Anchored = anchored end)
			if not s then ok = false warn(e) end
		end
	end
	return ok
end

-- Cash-Booster-aware income loop
local function startIncomeForPlaced(model)
	if not model or not model.Parent then return end
	if activeIncome[model] then return end
	local incomeValObj = model:FindFirstChild("IncomePerSec")
	local ownerVal = model:FindFirstChild("Owner")
	if not incomeValObj or not ownerVal then return end
	local incomePerSec = tonumber(incomeValObj.Value) or 0
	local ownerName = tostring(ownerVal.Value or "")
	local conn = {}
	activeIncome[model] = conn
	conn.runner = task.spawn(function()
		while model and model.Parent and activeIncome[model] == conn do
			if incomePerSec > 0 and ownerName ~= "" then
				local pl = Players:FindFirstChild(ownerName)
				if pl and pl:FindFirstChild("leaderstats") and pl.leaderstats:FindFirstChild("Gold") then
					local boost = pl:GetAttribute("IncomeBoost") or 0 -- z.B. 0.10 für +10 %
					local mult = 1 + boost
					pl.leaderstats.Gold.Value += incomePerSec * mult
				end
			end
			task.wait(1)
		end
	end)
end
local function stopIncomeForPlaced(model)
	if activeIncome[model] then
		activeIncome[model] = nil
	end
end
_G.startIncomeForPlaced = startIncomeForPlaced

local function setPromptsToPickup(model)
	local prompt = ensurePickupPrompt(model)
	if prompt then
		prompt.ActionText = "Aufheben"
		prompt.ObjectText = model.Name
		safeSetAttribute(prompt, "Price", nil)
		safeSetAttribute(prompt, "ModelName", model:GetAttribute("ModelName") or model.Name)
	end
	attachLabelToModel(model)
end

local function resolveSlot(plot, slotInstanceOrName)
	if typeof(slotInstanceOrName) == "Instance" then
		if slotInstanceOrName:IsA("BasePart") then
			return slotInstanceOrName, slotInstanceOrName
		else
			for _, d in ipairs(slotInstanceOrName:GetDescendants()) do
				if d:IsA("BasePart") then
					return d, slotInstanceOrName
				end
			end
		end
	elseif type(slotInstanceOrName) == "string" then
		local slotInst = plot and plot:FindFirstChild(slotInstanceOrName)
		if slotInst then
			if slotInst:IsA("BasePart") then
				return slotInst, slotInst
			else
				for _, d in ipairs(slotInst:GetDescendants()) do
					if d:IsA("BasePart") then
						return d, slotInst
					end
				end
			end
		end
	end
	return nil, nil
end

-- Immer neues Tool, kein Stacken
local function giveToolToBackpack(player, item)
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return end

	local tool = Instance.new("Tool")
	tool.Name = item.ModelName
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	safeSetAttribute(tool, "amount", 1)
	safeSetAttribute(tool, "rarity", item.Rarity or "Common")
	safeSetAttribute(tool, "miningPower", item.MiningPower or 0)
	safeSetAttribute(tool, "incomePerSec", item.IncomePerSec or 0)
	tool.ToolTip = string.format("%s | Power %s | Income %s/s",
		item.Rarity or "Common",
		tostring(item.MiningPower or 0),
		tostring(item.IncomePerSec or 0)
	)
	tool.Parent = backpack
end

-- Entfernt genau ein Tool (kein amount-Stacking)
local function removeOneTool(player, modelName)
	local function try(container)
		if not container then return false end
		for _, t in ipairs(container:GetChildren()) do
			if t:IsA("Tool") and t.Name == modelName then
				t:Destroy()
				return true
			end
		end
		return false
	end
	if try(player.Character) then return true end
	return try(player:FindFirstChild("Backpack"))
end

local function resolveModelAndName(argInstance, fallbackName)
	local model = nil
	if argInstance then
		if argInstance:IsA("ProximityPrompt") then
			local parent = argInstance.Parent
			if parent and parent:IsA("BasePart") then
				model = parent.Parent
			else
				model = parent
			end
		elseif argInstance:IsA("BasePart") then
			model = argInstance.Parent
		else
			model = argInstance
		end
	end
	local modelName = nil
	if argInstance and argInstance:IsA("ProximityPrompt") then
		modelName = argInstance:GetAttribute("ModelName")
	end
	if not modelName and model and model:IsA("Instance") then
		modelName = model:GetAttribute("ModelName") or model.Name
	end
	if not modelName then
		modelName = fallbackName
	end
	return model, modelName
end

local function dumpSlots(plot)
	if not plot then
		dprint("PLOT nil")
		return
	end
	dprint("PLOT slots listing for", plot.Name)
	for _, child in ipairs(plot:GetChildren()) do
		if type(child.Name) == "string" and child.Name:match("^Slot") then
			local part = nil
			if child:IsA("BasePart") then
				part = child
			else
				for _, d in ipairs(child:GetDescendants()) do
					if d:IsA("BasePart") then
						part = d
						break
					end
				end
			end
			dprint(
				"  Slot", child.Name,
				"part", part and part:GetFullName() or "nil",
				"occ(model)", child:GetAttribute("Occupied"),
				"occ(part)", part and part:GetAttribute("Occupied")
			)
		end
	end
end

pickupRemote.OnServerEvent:Connect(function(player, targetOrName, nameFromClient)
	dprint("PICKUP call", player.Name, targetOrName, nameFromClient)
	local uid = player.UserId
	if heldByPlayer[uid] then
		pickupRemote:FireClient(player, false, "Du hältst bereits ein Brainrot.")
		return
	end

	-- Pickup placed: immer ins Inventar (StoredInSlot erforderlich)
	if typeof(targetOrName) == "Instance" then
		local modelCandidate = targetOrName
		if modelCandidate:IsA("ProximityPrompt") then
			modelCandidate = select(1, resolveModelAndName(modelCandidate))
		end
		if modelCandidate and modelCandidate:IsDescendantOf(brainrotsFolder) and modelCandidate:FindFirstChild("StoredInSlot") then
			local owner = modelCandidate:FindFirstChild("Owner")
			if not owner then
				owner = Instance.new("StringValue")
				owner.Name = "Owner"
				owner.Parent = modelCandidate
				owner.Value = player.Name
			elseif owner.Value ~= player.Name then
				pickupRemote:FireClient(player, false, "Nicht dein Brainrot.")
				return
			end

			local stored = modelCandidate:FindFirstChild("StoredInSlot")
			if stored and stored.Value and stored.Value ~= "" then
				local plotsFolder = workspace:FindFirstChild("Plots")
				if plotsFolder then
					for _, plot in ipairs(plotsFolder:GetChildren()) do
						local slotObj = plot:FindFirstChild(stored.Value)
						if slotObj and slotObj.SetAttribute then
							slotObj:SetAttribute("Occupied", nil)
							break
						end
					end
				end
				pcall(function() stored:Destroy() end)
			end

			stopIncomeForPlaced(modelCandidate)

			local modelName = modelCandidate:GetAttribute("ModelName") or modelCandidate.Name
			local def = Catalog[modelName] or {}
			local item = {
				ModelName    = modelName,
				Rarity       = def.Rarity or (modelCandidate:FindFirstChild("Rarity") and modelCandidate.Rarity.Value) or "Common",
				MiningPower  = def.MiningPower or (modelCandidate:FindFirstChild("MiningPower") and modelCandidate.MiningPower.Value) or 0,
				IncomePerSec = def.IncomePerSec or (modelCandidate:FindFirstChild("IncomePerSec") and modelCandidate.IncomePerSec.Value) or 0,
			}

			local addedOk = pcall(function()
				Inventory:AddToInventory(player, item)
			end)
			if not addedOk then
				pickupRemote:FireClient(player, false, "Fehler beim Hinzufügen zum Inventar.")
				return
			end
			giveToolToBackpack(player, item)
			pcall(function() modelCandidate:Destroy() end)

			pickupRemote:FireClient(player, true, "addedToInventory")
			dprint(player.Name .. " picked up placed " .. modelName .. " -> inventory")
			return
		end
	end

	-- Purchase (nur ohne StoredInSlot)
	local modelFromInstance, modelNameFromInstance = nil, nil
	if typeof(targetOrName) == "Instance" then
		modelFromInstance, modelNameFromInstance = resolveModelAndName(targetOrName, nameFromClient)
	end
	local modelName = modelNameFromInstance or nameFromClient or tostring(targetOrName or "")
	if not modelName or modelName == "" then
		pickupRemote:FireClient(player, false, "Ungültiges Ziel.")
		return
	end

	local def = Catalog[modelName] or {}
	local leaderstats = player:FindFirstChild("leaderstats")
	local gold = leaderstats and leaderstats:FindFirstChild("Gold")

	local cost = 0
	if def and def.Price then
		cost = def.Price
	elseif def and def.MiningPower then
		local mp = tonumber(def.MiningPower) or def.MiningPower or 0
		cost = tonumber(mp) * 5
	else
		cost = 0
	end

	if cost <= 0 then
		pickupRemote:FireClient(player, false, "Nicht kaufbar.")
		return
	end

	if not gold then
		pickupRemote:FireClient(player, false, "Fehlende Daten.")
		return
	end
	if gold.Value < cost then
		pickupRemote:FireClient(player, false, "Brauchst " .. tostring(cost) .. " Gold!")
		return
	end

	gold.Value = gold.Value - cost

	local item = {
		ModelName    = modelName,
		Rarity       = def.Rarity or "Common",
		MiningPower  = def.MiningPower or 0,
		IncomePerSec = def.IncomePerSec or 0,
	}

	local addedOk, err = pcall(function()
		Inventory:AddToInventory(player, item)
	end)
	if not addedOk then
		pickupRemote:FireClient(player, false, "Fehler beim Hinzufügen zum Inventar.")
		return
	end

	giveToolToBackpack(player, item)

	if modelFromInstance and modelFromInstance.Parent then
		pcall(function() modelFromInstance:Destroy() end)
	end

	pickupRemote:FireClient(player, true, "addedToInventory")
	dprint("BUY:", player.Name, "model", modelName, "cost", cost)
end)

local function handlePlace(player, slotInstanceOrName)
	dprint("PLACE call from", player.Name, "raw arg:", slotInstanceOrName)

	local uid = player.UserId
	local lastPlace = placeCooldown[uid] or 0
	if tick() - lastPlace < PLACE_COOLDOWN_SEC then
		placeRemote:FireClient(player, false, "Bitte kurz warten.")
		return
	end
	placeCooldown[uid] = tick()

	local plotName = player:GetAttribute("PlotName")
	if not plotName then
		placeRemote:FireClient(player, false, "Kein Plot gefunden.")
		return
	end
	local plotsFolder = workspace:FindFirstChild("Plots")
	if not plotsFolder then
		placeRemote:FireClient(player, false, "Plots nicht verfügbar.")
		return
	end
	local plot = plotsFolder:FindFirstChild(plotName)
	if not plot then
		placeRemote:FireClient(player, false, "Plot nicht gefunden.")
		return
	end

	dumpSlots(plot)

	local slotPart, slotContainer = resolveSlot(plot, slotInstanceOrName)
	if not slotPart then
		placeRemote:FireClient(player, false, "Slot nicht gefunden.")
		dprint("PLACE fail: no slotPart", slotInstanceOrName)
		return
	end

	local occupied = false
	if slotPart.GetAttribute and slotPart:GetAttribute("Occupied") then occupied = true end
	if slotContainer and slotContainer ~= slotPart and slotContainer.GetAttribute and slotContainer:GetAttribute("Occupied") then occupied = true end
	if occupied then
		placeRemote:FireClient(player, false, "Slot bereits belegt.")
		dprint("PLACE fail: occupied", slotPart, slotContainer)
		return
	end

	-- Fall A: held-Model vorhanden
	local held = heldByPlayer[uid]
	if held and held.model then
		local model = held.model
		local meta = held.meta
		pcall(function() restoreTransparenciesAndAnchors(meta) end)

		if slotPart:IsA("BasePart") and model.PrimaryPart then
			model:SetPrimaryPartCFrame(slotPart.CFrame * CFrame.new(0, 3, 0))
		elseif slotPart:IsA("BasePart") then
			for _, p in ipairs(model:GetDescendants()) do
				if p:IsA("BasePart") then
					p.CFrame = slotPart.CFrame * CFrame.new(0, 3, 0)
					break
				end
			end
		end

		for _, part in ipairs(model:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Anchored = true
			end
		end

		model.Parent = brainrotsFolder
		setPromptsToPickup(model)
		attachLabelToModel(model)

		local stored = model:FindFirstChild("StoredInSlot") or Instance.new("StringValue")
		stored.Name = "StoredInSlot"
		stored.Value = slotContainer.Name
		stored.Parent = model

		local ownerTag = model:FindFirstChild("Owner") or Instance.new("StringValue")
		ownerTag.Name = "Owner"
		ownerTag.Value = player.Name
		ownerTag.Parent = model

		if slotPart.SetAttribute then slotPart:SetAttribute("Occupied", true) end
		if slotContainer and slotContainer ~= slotPart and slotContainer.SetAttribute then
			slotContainer:SetAttribute("Occupied", true)
		end

		heldByPlayer[uid] = nil
		pcall(function() startIncomeForPlaced(model) end)

		placeRemote:FireClient(player, true, tostring(model.Name))
		dprint("PLACE held OK", model.Name, "at", slotContainer.Name)
		return
	end

	-- Fall B: ausgerüstetes Tool klonen ODER eines aus dem Backpack nehmen
	local char = player.Character
	local equippedName = nil
	if char then
		for _, t in ipairs(char:GetChildren()) do
			if t:IsA("Tool") then
				equippedName = t.Name
				break
			end
		end
	end
	if not equippedName then
		local backpack = player:FindFirstChild("Backpack")
		if backpack then
			for _, t in ipairs(backpack:GetChildren()) do
				if t:IsA("Tool") then
					equippedName = t.Name
					break
				end
			end
		end
	end
	if not equippedName then
		placeRemote:FireClient(player, false, "Du hast nichts ausgerüstet.")
		dprint("PLACE fail: no equipped tool (none in char/backpack)")
		return
	end

	local newModel = spawnFromCatalog(equippedName, player.Name)
	if not newModel then
		placeRemote:FireClient(player, false, "Konnte Modell nicht erzeugen.")
		dprint("PLACE fail: no template", equippedName)
		return
	end

	if slotPart:IsA("BasePart") and newModel.PrimaryPart then
		newModel:SetPrimaryPartCFrame(slotPart.CFrame * CFrame.new(0, 3, 0))
	elseif slotPart:IsA("BasePart") then
		for _, p in ipairs(newModel:GetDescendants()) do
			if p:IsA("BasePart") then
				p.CFrame = slotPart.CFrame * CFrame.new(0, 3, 0)
				break
			end
		end
	end

	for _, part in ipairs(newModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end

	newModel.Parent = brainrotsFolder
	setPromptsToPickup(newModel)
	attachLabelToModel(newModel)

	local stored2 = newModel:FindFirstChild("StoredInSlot")
	if not stored2 then
		stored2 = Instance.new("StringValue")
		stored2.Name = "StoredInSlot"
		stored2.Parent = newModel
	end
	stored2.Value = slotContainer.Name

	local ownerTag2 = newModel:FindFirstChild("Owner")
	if not ownerTag2 then
		ownerTag2 = Instance.new("StringValue")
		ownerTag2.Name = "Owner"
		ownerTag2.Parent = newModel
	end
	ownerTag2.Value = player.Name

	if slotPart.SetAttribute then slotPart:SetAttribute("Occupied", true) end
	if slotContainer and slotContainer ~= slotPart and slotContainer.SetAttribute then
		slotContainer:SetAttribute("Occupied", true)
	end

	removeOneTool(player, equippedName)
	pcall(function() startIncomeForPlaced(newModel) end)

	placeRemote:FireClient(player, true, tostring(newModel.Name))
	dprint("PLACE equipped OK", newModel.Name, "at", slotContainer.Name)
end  -- Ende handlePlace

placeRemote.OnServerEvent:Connect(function(player, slotInstanceOrName)
	handlePlace(player, slotInstanceOrName)
end)

local function connectSlotClickDetector(cd)
	if cd:GetAttribute("SlotClickHooked") then return end
	cd:SetAttribute("SlotClickHooked", true)
	cd.MouseClick:Connect(function(player)
		handlePlace(player, cd.Parent)
	end)
end

local function scanSlotsForClickDetectors()
	local plotsFolder = workspace:FindFirstChild("Plots")
	if not plotsFolder then return end
	for _, plot in ipairs(plotsFolder:GetChildren()) do
		for _, child in ipairs(plot:GetDescendants()) do
			if child:IsA("ClickDetector") then
				local parentSlot = child.Parent
				if parentSlot and type(parentSlot.Name) == "string" and parentSlot.Name:match("^Slot") then
					connectSlotClickDetector(child)
				end
			end
		end
	end
end

scanSlotsForClickDetectors()
workspace.DescendantAdded:Connect(function(desc)
	if desc:IsA("ClickDetector") then
		local parentSlot = desc.Parent
		if parentSlot and type(parentSlot.Name) == "string" and parentSlot.Name:match("^Slot") then
			connectSlotClickDetector(desc)
		end
	end
end)

EquipReq_OnServerEvent = equipReq.OnServerEvent:Connect(function(player, inventoryIndex)
	local ok, result = pcall(function()
		return Inventory:EquipFromInventory(player, inventoryIndex, heldStorage)
	end)
	if ok and result and typeof(result) == "Instance" then
		heldByPlayer[player.UserId] = { model = result, meta = storeOriginalTransparencies(result) }
		equipResp:FireClient(player, true, "equipped")
		dprint("Equip success for", player.Name)
	else
		local err = tostring(result)
		equipResp:FireClient(player, false, err or "Equip failed")
		dprint("Equip failed for", player.Name, err)
	end
end)

local function anchorPlacedModel(model)
	if not model or not model:IsA("Model") then return end
	if not model:FindFirstChild("StoredInSlot") then return end
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = true
			part.AssemblyLinearVelocity = Vector3.new(0,0,0)
			part.AssemblyAngularVelocity = Vector3.new(0,0,0)
		end
	end
	if model.PrimaryPart then
		model.PrimaryPart.Anchored = true
		model.PrimaryPart.CanCollide = true
		model.PrimaryPart.AssemblyLinearVelocity = Vector3.new(0,0,0)
		model.PrimaryPart.AssemblyAngularVelocity = Vector3.new(0,0,0)
	end
	setPromptsToPickup(model)
	attachLabelToModel(model)
end

for _, child in ipairs(brainrotsFolder:GetDescendants()) do
	if child:IsA("Model") then
		anchorPlacedModel(child)
	end
end
brainrotsFolder.DescendantAdded:Connect(function(child)
	if child:IsA("Model") then
		anchorPlacedModel(child)
	end
end)
