-- PlotPersistence.lua (ModuleScript in ServerScriptService)
-- Speicher/Restore für Plots + Brainrots, mit Debug-Logging und Yaw-Persistenz.
-- Sauber, ohne goto / riskante Syntax.

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local PlotPersistence = {}

local DEBUG = false
local DATASTORE_NAME = "PlayerPlots_v4"
local ds = nil

local function dprint(...)
	if DEBUG then
		print("[PlotPersistence]", ...)
	end
end

local function tryGetDataStore()
	if ds then return ds end
	local inStudio = RunService:IsStudio()
	if inStudio then
		local ok, ref = pcall(function() return DataStoreService:GetDataStore(DATASTORE_NAME) end)
		if ok then ds = ref end
		return ds
	else
		ds = DataStoreService:GetDataStore(DATASTORE_NAME)
		return ds
	end
end

local SAVE_RETRIES = 5
local RETRY_BASE_DELAY = 0.25

local function retryAsync(fn, retries)
	retries = retries or SAVE_RETRIES
	local delayTime = RETRY_BASE_DELAY
	for i = 1, retries do
		local ok, res = pcall(fn)
		if ok then
			return true, res
		end
		dprint("retryAsync: attempt", i, "failed:", res)
		task.wait(delayTime)
		delayTime = delayTime * 2
	end
	return false, "max retries exceeded"
end

-- BuildSaveForPlayer: sammelt Slots & Gold (+Yaw wenn vorhanden)
function PlotPersistence:BuildSaveForPlayer(player)
	local out = { Plots = {}, Gold = 0, Updated = os.time() }

	-- Gold
	if player and player:FindFirstChild("leaderstats") then
		local gold = player.leaderstats:FindFirstChild("Gold")
		if gold and gold:IsA("IntValue") then
			out.Gold = gold.Value
		end
	end

	local plotsFolder = workspace:FindFirstChild("Plots")
	if not plotsFolder then
		warn("PlotPersistence: workspace.Plots fehlt; kein Plot-Save möglich.")
		return out
	end

	for _, plot in ipairs(plotsFolder:GetChildren()) do
		if plot and plot:IsA("Instance") then
			local ownerAttr = plot:GetAttribute("Owner")
			if ownerAttr == player.Name then
				local plotData = { Slots = {} }

				for _, slot in ipairs(plot:GetChildren()) do
					local isSlot = false
					if type(slot.Name) == "string" and slot.Name:match("^Slot") then
						isSlot = true
					elseif slot:GetAttribute("IsSlot") == true then
						isSlot = true
					elseif slot:FindFirstChild("SlotMarker") then
						isSlot = true
					end

					if not isSlot then
						-- not a slot, skip
					else
						if DEBUG then dprint("BuildSave: scanning slot", plot.Name, slot.Name) end

						local foundMeta = nil
						local brainrotsFolder = workspace:FindFirstChild("Brainrots")
						if brainrotsFolder then
							for _, obj in ipairs(brainrotsFolder:GetDescendants()) do
								if obj and obj:IsA("Model") then
									local storedTag = obj:FindFirstChild("StoredInSlot")
									local ownerTag = obj:FindFirstChild("Owner")
									if storedTag and ownerTag and storedTag.Value == slot.Name and ownerTag.Value == player.Name then
										-- found placed model for this slot
										if DEBUG then dprint("BuildSave: Found brainrot for slot:", slot.Name, "->", obj.Name) end
										foundMeta = {}
										local mn = obj:FindFirstChild("ModelName")
										local rarity = obj:FindFirstChild("Rarity")
										local mining = obj:FindFirstChild("MiningPower")
										local income = obj:FindFirstChild("IncomePerSec")
										foundMeta.ModelName = (mn and mn.Value) or obj.Name
										foundMeta.Rarity = (rarity and rarity.Value) or (obj:GetAttribute("Rarity") or "Common")
										foundMeta.MiningPower = (mining and tonumber(mining.Value)) or (obj:GetAttribute("MiningPower") or 0)
										foundMeta.IncomePerSec = (income and tonumber(income.Value)) or (obj:GetAttribute("IncomePerSec") or 0)
										foundMeta.StoredInSlot = slot.Name
										local yawAttr = nil
										pcall(function() yawAttr = obj:GetAttribute("Yaw") end)
										if yawAttr ~= nil then
											foundMeta.Yaw = yawAttr
										end
										break
									end
								end
							end
						end

						if foundMeta then
							plotData.Slots[slot.Name] = foundMeta
						else
							if DEBUG then dprint("BuildSave: no brainrot found for slot", slot.Name) end
						end
					end
				end

				out.Plots[plot.Name] = plotData
			end
		end
	end

	if DEBUG then
		local ok, js = pcall(function() return HttpService:JSONEncode(out) end)
		if ok then dprint("BuildSaveForPlayer payload:", js) else dprint("BuildSaveForPlayer payload (table):", out) end
	end

	return out
