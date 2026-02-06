local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local buyRemote = ReplicatedStorage:WaitForChild("MiscShopPurchase")

-- Produkte
local SPEED_POTION_ID = "SpeedPotion"
local SPEED_POTION_PLUS_ID = "SpeedPotionPlus"
local CASH_BOOSTER_ID = "CashBooster"

-- Preise
local SPEED_POTION_PRICE = 50
local SPEED_POTION_PLUS_PRICE = 500 -- 10x teurer
local CASH_BOOSTER_PRICE = 100

-- Effekte
local SPEED_DURATION = 300
local SPEED_MULTIPLIER = 1.6
local SPEED_PLUS_MULTIPLIER = 2.0 -- etwas schneller, nicht zu wild
local DEFAULT_WALKSPEED = 16

local CASH_BOOST_VALUE = 0.10
local CASH_BOOST_DURATION = 300

local boostUntil = {}       -- userId -> expireTime (os.clock)
local incomeBoostUntil = {} -- userId -> expireTime (os.clock)

local function applyIncomeBoost(player, value, duration)
	player:SetAttribute("IncomeBoost", value)
	local expireAt = os.clock() + duration
	incomeBoostUntil[player.UserId] = expireAt

	task.spawn(function()
		task.wait(duration + 0.05)
		if incomeBoostUntil[player.UserId] and incomeBoostUntil[player.UserId] <= os.clock() then
			incomeBoostUntil[player.UserId] = nil
			player:SetAttribute("IncomeBoost", 0)
		end
	end)
end

local function giveSpeedPotion(player, isPlus)
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return end

	local tool = Instance.new("Tool")
	tool.Name = isPlus and SPEED_POTION_PLUS_ID or SPEED_POTION_ID
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool.ToolTip = "5 Minuten Speed-Boost"
	tool:SetAttribute("iconId", "rbxassetid://0") -- bei Bedarf Icon-ID setzen

	tool.Activated:Connect(function()
		pcall(function() tool:Destroy() end)

		local char = player.Character
		local hum = char and char:FindFirstChildWhichIsA("Humanoid")
		if not hum then return end

		local now = os.clock()
		local expireAt = now + SPEED_DURATION
		boostUntil[player.UserId] = expireAt

		local mult = isPlus and SPEED_PLUS_MULTIPLIER or SPEED_MULTIPLIER
		local target = math.max(hum.WalkSpeed, DEFAULT_WALKSPEED * mult)
		hum.WalkSpeed = target

		task.spawn(function()
			task.wait(SPEED_DURATION + 0.05)
			if boostUntil[player.UserId] and boostUntil[player.UserId] <= os.clock() then
				boostUntil[player.UserId] = nil
				local c = player.Character
				local h = c and c:FindFirstChildWhichIsA("Humanoid")
				if h then
					h.WalkSpeed = DEFAULT_WALKSPEED
				end
			end
		end)
	end)

	tool.Parent = backpack
end

local function handlePurchase(player, productId)
	local stats = player:FindFirstChild("leaderstats")
	local gold = stats and stats:FindFirstChild("Gold")
	if not gold then return end

	if productId == SPEED_POTION_ID then
		if gold.Value < SPEED_POTION_PRICE then return end
		gold.Value -= SPEED_POTION_PRICE
		giveSpeedPotion(player, false)
		return
	elseif productId == SPEED_POTION_PLUS_ID then
		if gold.Value < SPEED_POTION_PLUS_PRICE then return end
		gold.Value -= SPEED_POTION_PLUS_PRICE
		giveSpeedPotion(player, true)
		return
	elseif productId == CASH_BOOSTER_ID then
		if gold.Value < CASH_BOOSTER_PRICE then return end
		gold.Value -= CASH_BOOSTER_PRICE
		applyIncomeBoost(player, CASH_BOOST_VALUE, CASH_BOOST_DURATION)
		return
	end
end

buyRemote.OnServerEvent:Connect(handlePurchase)
