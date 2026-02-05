-- GoldHUD.lua (StarterPlayerScripts)
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Warte auf leaderstats (ohne kurzen Timeout, damit HUD nicht fehlschlägt)
local leaderstats = player:WaitForChild("leaderstats")
local goldValue = leaderstats:WaitForChild("Gold")

-- Erstelle ScreenGui
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GoldHUD"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local hudFrame = Instance.new("Frame")
hudFrame.Name = "HUDFrame"
hudFrame.Size = UDim2.new(0, 160, 0, 48)
hudFrame.Position = UDim2.new(1, -180, 0, 12)
hudFrame.BackgroundTransparency = 0.25
hudFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
hudFrame.BorderSizePixel = 0
hudFrame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 8)
corner.Parent = hudFrame

local iconLabel = Instance.new("TextLabel")
iconLabel.Name = "GoldIcon"
iconLabel.Size = UDim2.new(0, 48, 1, 0)
iconLabel.Position = UDim2.new(0, 6, 0, 0)
iconLabel.BackgroundTransparency = 1
iconLabel.Text = "💰"
iconLabel.TextScaled = true
iconLabel.Font = Enum.Font.GothamBold
iconLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
iconLabel.Parent = hudFrame

local amountLabel = Instance.new("TextLabel")
amountLabel.Name = "GoldAmount"
amountLabel.Size = UDim2.new(1, -60, 1, 0)
amountLabel.Position = UDim2.new(0, 60, 0, 0)
amountLabel.BackgroundTransparency = 1
amountLabel.Text = tostring(goldValue.Value)
amountLabel.TextScaled = true
amountLabel.Font = Enum.Font.GothamBold
amountLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
amountLabel.TextXAlignment = Enum.TextXAlignment.Left
amountLabel.Parent = hudFrame

local smallLabel = Instance.new("TextLabel")
smallLabel.Name = "SmallLabel"
smallLabel.Size = UDim2.new(1, -60, 0, 14)
smallLabel.Position = UDim2.new(0, 60, 1, -16)
smallLabel.BackgroundTransparency = 1
smallLabel.Text = "Gold"
smallLabel.TextScaled = false
smallLabel.Font = Enum.Font.Gotham
smallLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
smallLabel.TextSize = 12
smallLabel.TextXAlignment = Enum.TextXAlignment.Left
smallLabel.Parent = hudFrame

-- Update-Funktion
local function updateAmount()
	amountLabel.Text = tostring(goldValue.Value)
end

goldValue:GetPropertyChangedSignal("Value"):Connect(updateAmount)
updateAmount()

-- kleine Pop-Animation bei Änderung
goldValue.Changed:Connect(function()
	pcall(function()
		hudFrame:TweenSize(UDim2.new(0, 176, 0, 52), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.08, true)
		task.wait(0.08)
		hudFrame:TweenSize(UDim2.new(0, 160, 0, 48), Enum.EasingDirection.Out, Enum.EasingStyle.Quad, 0.12, true)
	end)
end)

print("✅ GoldHUD ready")
