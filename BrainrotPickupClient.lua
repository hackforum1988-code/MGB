-- BrainrotPickupClient.lua (Client) - equip model follows player's hand; RequestPlace auto-finds slot if not provided
-- Replace the running client script with this complete file.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local DEBUG = true
local function dbg(...) if DEBUG and RunService:IsStudio() then print("[BPC]", ...) end end

local pickupRemote = ReplicatedStorage:WaitForChild("BrainrotPickup")
local placeRemote  = ReplicatedStorage:WaitForChild("BrainrotPlace")
local equipReq     = ReplicatedStorage:WaitForChild("EquipRequest")
local equipResp    = ReplicatedStorage:WaitForChild("EquipResponse")

local localHeldModel = nil -- Instance in workspace.HeldBrainrots
local isPlacing = false
local followConn = nil

local function showToast(text) print("[TOAST]", text) end
local function showPlacingSpinner(show) if show then dbg("Placing spinner ON") else dbg("Placing spinner OFF") end end

local function stopFollowingHeld()
	if followConn then
		pcall(function() followConn:Disconnect() end)
		followConn = nil
	end
	if localHeldModel then
		-- restore anchoring if needed; keep unanchored for placement
		pcall(function()
			if localHeldModel.PrimaryPart then
				localHeldModel.PrimaryPart.CanCollide = true
			end
		end)
	end
end

local function startFollowingHeld(modelInstance)
	-- ensure primary part
	if not modelInstance then return end
	pcall(function()
		if modelInstance.PrimaryPart then
			modelInstance.PrimaryPart.CanCollide = false
		end
	end)

	-- detach previous
	stopFollowingHeld()
	localHeldModel = modelInstance

	-- RenderStepped follow (local only)
	followConn = RunService.RenderStepped:Connect(function()
		if not localHeldModel then return end
		local prim = localHeldModel.PrimaryPart
		if not prim then return end
		if not player.Character then return end

		-- find hand (try RightHand, then Right Arm, then HumanoidRootPart)
		local hand = player.Character:FindFirstChild("RightHand") or player.Character:FindFirstChild("Right Arm") or player.Character:FindFirstChild("HumanoidRootPart")
		if hand and hand:IsA("BasePart") then
			-- position the model near the hand; adjust offset as needed
			local targetCFrame = hand.CFrame * CFrame.new(0, -0.5, 0) * CFrame.Angles(0, math.rad(180), 0)
			pcall(function() prim.CFrame = targetCFrame end)
		end
	end)

	dbg("startFollowingHeld: following model:", modelInstance.Name)
end

local function clearLocalHeldVisuals()
	stopFollowingHeld()
	localHeldModel = nil
end

local function restoreLocalHeldVisuals()
	-- If needed, we can respawn visual or search HeldBrainrots — for now do nothing
end

-- helper: find first free slot in player's plot (client-side best-effort)
local function findFirstFreeSlotName()
	local plotName = nil
	pcall(function() plotName = player:GetAttribute("PlotName") end)
	if not plotName then return nil end
	local plotsFolder = Workspace:FindFirstChild("Plots")
	if not plotsFolder then return nil end
	local plot = plotsFolder:FindFirstChild(plotName)
	if not plot then return nil end

	-- collect used slots for this player (search workspace.Brainrots)
	local used = {}
	local brFolder = Workspace:FindFirstChild("Brainrots")
	if brFolder then
		for _, m in ipairs(brFolder:GetChildren()) do
			if m:IsA("Model") then
				local ownerVal = m:FindFirstChild("Owner")
				local stored = m:FindFirstChild("StoredInSlot")
				if ownerVal and stored then
					if ownerVal.Value == player.Name then
						used[stored.Value] = true
					end
				end
			end
		end
	end

	-- iterate slots under plot (prefer parts named SlotX)
	for _, c in ipairs(plot:GetChildren()) do
		if c:IsA("BasePart") or c:IsA("Part") or c.ClassName == "Part" then
			local slotName = c.Name
			if not used[slotName] then
				return slotName
			end
		end
	end

	-- fallback: return nil
	return nil
end

