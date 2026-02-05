-- InventoryServer.lua (ServerScriptService)
local DataStoreService = game:GetService("DataStoreService")
local ds = DataStoreService:GetDataStore("PlayerInventory_v1")
local Inventory = {}
local cache = {}

local function key(userId) return "inv_"..tostring(userId) end

function Inventory:LoadForPlayer(player)
	cache[player.UserId] = cache[player.UserId] or {}
	local ok, data = pcall(function() return ds:GetAsync(key(player.UserId)) end)
	if ok and data and data.Items then
		cache[player.UserId] = data.Items
	end
	return cache[player.UserId]
end

function Inventory:GetInventory(player)
	cache[player.UserId] = cache[player.UserId] or {}
	return cache[player.UserId]
end

function Inventory:AddToInventory(player, item)
	cache[player.UserId] = cache[player.UserId] or {}
	table.insert(cache[player.UserId], item)
	pcall(function()
		ds:UpdateAsync(key(player.UserId), function(old)
			old = old or {}
			old.Items = cache[player.UserId]
			return old
		end)
	end)
end

function Inventory:RemoveFromInventory(player, index)
	local inv = self:GetInventory(player)
	if not inv[index] then return false end
	table.remove(inv, index)
	pcall(function()
		ds:UpdateAsync(key(player.UserId), function(old)
			old = old or {}
			old.Items = inv
			return old
		end)
	end)
	return true
end

return Inventory
