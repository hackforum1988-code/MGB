local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local DEBUG = false

local pickupRemote = ReplicatedStorage:WaitForChild("BrainrotPickup")
local placeRemote  = ReplicatedStorage:WaitForChild("BrainrotPlace")
local equipReq     = ReplicatedStorage:WaitForChild("EquipRequest")
local equipResp    = ReplicatedStorage:WaitForChild("EquipResponse")

local localHeldModel = nil
local isPlacing = false

local function showToast(text) print("[TOAST]", text) end
local function showPlacingSpinner(show) if show then print("Placing spinner ON") else print("Placing spinner OFF") end end
local function clearLocalHeldVisuals() end
local function restoreLocalHeldVisuals() end
local function setLocalHeldModel(modelInstance)
	localHeldModel = modelInstance
	if DEBUG then print("Local held model set to:", modelInstance and modelInstance.Name or "nil") end
end

pickupRemote.OnClientEvent:Connect(function(successOrModel, payload)
	if type(successOrModel) == "boolean" then
		local success = successOrModel
		local info = payload
		if success then
			if info == "addedToInventory" then
				showToast("Gekauft: Item wurde ins Inventar gelegt.")
			elseif info == "pickedUp" then
				showToast("Aufgenommen.")
				task.delay(0.05, function()
					local hb = workspace:FindFirstChild("HeldBrainrots")
					if hb then
						for _, m in ipairs(hb:GetChildren()) do
							if m:FindFirstChild("Owner") and m.Owner.Value == player.Name then
								setLocalHeldModel(m)
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
			setLocalHeldModel(model)
		else
			showToast("Kauf: ungültiges Modell erhalten")
		end
		return
	end

	warn("pickupRemote: unbekanntes payload:", successOrModel, payload)
end)

placeRemote.OnClientEvent:Connect(function(success, payload)
	showPlacingSpinner(false)
	isPlacing = false
	if success then
		showToast("Platziert: " .. tostring(payload))
		clearLocalHeldVisuals()
		localHeldModel = nil
	else
		showToast("Platzieren fehlgeschlagen: " .. tostring(payload))
		restoreLocalHeldVisuals()
	end
end)

equipResp.OnClientEvent:Connect(function(success, payload)
	if success then
		showToast("Equipped: " .. tostring(payload))
		task.delay(0.05, function()
			local hb = workspace:FindFirstChild("HeldBrainrots")
			if hb then
				for _, m in ipairs(hb:GetChildren()) do
					if m:FindFirstChild("Owner") and m.Owner.Value == player.Name then
						setLocalHeldModel(m)
						break
					end
				end
			end
		end)
	else
		showToast("Equip fehlgeschlagen: " .. tostring(payload))
	end
end)

local function requestPlace(slotInstanceOrName)
	if isPlacing then
		showToast("Bitte kurz warten.")
		return
	end
	if not localHeldModel then
		showToast("Du hältst nichts.")
		return
	end
	isPlacing = true
	showPlacingSpinner(true)
	-- WICHTIG: Slot-Namen (z.B. "Slot1") oder Slot-Instance weitergeben
	placeRemote:FireServer(slotInstanceOrName)
end

local function requestPickup(targetModelOrName)
	pickupRemote:FireServer(targetModelOrName)
end

local function requestEquip(inventoryIndex)
	equipReq:FireServer(inventoryIndex)
end

_G.Client_BrainrotHelpers = {
	RequestPlace = requestPlace,
	RequestPickup = requestPickup,
	RequestEquip = requestEquip,
	GetHeld = function() return localHeldModel end,
}

print("✅ BrainrotPickupClient ready (robust handlers)")