end

-- SavePlayer: speichert BuildSaveForPlayer via DataStore
function PlotPersistence:SavePlayer(player)
	local dsRef = tryGetDataStore()
	if not dsRef then
		warn("PlotPersistence: DataStore nicht verfügbar; Save übersprungen.")
		return false, "datastore unavailable"
	end

	local payload = self:BuildSaveForPlayer(player)
	local key = "player_" .. tostring(player.UserId)

	local suc, res = retryAsync(function() return dsRef:SetAsync(key, payload) end, SAVE_RETRIES)
	if not suc then
		warn("PlotPersistence: Save fehlgeschlagen:", res)
		return false, res
	end

	if DEBUG then dprint("PlotPersistence: Saved data for", player.Name, "key=", key) end
	return true
end

-- RestorePlayer: lädt Daten und ruft spawnCallback(plot, slotName, slotInfo)
-- startIncomeCallback(model) optional
function PlotPersistence:RestorePlayer(player, spawnCallback, startIncomeCallback)
	local dsRef = tryGetDataStore()
	if not dsRef then
		warn("PlotPersistence: DataStore nicht verfügbar; Restore übersprungen.")
		return false, "datastore unavailable"
	end

	local key = "player_" .. tostring(player.UserId)
	local suc, data = retryAsync(function() return dsRef:GetAsync(key) end, SAVE_RETRIES)
	if not suc then
		if DEBUG then dprint("PlotPersistence: Kein Save vorhanden oder Fehler beim Laden für", player.Name) end
		return false, "no data"
	end

	if not data or type(data) ~= "table" or not data.Plots then
		if DEBUG then dprint("PlotPersistence: Ungültige Save-Daten für", player.Name, "data=", data) end
		return false, "invalid data"
	end

	if DEBUG then
		local ok, js = pcall(function() return HttpService:JSONEncode(data) end)
		if ok then dprint("RestorePlayer: loaded data for", player.Name, "->", js) else dprint("RestorePlayer: loaded data (table) for", player.Name) end
	end

	local plotsFolder = workspace:FindFirstChild("Plots")
	if not plotsFolder then
		warn("PlotPersistence: workspace.Plots fehlt; Restore nicht möglich.")
		return false, "no plots folder"
	end

	-- iterate plots
	for plotName, plotData in pairs(data.Plots or {}) do
		if DEBUG then dprint("RestorePlayer: processing plot", plotName) end

		if type(plotData) ~= "table" or type(plotData.Slots) ~= "table" then
			if DEBUG then dprint("RestorePlayer: plotData invalid for", plotName) end
			-- skip to next plot
		else
			local plot = plotsFolder:FindFirstChild(plotName)
			if not plot then
				if DEBUG then dprint("RestorePlayer: plot not found in workspace:", plotName) end
			else
				for slotName, slotInfo in pairs(plotData.Slots or {}) do
					if DEBUG then dprint("RestorePlayer: attempting spawn for", plotName, slotName, "slotInfo.ModelName=", slotInfo and slotInfo.ModelName or "nil") end
					if type(spawnCallback) ~= "function" then
						if DEBUG then dprint("RestorePlayer: spawnCallback missing") end
					else
						local okSpawn, spawned = pcall(function() return spawnCallback(plot, slotName, slotInfo) end)
						if not okSpawn then
							dprint("RestorePlayer: spawnCallback errored for", plotName, slotName, "err=", spawned)
						else
							if spawned then
								if startIncomeCallback and type(startIncomeCallback) == "function" then
									pcall(function() startIncomeCallback(spawned) end)
								end
								if DEBUG then dprint("RestorePlayer: spawned model for", plotName, slotName) end
							else
								if DEBUG then dprint("RestorePlayer: spawnCallback returned nil for", plotName, slotName) end
							end
						end
					end
				end
			end
		end
	end

	return true
end

return PlotPersistence
