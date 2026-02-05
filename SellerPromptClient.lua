local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local sellRemote = ReplicatedStorage:WaitForChild("BrainrotSell")

local PROMPT_NAME = "SellPrompt"

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

-- GUI-Bau (einfaches Overlay)
local function buildDialog()
	local screen = Instance.new("ScreenGui")
	screen.Name = "SellerDialog"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, 320, 0, 200)
	frame.Position = UDim2.new(0.5, -160, 0.5, -100)
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

	return screen, frame, btnSell, btnOther
end

local currentGui

local function closeDialog()
	if currentGui then
		currentGui:Destroy()
		currentGui = nil
	end
end

local function openDialog()
	if currentGui then closeDialog() end
	local gui, frame, btnSell, btnOther = buildDialog()
	gui.Parent = player:WaitForChild("PlayerGui")
	currentGui = gui

	btnSell.MouseButton1Click:Connect(function()
		local equipped = getEquippedToolName()
		if equipped then
			sellRemote:FireServer(equipped) -- Server berechnet Preis/Gutschrift
		end
		closeDialog()
	end)

	btnOther.MouseButton1Click:Connect(function()
		-- TODO: Öffne Shop-UI für andere Gegenstände
		closeDialog()
	end)

	-- Kleine Fade-In-Optik
	frame.BackgroundTransparency = 0.2
	TweenService:Create(frame, TweenInfo.new(0.15), {BackgroundTransparency = 0.05}):Play()
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, plr)
	if plr ~= player then return end
	if prompt.Name ~= PROMPT_NAME then return end
	openDialog()
end)

print("SellerPromptClient ready (Dialog)")
