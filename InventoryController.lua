-- services
local StarterGui = game:GetService("StarterGui")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- references
local player = Players.LocalPlayer
local backpack = player:WaitForChild("Backpack")
local camera = workspace.CurrentCamera

-- DISABLE BASIC ROBLOX HOTBAR
StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

local CustomInventoryGUI = script.Parent
local hotBar = CustomInventoryGUI.hotBar
local Inventory = CustomInventoryGUI.Inventory
local toolButton = script.toolButton

local inventoryHandler = require(script.SETTINGS)

print("InventoryController: started (client)")
_G.Client_BrainrotHelpers = _G.Client_BrainrotHelpers or {}
_G.Client_BrainrotHelpers.RequestPickup = function(target)
	print("Client helper RequestPickup called, target:", target)
	local pickup = ReplicatedStorage:FindFirstChild("BrainrotPickup")
	if pickup then pickup:FireServer(target) else print("BrainrotPickup Remote missing") end
end

-- Equip Remote
local equipRequest = ReplicatedStorage:WaitForChild("EquipRequest")

-- Keycode → Slot-Index Mapping
local keyToIndex = {
	[Enum.KeyCode.One]   = 1,
	[Enum.KeyCode.Two]   = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four]  = 4,
	[Enum.KeyCode.Five]  = 5,
	[Enum.KeyCode.Six]   = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
	[Enum.KeyCode.Nine]  = 9,
}

-- Cache Humanoid
local character = player.Character or player.CharacterAdded:Wait()
local humanoid = character:FindFirstChildWhichIsA("Humanoid")

local function onCharacterAdded(char)
	character = char
	humanoid = character:FindFirstChildWhichIsA("Humanoid")
end
player.CharacterAdded:Connect(onCharacterAdded)

-- Lokales Ausrüsten, damit Tool sichtbar ist
local function equipToolLocal(index)
	if not humanoid then return end
	local toolObj = inventoryHandler.OBJECTS.HotBar[index]
	if not toolObj or not toolObj.Tool then return end
	if toolObj.Tool.Parent ~= backpack and toolObj.Tool.Parent ~= character then
		toolObj.Tool.Parent = backpack
	end
	humanoid:EquipTool(toolObj.Tool)
end

local function handleHotbarKey(keyCode)
	local index = keyToIndex[keyCode]
	if not index then return end
	if index < 1 or index > inventoryHandler.slotAmount then return end
	-- Server informieren (Persistenz/Validierung)
	equipRequest:FireServer(index)
	-- Lokal anzeigen/ausrüsten
	equipToolLocal(index)
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.UserInputType == Enum.UserInputType.Keyboard then
		if keyToIndex[input.KeyCode] then
			handleHotbarKey(input.KeyCode)
		end
	end
end)

-- Hilfsfunktion: Slot-Visuals aktualisieren (Text + Bild)
local function updateSlotVisual(index)
	local toolFrame = hotBar:FindFirstChild(index)
	if not toolFrame then return end

	toolFrame.toolNumber.Text = tostring(index)
	toolFrame.LayoutOrder = index -- fixierte Position im Grid

	local toolObject = inventoryHandler.OBJECTS.HotBar[index]
	if toolObject and toolObject.Tool then
		local tool = toolObject.Tool
		toolFrame.toolName.Text = tool.Name or ""
		local amt = tool:GetAttribute("amount")
		toolFrame.toolAmount.Text = amt and tostring(amt) or ""

		local img = tool:GetAttribute("iconId") or tool:GetAttribute("Icon") or ""
		if img == "" and tool.TextureId then
			img = tool.TextureId
		end
		if img == "" and tool:FindFirstChild("Handle") and tool.Handle:IsA("BasePart") then
			local mesh = tool.Handle:FindFirstChildWhichIsA("SpecialMesh") or tool.Handle:FindFirstChild("Mesh")
			if mesh and mesh.TextureId and mesh.TextureId ~= "" then
				img = mesh.TextureId
			end
		end
		if toolFrame:FindFirstChild("toolImage") then
			toolFrame.toolImage.Image = img or ""
		end
	else
		toolFrame.toolName.Text = ""
		toolFrame.toolAmount.Text = ""
		if toolFrame:FindFirstChild("toolImage") then
			toolFrame.toolImage.Image = ""
		end
	end
end

-- Baut/aktualisiert alle Frames, fixiert Nummern/Positionen 1..slotAmount
local function showSlots()
	for index = 1, inventoryHandler.slotAmount do
		local frame = hotBar:FindFirstChild(index)
		if not frame then
			frame = toolButton:Clone()
			frame.Name = index
			frame.Parent = hotBar
		end
		frame.LayoutOrder = index
		updateSlotVisual(index)
	end
end

-- Leert/aktualisiert Slots ohne Zerstörung
local function clearEmptySlots()
	for index = 1, inventoryHandler.slotAmount do
		updateSlotVisual(index)
	end
end

local function manageInventory (_, inputState)
	if inputState == Enum.UserInputState.Begin then
		Inventory.Visible = not Inventory.Visible
		local currentState = Inventory.Visible

		inventoryHandler:removeCurrentDescription()
		if currentState then
			showSlots()
			CustomInventoryGUI.openButton.Position = UDim2.fromScale(0.5,0.5)
			CustomInventoryGUI.openButton.info.Text = "(') close inventory"
		else
			if not inventoryHandler.SETTINGS.SHOW_EMPTY_TOOL_FRAMES_IN_HOTBAR then
				clearEmptySlots()
			end
			CustomInventoryGUI.openButton.Position = UDim2.fromScale(0.5,0.909)
			CustomInventoryGUI.openButton.info.Text = "(') open inventory"
		end
	end
end

local function searchTool()
	inventoryHandler:searchTool()
end
local function newTool(tool)
	if tool:IsA("Tool") then
		inventoryHandler:newTool(tool)
		showSlots()
	end
end

local function reloadInventory(character)
	inventoryHandler.currentlyEquipped = nil
	backpack = player:WaitForChild("Backpack")
	for _, tool in pairs(backpack:GetChildren()) do
		if tool:IsA("Tool") then
			newTool(tool)
		end
	end
	showSlots()
end

player.CharacterAdded:Connect(reloadInventory)
backpack.ChildAdded:Connect(newTool)
backpack.ChildRemoved:Connect(function()
	showSlots()
end)

UserInputService.InputBegan:Connect(function(key, gameProcessed)
	if not gameProcessed and key.KeyCode == Enum.KeyCode.Quote then
		manageInventory(nil, Enum.UserInputState.Begin)
	end
end)
ContextActionService:BindAction("searchTool", searchTool, false, Enum.KeyCode.F)

showSlots()
