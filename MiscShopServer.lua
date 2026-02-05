local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local buyRemote = ReplicatedStorage:WaitForChild("MiscShopPurchase")

local SPEED_POTION_ID = "SpeedPotion"
local SPEED_POTION_PRICE = 50          -- Preis anpassen
local SPEED_MULTIPLIER = 1.6           -- Laufgeschwindigkeit-Multiplikator
local SPEED_DURATION = 300             -- 5 Minuten
local DEFAULT_WALKSPEED = 16

local boostUntil = {} -- userId -> expireTime (os.clock)

local function giveSpeedPotion(player)
	local backpack = player:FindFirstChild("Backpack")
	if not backpack then return end

	local tool = Instance.new("Tool")
	tool.Name = SPEED_POTION_ID
	tool.RequiresHandle = false
	tool.CanBeDropped = false
	tool.ToolTip = "5 Minuten Speed-Boost"
	tool:SetAttribute("iconId", "rbxassetid://0") -- Icon-ID nach Bedarf setzen

	tool.Activated:Connect(function()
		-- Tool sofort entfernen
		pcall(function() tool:Destroy() end)

		local char = player.Character
		local hum = char and char:FindFirstChildWhichIsA("Humanoid")
		if not hum then return end

		local now = os.clock()
		local expireAt = now + SPEED_DURATION
		boostUntil[player.UserId] = expireAt

		local target = math.max(hum.WalkSpeed, DEFAULT_WALKSPEED * SPEED_MULTIPLIER)
		hum.WalkSpeed = target

		-- Rücksetzung nach Ablauf, falls kein neuer Boost gestartet wurde
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
	if productId ~= SPEED_POTION_ID then return end

	local stats = player:FindFirstChild("leaderstats")
	local gold = stats and stats:FindFirstChild("Gold")
	if not gold or gold.Value < SPEED_POTION_PRICE then
		return -- zu wenig Gold, einfach abbrechen
	end

	gold.Value -= SPEED_POTION_PRICE
	giveSpeedPotion(player)
end

buyRemote.OnServerEvent:Connect(handlePurchase)