-- PICKUP handler
pickupRemote.OnClientEvent:Connect(function(successOrModel, payload)
	if type(successOrModel) == "boolean" then
		local success = successOrModel
		local info = payload
		if success then
			if info == "addedToInventory" then
				showToast("Gekauft: Item wurde ins Inventar gelegt.")
			elseif info == "pickedUp" then
				showToast("Aufgenommen.")
				-- try to find HeldBrainrots model locally
				task.delay(0.05, function()
					local hb = Workspace:FindFirstChild("HeldBrainrots")
					if hb then
						for _, m in ipairs(hb:GetChildren()) do
							if m:FindFirstChild("Owner") and m.Owner.Value == player.Name then
								startFollowingHeld(m)
								break
							end
						end
					end
				end)
			else
				showToast("Erfolg: " .. tostring(info))
			end
		else
			showToast("Fehler: " .. tostring(info))
			restoreLocalHeldVisuals()
		end
		return
	end

	if typeof(successOrModel) == "Instance" then
		local model = successOrModel
		if model and model.Name then
			showToast("Gekauft: " .. model.Name)
			-- if model is in workspace.HeldBrainrots, follow it
			local parentName = ""
			pcall(function() parentName = tostring(model.Parent and model.Parent:GetFullName()) end)
			if model.Parent == Workspace:FindFirstChild("HeldBrainrots") then
				startFollowingHeld(model)
			else
				-- if it's a Tool instance in Backpack, we won't follow; but mark as held
				startFollowingHeld(model)
			end
		else
			showToast("Kauf: ungültiges Modell erhalten")
		end
		return
	end

	warn("pickupRemote: unbekanntes payload:", successOrModel, payload)
end)

-- PLACE response handler
placeRemote.OnClientEvent:Connect(function(success, payload)
	showPlacingSpinner(false)
	isPlacing = false
	if success then
		showToast("Platziert: " .. tostring(payload))
		-- after a successful place, clear local visuals
		clearLocalHeldVisuals()
	else
		showToast("Platzieren fehlgeschlagen: " .. tostring(payload))
		restoreLocalHeldVisuals()
	end
end)

-- EQUIP response handler
equipResp.OnClientEvent:Connect(function(success, payload)
	local pType = typeof(payload)
	local pName = "(none)"
	pcall(function() pName = payload.Name or tostring(payload) end)
	dbg("equipResp received: success=", success, "payloadType=", pType, "payloadName=", pName)

	if pType == "Instance" then
		-- If server returned workspace model in HeldBrainrots, follow it
		if payload.Parent == Workspace:FindFirstChild("HeldBrainrots") then
			startFollowingHeld(payload)
		else
			-- payload might be Tool in backpack; still attempt to follow if relevant
			startFollowingHeld(payload)
		end
		if success then showToast("Equipped: " .. tostring(pName)) else showToast("Equip fehlgeschlagen: " .. tostring(pName)) end
		return
	end

	if success then
		showToast("Equipped: " .. tostring(payload))
		task.delay(0.05, function()
			local hb = Workspace:FindFirstChild("HeldBrainrots")
			if hb then
				for _, m in ipairs(hb:GetChildren()) do
					if m:FindFirstChild("Owner") and m.Owner.Value == player.Name then
						startFollowingHeld(m)
						break
					end
				end
			end
		end)
	else
		showToast("Equip fehlgeschlagen: " .. tostring(payload))
	end
end)

-- requestPlace: slotInstanceOrName optional; if nil, client attempts to find first free slot
local function requestPlace(slotInstanceOrName)
	if isPlacing then
		showToast("Bitte kurz warten.")
		return
	end

	local forcedModelName = nil
	pcall(function()
		if _G.Client_BrainrotHelpers and type(_G.Client_BrainrotHelpers.GetSelectedToolName) == "function" then
			forcedModelName = _G.Client_BrainrotHelpers.GetSelectedToolName()
		end
	end)

	-- auto-resolve slot if not given
	local slotArg = slotInstanceOrName
	if slotArg == nil then
		local slotName = findFirstFreeSlotName()
		if slotName then
			slotArg = slotName
		else
			showToast("Kein freier Slot gefunden.")
			return
		end
	end

	dbg("requestPlace called; slotArg=", tostring(slotArg),
		"localHeldModel=", localHeldModel and (localHeldModel.Name .. " typeof=" .. typeof(localHeldModel)) or "nil",
		"selectedModelName=", tostring(forcedModelName))

	if not localHeldModel and (forcedModelName == nil or forcedModelName == "") then
		showToast("Du hältst nichts und hast kein Hotbar-Item ausgewählt.")
		return
	end

	isPlacing = true
	showPlacingSpinner(true)
	pcall(function() placeRemote:FireServer(slotArg, forcedModelName) end)
end

local function requestPickup(targetModelOrName)
	pickupRemote:FireServer(targetModelOrName)
end

local function requestEquip(inventoryIndex)
	equipReq:FireServer(inventoryIndex)
end

-- merge helpers into global helpers table
_G.Client_BrainrotHelpers = _G.Client_BrainrotHelpers or {}
do
	local h = _G.Client_BrainrotHelpers
	h.RequestPlace = requestPlace
	h.RequestPickup = requestPickup
	h.RequestEquip = requestEquip
	h.GetHeld = function() return localHeldModel end
end

dbg("✅ BrainrotPickupClient ready (follow-held + auto-slot place)")
