-- BrainrotPickupServer.lua (ServerScriptService)
-- Debug-heavy version to trace slot resolution and placement for Model-based slots and equipped tools.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Set DEBUG true for verbose logging
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

-- Helpers --------------------------------------------------------------------

local function dprint(...)
    if DEBUG then
        print(...)
    end
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
                    pl.leaderstats.Gold.Value += incomePerSec
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

-- resolveSlot: accepts BasePart or Model; returns (slotPart, slotContainerModel)
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

local function giveToolToBackpack(player, item)
    local backpack = player:FindFirstChild("Backpack")
    if not backpack then return end
    local existing = backpack:FindFirstChild(item.ModelName)
    if existing and existing:IsA("Tool") then
        local amt = tonumber(existing:GetAttribute("amount")) or 1
        existing:SetAttribute("amount", amt + 1)
        return
    end
    local tool = Instance.new("Tool")
    tool.Name = item.ModelName
    tool.RequiresHandle = false
    tool.CanBeDropped = false
    tool:SetAttribute("amount", 1)
    tool:SetAttribute("rarity", item.Rarity or "Common")
    tool:SetAttribute("miningPower", item.MiningPower or 0)
    tool:SetAttribute("incomePerSec", item.IncomePerSec or 0)
    tool.ToolTip = string.format("%s | Power %s | Income %s/s", item.Rarity or "Common", tostring(item.MiningPower or 0), tostring(item.IncomePerSec or 0))
    tool.Parent = backpack
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

-- Pickup/Buy -----------------------------------------------------------------
pickupRemote.OnServerEvent:Connect(function(player, targetOrName, nameFromClient)
    local uid = player.UserId
    if heldByPlayer[uid] then
        pickupRemote:FireClient(player, false, "Du hältst bereits ein Brainrot.")
        return
    end

    -- Pickup placed
    if typeof(targetOrName) == "Instance" then
        local modelCandidate = targetOrName
        if modelCandidate:IsA("ProximityPrompt") then
            modelCandidate = select(1, resolveModelAndName(modelCandidate))
        end
        if modelCandidate and modelCandidate:IsDescendantOf(brainrotsFolder) and modelCandidate:FindFirstChild("StoredInSlot") then
            local owner = modelCandidate:FindFirstChild("Owner")
            if not owner or owner.Value ~= player.Name then
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
            local meta = storeOriginalTransparencies(modelCandidate)
            local okPark = pcall(function()
                for _, part in ipairs(modelCandidate:GetDescendants()) do
                    if part:IsA("BasePart") then
                        part.CanCollide = false
                        part.Anchored = true
                        part.Transparency = 1
                    end
                end
                modelCandidate.Parent = heldStorage
            end)
            if not okPark then
                pickupRemote:FireClient(player, false, "Aufnahme fehlgeschlagen.")
                return
            end
            heldByPlayer[uid] = { model = modelCandidate, meta = meta }
            pickupRemote:FireClient(player, true, "pickedUp")
            dprint(player.Name .. " picked up placed " .. modelCandidate.Name)
            return
        end
    end

    -- Purchase
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

-- Place ----------------------------------------------------------------------
placeRemote.OnServerEvent:Connect(function(player, slotInstanceOrName)
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

        model.Parent = brainrotsFolder

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

    -- Fall B: ausgerüstetes Tool klonen
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
        placeRemote:FireClient(player, false, "Du hast nichts ausgerüstet.")
        dprint("PLACE fail: no equipped tool")
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

    newModel.Parent = brainrotsFolder

    local stored = newModel:FindFirstChild("StoredInSlot") or Instance.new("StringValue")
    stored.Name = "StoredInSlot"
    stored.Value = slotContainer.Name
    stored.Parent = newModel

    local ownerTag = newModel:FindFirstChild("Owner") or Instance.new("StringValue")
    ownerTag.Name = "Owner"
    ownerTag.Value = player.Name
    ownerTag.Parent = newModel

    if slotPart.SetAttribute then slotPart:SetAttribute("Occupied", true) end
    if slotContainer and slotContainer ~= slotPart and slotContainer.SetAttribute then
        slotContainer:SetAttribute("Occupied", true)
    end

    removeOneTool(player, equippedName)
    pcall(function() startIncomeForPlaced(newModel) end)

    placeRemote:FireClient(player, true, tostring(newModel.Name))
    dprint("PLACE equipped OK", newModel.Name, "at", slotContainer.Name)
end)

-- Equip (unverändert)
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