local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local sellRemote = ReplicatedStorage:WaitForChild("BrainrotSell")
local miscShopRemote = ReplicatedStorage:WaitForChild("MiscShopPurchase") -- Shop für andere Gegenstände

local PROMPT_NAME = "SellPrompt"

local currentGui

local function closeDialog()
	if currentGui then
		currentGui:Destroy()
		currentGui = nil
	end
end

local function fadeIn(frame)
	frame.BackgroundTransparency = 0.2
	TweenService:Create(
		frame,
		TweenInfo.new(0.15, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 0.05 }
	):Play()
end

local function buildBaseFrame()
	local screen = Instance.new("ScreenGui")
	screen.Name = "SellerDialog"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 340, 0, 280)
	frame.Position = UDim2.new(0.5, -170, 0.5, -140)
	frame.BackgroundColor3 = Color3.fromRGB(25, 25, 35)
	frame.BackgroundTransparency = 0.05
	frame.Active = true
	frame.Parent = screen

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingBottom = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = frame

	return screen, frame
end

local function getEquippedToolName()
	local char = player.Character
	if not char then return nil end
	for _, t in ipairs(char:GetChildren()) do
		if t:IsA("Tool") then
			return t.Name
		end
	end
	return nil
end

local function openMainDialog()
	closeDialog()
	local screen, frame = buildBaseFrame()
	screen.Parent = player:WaitForChild("PlayerGui")
	currentGui = screen

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 28)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextSize = 18
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Text = "Hallo, ich bin der Miner!"
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = frame

	local body = Instance.new("TextLabel")
	body.Size = UDim2.new(1, 0, 0, 48)
	body.Position = UDim2.new(0, 0, 0, 32)
	body.BackgroundTransparency = 1
	body.Font = Enum.Font.Gotham
	body.TextSize = 14
	body.TextColor3 = Color3.fromRGB(220, 220, 230)
	body.TextWrapped = true
	body.Text = "Ich kaufe deine Brainrots ab und habe hin und wieder andere Gegenstände."
	body.TextXAlignment = Enum.TextXAlignment.Left
	body.Parent = frame

	local btnSell = Instance.new("TextButton")
	btnSell.Size = UDim2.new(1, 0, 0, 40)
	btnSell.Position = UDim2.new(0, 0, 0, 90)
	btnSell.BackgroundColor3 = Color3.fromRGB(60, 130, 255)
	btnSell.TextColor3 = Color3.fromRGB(255, 255, 255)
	btnSell.Font = Enum.Font.GothamBold
	btnSell.TextSize = 16
	btnSell.Text = "Meine Brainrots verkaufen"
	btnSell.AutoButtonColor = true
	btnSell.Parent = frame
	Instance.new("UICorner", btnSell).CornerRadius = UDim.new(0, 8)

	local btnOther = Instance.new("TextButton")
	btnOther.Size = UDim2.new(1, 0, 0, 40)
	btnOther.Position = UDim2.new(0, 0, 0, 140)
	btnOther.BackgroundColor3 = Color3.fromRGB(90, 90, 110)
	btnOther.TextColor3 = Color3.fromRGB(255, 255, 255)
	btnOther.Font = Enum.Font.GothamBold
	btnOther.TextSize = 16
	btnOther.Text = "Andere Gegenstände ansehen"
	btnOther.AutoButtonColor = true
	btnOther.Parent = frame
	Instance.new("UICorner", btnOther).CornerRadius = UDim.new(0, 8)

	btnSell.MouseButton1Click:Connect(function()
		local equipped = getEquippedToolName()
		if equipped then
			sellRemote:FireServer(equipped)
		end
		closeDialog()
	end)

	btnOther.MouseButton1Click:Connect(function()
		-- öffne Shop-Ansicht
		local function openOtherDialog()
			closeDialog()
			local screen2, frame2 = buildBaseFrame()
			screen2.Parent = player:WaitForChild("PlayerGui")
			currentGui = screen2

			local title2 = Instance.new("TextLabel")
			title2.Size = UDim2.new(1, 0, 0, 28)
			title2.BackgroundTransparency = 1
			title2.Font = Enum.Font.GothamBold
			title2.TextSize = 18
			title2.TextColor3 = Color3.fromRGB(255, 255, 255)
			title2.Text = "Andere Gegenstände"
			title2.TextXAlignment = Enum.TextXAlignment.Left
			title2.Parent = frame2

			local body2 = Instance.new("TextLabel")
			body2.Size = UDim2.new(1, 0, 0, 40)
			body2.Position = UDim2.new(0, 0, 0, 32)
			body2.BackgroundTransparency = 1
			body2.Font = Enum.Font.Gotham
			body2.TextSize = 14
			body2.TextColor3 = Color3.fromRGB(220, 220, 230)
			body2.TextWrapped = true
			body2.Text = "Wähle einen Gegenstand aus."
			body2.TextXAlignment = Enum.TextXAlignment.Left
			body2.Parent = frame2

			local y = 90
			local function makeButton(text, color)
				local b = Instance.new("TextButton")
				b.Size = UDim2.new(1, 0, 0, 40)
				b.Position = UDim2.new(0, 0, 0, y)
				b.BackgroundColor3 = color
				b.TextColor3 = Color3.fromRGB(255, 255, 255)
				b.Font = Enum.Font.GothamBold
				b.TextSize = 16
				b.Text = text
				b.AutoButtonColor = true
				b.Parent = frame2
				Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
				y = y + 45
				return b
			end

			local btnPotion = makeButton("Speed-Potion (5 Min Speed)", Color3.fromRGB(60, 160, 90))
			local btnPotionPlus = makeButton("Extra Speed-Potion (schneller, 5 Min)", Color3.fromRGB(80, 100, 180))
			local btnBooster = makeButton("Cash Booster (+10% Income, 5 Min)", Color3.fromRGB(200, 140, 60))

			local btnBack = Instance.new("TextButton")
			btnBack.Size = UDim2.new(1, 0, 0, 40)
			btnBack.Position = UDim2.new(0, 0, 0, y + 10)
			btnBack.BackgroundColor3 = Color3.fromRGB(90, 90, 110)
			btnBack.TextColor3 = Color3.fromRGB(255, 255, 255)
			btnBack.Font = Enum.Font.GothamBold
			btnBack.TextSize = 16
			btnBack.Text = "Zurück"
			btnBack.AutoButtonColor = true
			btnBack.Parent = frame2
			Instance.new("UICorner", btnBack).CornerRadius = UDim.new(0, 8)

			btnPotion.MouseButton1Click:Connect(function()
				miscShopRemote:FireServer("SpeedPotion")
				closeDialog()
			end)

			btnPotionPlus.MouseButton1Click:Connect(function()
				miscShopRemote:FireServer("SpeedPotionPlus")
				closeDialog()
			end)

			btnBooster.MouseButton1Click:Connect(function()
				miscShopRemote:FireServer("CashBooster")
				closeDialog()
			end)

			btnBack.MouseButton1Click:Connect(function()
				openMainDialog()
			end)

			fadeIn(frame2)
		end

		openOtherDialog()
	end)

	fadeIn(frame)
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, triggeringPlayer)
	if triggeringPlayer ~= player then return end
	if prompt.Name ~= PROMPT_NAME then return end
	openMainDialog()
end)

ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt, triggeringPlayer)
	if triggeringPlayer ~= player then return end
	if prompt.Name ~= PROMPT_NAME then return end
	closeDialog()
end)
