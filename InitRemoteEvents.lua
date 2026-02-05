-- InitRemoteEvents.lua (ServerScriptService)
-- Erstellt frühzeitig die benötigten RemoteEvents in ReplicatedStorage,
-- damit Clients beim Start zuverlässig darauf zugreifen können.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DEBUG = false

local function ensureRemoteEvent(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if r and r:IsA("RemoteEvent") then
		return r
	end
	local new = Instance.new("RemoteEvent")
	new.Name = name
	new.Parent = ReplicatedStorage
	if DEBUG then
		print("InitRemoteEvents: created RemoteEvent", name)
	end
	return new
end

local function ensureRemoteFunction(name)
	local r = ReplicatedStorage:FindFirstChild(name)
	if r and r:IsA("RemoteFunction") then
		return r
	end
	local new = Instance.new("RemoteFunction")
	new.Name = name
	new.Parent = ReplicatedStorage
	if DEBUG then
		print("InitRemoteEvents: created RemoteFunction", name)
	end
	return new
end

-- Ensure commonly-used remotes exist
ensureRemoteEvent("BrainrotPickup")
sureRemoteEvent("BrainrotPlace")
sureRemoteEvent("EquipRequest")
sureRemoteEvent("EquipResponse")
sureRemoteEvent("BrainrotSell")

-- If you use any RemoteFunctions, ensure them too, e.g.:
-- ensureRemoteFunction("InventoryRequest")

-- Optional: ensure BrainrotModels folder exists (used by RollSystem)
if not ReplicatedStorage:FindFirstChild("BrainrotModels") then
	local f = Instance.new("Folder")
	f.Name = "BrainrotModels"
	f.Parent = ReplicatedStorage
	if DEBUG then
		print("InitRemoteEvents: created placeholder ReplicatedStorage.BrainrotModels")
	end
end

-- Optional: ensure Sounds folder exists
if not ReplicatedStorage:FindFirstChild("Sounds") then
	local s = Instance.new("Folder")
	s.Name = "Sounds"
	s.Parent = ReplicatedStorage
	if DEBUG then
		print("InitRemoteEvents: created placeholder ReplicatedStorage.Sounds")
	end
end

if DEBUG then
	print("InitRemoteEvents ready")
end