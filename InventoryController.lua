-- InventoryController.lua (Client) - vollständig ohne 'and' Operator
-- Bitte 1:1 ersetzen in StarterGui -> Custom Inventory -> InventoryController (LocalScript)

local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local backpack = player:WaitForChild("Backpack")

StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

local GuiRoot = script.Parent
local hotBar = GuiRoot:WaitForChild("hotBar")
local Inventory = GuiRoot:WaitForChild("Inventory")
local toolButton = script:WaitForChild("toolButton")

local function dprint(...)
	if RunService:IsStudio() then
		print("[INV]", ...)
	end
end

-- sichere SETTINGS require
local function tryRequireSettings()
	local candidates = {}
	local a = script:FindFirstChild("SETTINGS")
	if a then table.insert(candidates, a) end
	if script.Parent then
		local b = script.Parent:FindFirstChild("SETTINGS")
		if b then table.insert(candidates, b) end
	end
	local c = ReplicatedStorage:FindFirstChild("SETTINGS")
	if c then table.insert(candidates, c) end

	for i = 1, #candidates do
		local modInstance = candidates[i]
		if modInstance and modInstance:IsA("ModuleScript") then
			local ok, mod = pcall(require, modInstance)
			if ok and type(mod) == "table" then
				dprint("Loaded SETTINGS from", modInstance:GetFullName())
				return mod
			end
		end
	end

	-- fallback
	local fallback = {}
	fallback.OBJECTS = { HotBar = {}, Inventory = {} }
	fallback.SETTINGS = {}
	fallback.slotAmount = 9
	fallback.inventoryCapacity = 40
	dprint("Using fallback SETTINGS")
	return fallback
end

local inventoryHandler = tryRequireSettings()
if type(inventoryHandler.OBJECTS) ~= "table" then inventoryHandler.OBJECTS = { HotBar = {}, Inventory = {} } end
if type(inventoryHandler.OBJECTS.HotBar) ~= "table" then inventoryHandler.OBJECTS.HotBar = {} end
if type(inventoryHandler.OBJECTS.Inventory) ~= "table" then inventoryHandler.OBJECTS.Inventory = {} end
if type(inventoryHandler.SETTINGS) ~= "table" then inventoryHandler.SETTINGS = {} end
if type(inventoryHandler.slotAmount) ~= "number" then inventoryHandler.slotAmount = 9 end
if type(inventoryHandler.inventoryCapacity) ~= "number" then inventoryHandler.inventoryCapacity = 40 end

-- Visual defaults (keine 'and' im Kommentar)
local DEFAULT_TEXT_COLOR = Color3.fromRGB(255,255,255)
local DEFAULT_STROKE_COLOR = Color3.fromRGB(0,0,0)
local DEFAULT_SELECT_BG = Color3.fromRGB(60,135,200)
local DEFAULT_BOX_BG = Color3.fromRGB(255,255,255)
local DEFAULT_SELECT_BORDER = Color3.fromRGB(10,90,160)
local DEFAULT_BOX_BORDER = Color3.fromRGB(0,0,0)

local SELECT_BG = DEFAULT_SELECT_BG
local DEFAULT_BG = DEFAULT_BOX_BG
local SELECT_BORDER = DEFAULT_SELECT_BORDER
local DEFAULT_BORDER = DEFAULT_BOX_BORDER

local ssettings = inventoryHandler.SETTINGS
if type(ssettings) == "table" then
	if ssettings.SELECT_BG_COLOR then SELECT_BG = ssettings.SELECT_BG_COLOR end
	if ssettings.BOX_BG_COLOR then DEFAULT_BG = ssettings.BOX_BG_COLOR end
	if ssettings.SELECT_BORDER_COLOR then SELECT_BORDER = ssettings.SELECT_BORDER_COLOR end
	if ssettings.BOX_BORDER_COLOR then DEFAULT_BORDER = ssettings.BOX_BORDER_COLOR end
end

-- safe disconnect helper
local function safeDisconnect(conn)
	if conn == nil then return end
	pcall(function()
		if conn and type(conn.Disconnect) == "function" then
			conn:Disconnect()
		end
	end)
end

-- Tool helper
local function isToolSafe(inst)
	if not inst then return false end
	local ok, res = pcall(function() return inst:IsA("Tool") end)
	if ok and res then return true end
	return false
end

local function findToolInBackpackByName(name)
	if type(name) ~= "string" then return nil end
	local inst = backpack:FindFirstChild(name)
	if inst then
		if inst:IsA("Tool") then return inst end
	end
	local desc = backpack:GetDescendants()
	for i = 1, #desc do
		local v = desc[i]
		if v and v:IsA("Tool") then
			if v.Name == name then return v end
		end
	end
	return nil
end

-- create UI frame
local function createToolFrame(tool, parentKind, position)
	local container = Inventory:FindFirstChild("Frame")
	if not container then container = Inventory end
	if parentKind == "HotBar" then container = hotBar end

	local frame = toolButton:Clone()
	if parentKind == "Inventory" then
		frame.Name = tool.Name
	else
		if position then frame.Name = tostring(position) else frame.Name = tostring(frame.Name) end
	end

	pcall(function()
		frame.Visible = true
		frame.ZIndex = 2

		local tn = frame:FindFirstChild("toolName")
		if tn then
			tn.Text = tool.Name or ""
			tn.TextScaled = true
			tn.TextColor3 = DEFAULT_TEXT_COLOR
			pcall(function() tn.TextStrokeColor3 = DEFAULT_STROKE_COLOR end)
			pcall(function() tn.TextStrokeTransparency = 0 end)
			tn.TextTransparency = 0
			tn.Visible = true
			tn.ZIndex = 3
		end

		local ta = frame:FindFirstChild("toolAmount")
		if ta then
			local amt = nil
			if tool.GetAttribute then
				local okAttr, val = pcall(function() return tool:GetAttribute("amount") end)
				if okAttr then amt = val end
			end
			if amt then ta.Text = tostring(amt) else ta.Text = "" end
			ta.TextScaled = true
			ta.TextColor3 = DEFAULT_TEXT_COLOR
			pcall(function() ta.TextStrokeColor3 = DEFAULT_STROKE_COLOR end)
			pcall(function() ta.TextStrokeTransparency = 0 end)
			ta.TextTransparency = 0
			ta.Visible = true
			ta.ZIndex = 3
		end

		local ti = frame:FindFirstChild("toolImage")
		if ti then
			local img = ""
			if tool.GetAttribute then
				local okI, vI = pcall(function() return tool:GetAttribute("iconId") end)
				if okI and vI then img = vI end
			end
			if img == "" then
				local okT, tId = pcall(function() return tool.TextureId end)
				if okT and tId then img = tId end
			end
			ti.Image = img or ""
			ti.ImageTransparency = 0
			ti.Visible = true
			ti.ZIndex = 2
		end

		frame.BackgroundColor3 = DEFAULT_BG
		pcall(function() frame.BorderColor3 = DEFAULT_BORDER end)
	end)

	frame.Parent = container

	local obj = {
		Tool = tool,
		Frame = frame,
		Parent = parentKind or "Inventory",
		Position = position,
		Name = tool.Name,
		CONNECTIONS = {}
	}
	dprint("createToolFrame:", tool.Name, "->", container:GetFullName(), "frame:", frame.Name)
	return obj
end

-- API fallbacks
if type(inventoryHandler.removeCurrentDescription) ~= "function" then
	function inventoryHandler.removeCurrentDescription() end
end

if type(inventoryHandler.addTool) ~= "function" then
	function inventoryHandler.addTool(tool, parent, position)
		if not parent then parent = "Inventory" end

		if parent == "HotBar" then
			if position then
				local obj = createToolFrame(tool, "HotBar", position)
				inventoryHandler.OBJECTS.HotBar[position] = obj

				local conn = nil
				conn = tool.AncestryChanged:Connect(function(_, newParent)
					dprint("Tool AncestryChanged:", tool.Name, "->", tostring(newParent))
					local remove = false
					if not newParent then
						remove = true
					else
						local isBackpack = false
						if newParent == backpack then isBackpack = true end
						local isCharacter = false
						if player.Character then
							if newParent == player.Character then isCharacter = true end
						end
						if not isBackpack then
							if not isCharacter then
								remove = true
							end
						end
					end
					if remove then
						if obj.Frame and obj.Frame.Parent then obj.Frame:Destroy() end
						inventoryHandler.OBJECTS.HotBar[position] = nil
						pcall(function() tool:SetAttribute("toolAdded", false) end)
						safeDisconnect(conn)
					end
				end)

				obj.CONNECTIONS = obj.CONNECTIONS or {}
				obj.CONNECTIONS[1] = conn
				return
			end
		end

		-- inventory case
		local obj2 = createToolFrame(tool, "Inventory", nil)
		inventoryHandler.OBJECTS.Inventory[tool.Name] = obj2

		local conn2 = nil
		conn2 = tool.AncestryChanged:Connect(function(_, newParent)
			dprint("Tool AncestryChanged:", tool.Name, "->", tostring(newParent))
			local remove = false
			if not newParent then
				remove = true
			else
				local isBackpack2 = false
				if newParent == backpack then isBackpack2 = true end
				local isCharacter2 = false
				if player.Character then
					if newParent == player.Character then isCharacter2 = true end
				end
				if not isBackpack2 then
					if not isCharacter2 then
						remove = true
					end
				end
			end
			if remove then
				if obj2.Frame and obj2.Frame.Parent then obj2.Frame:Destroy() end
				inventoryHandler.OBJECTS.Inventory[tool.Name] = nil
				pcall(function() tool:SetAttribute("toolAdded", false) end)
				safeDisconnect(conn2)
			end
		end)

		obj2.CONNECTIONS = obj2.CONNECTIONS or {}
		obj2.CONNECTIONS[1] = conn2
	end
end

if type(inventoryHandler.newTool) ~= "function" then
	function inventoryHandler.newTool(tool)
		if not isToolSafe(tool) then return end

		local okAttr, added = pcall(function()
			if tool.GetAttribute then
				return tool:GetAttribute("toolAdded")
			end
			return false
		end)
		if okAttr and added then return end

		local filled = 0
		for k, v in pairs(inventoryHandler.OBJECTS.HotBar) do filled = filled + 1 end

		local parent = "Inventory"
		local position = nil
		if filled < inventoryHandler.slotAmount then
			for i = 1, inventoryHandler.slotAmount do
				if not inventoryHandler.OBJECTS.HotBar[i] then
					parent = "HotBar"
					position = i
					break
				end
			end
		end

		dprint("newTool:", tool.Name, "->", parent, "pos:", tostring(position))
		pcall(function() inventoryHandler.addTool(tool, parent, position) end)
		pcall(function() if tool.SetAttribute then tool:SetAttribute("toolAdded", true) end end)
	end
end

-- selection tracking
local selectedHotbarIndex = nil
_G.Client_BrainrotHelpers = _G.Client_BrainrotHelpers or {}
_G.Client_BrainrotHelpers.GetSelectedToolName = function()
	local idx = selectedHotbarIndex
	if not idx then return nil end
	local objs = inventoryHandler.OBJECTS
	if objs then
		local hb = objs.HotBar
		if hb then
			local entry = hb[idx]
			if entry then
				if entry.Tool then
					return entry.Tool.Name
				end
			end
		end
	end
	return nil
end

-- visual updates
local function updateSlotVisual(index)
	local frame = hotBar:FindFirstChild(index)
	if not frame then return end

	frame.BackgroundColor3 = DEFAULT_BG
	pcall(function() frame.BorderColor3 = DEFAULT_BORDER end)

	local isSelected = false
	if selectedHotbarIndex then
		if selectedHotbarIndex == index then isSelected = true end
	end
	if isSelected then
		frame.BackgroundColor3 = SELECT_BG
		pcall(function() frame.BorderColor3 = SELECT_BORDER end)
	end

	local toolObject = nil
	if inventoryHandler.OBJECTS then
		if inventoryHandler.OBJECTS.HotBar then
			toolObject = inventoryHandler.OBJECTS.HotBar[index]
		end
	end

	if toolObject then
		local tool = toolObject.Tool
		if tool then
			pcall(function()
				local tn = frame:FindFirstChild("toolName")
				if tn then tn.Text = tool.Name or "" end
				local ta = frame:FindFirstChild("toolAmount")
				if ta then
					local amt = nil
					if tool.GetAttribute then
						local okA, vA = pcall(function() return tool:GetAttribute("amount") end)
						if okA then amt = vA end
					end
					if amt then ta.Text = tostring(amt) else ta.Text = "" end
				end
				local ti = frame:FindFirstChild("toolImage")
				if ti then
					local img = ""
					if tool.GetAttribute then
						local okI, vI = pcall(function() return tool:GetAttribute("iconId") end)
						if okI and vI then img = vI end
					end
					if img == "" then
						local okT, tId = pcall(function() return tool.TextureId end)
						if okT and tId then img = tId end
					end
					ti.Image = img or ""
				end
			end)
			return
		end
	end

	-- clear visuals
	pcall(function()
		local tn = frame:FindFirstChild("toolName"); if tn then tn.Text = "" end
		local ta = frame:FindFirstChild("toolAmount"); if ta then ta.Text = "" end
		local ti = frame:FindFirstChild("toolImage"); if ti then ti.Image = "" end
	end)
end

local function showSlots()
	for i = 1, inventoryHandler.slotAmount do
		local frame = hotBar:FindFirstChild(i)
		if not frame then
			local okC, clone = pcall(function() return toolButton:Clone() end)
			if okC and clone then clone.Name = i; clone.Parent = hotBar end
			frame = hotBar:FindFirstChild(i)
		end
		updateSlotVisual(i)
	end
end

-- handle backpack events
local function handleNewToolCandidate(candidate)
	dprint("backpack.ChildAdded for:", tostring(candidate and candidate.Name), "class:", typeof(candidate))
	local tool = candidate
	if not isToolSafe(tool) then
		local nm = nil
		pcall(function() nm = candidate and candidate.Name end)
		if nm then
			local resolved = findToolInBackpackByName(nm)
			if resolved then tool = resolved; dprint("Resolved to tool:", tool.Name) end
		end
	end
	if isToolSafe(tool) then
		dprint("Adding tool to UI:", tool.Name)
		pcall(function() inventoryHandler.newTool(tool) end)
		showSlots()
	else
		dprint("Candidate not a Tool:", tostring(candidate))
	end
end

backpack.ChildAdded:Connect(handleNewToolCandidate)
backpack.ChildRemoved:Connect(function() dprint("backpack.ChildRemoved"); showSlots() end)

-- initial populate
dprint("Initial backpack contents:")
local bkids = backpack:GetChildren()
for i = 1, #bkids do
	dprint(" -", bkids[i].Name, "class:", bkids[i].ClassName)
	handleNewToolCandidate(bkids[i])
end
showSlots()

-- key mapping
local keyToIndex = {
	[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4, [Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8, [Enum.KeyCode.Nine] = 9,
}

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

	local idx = keyToIndex[input.KeyCode]
	if idx then
		if selectedHotbarIndex == idx then
			selectedHotbarIndex = idx
			dprint("Pressed key for selected slot -> place", idx)
			showSlots()
			pcall(function()
				if _G.Client_BrainrotHelpers and type(_G.Client_BrainrotHelpers.RequestPlace) == "function" then
					_G.Client_BrainrotHelpers.RequestPlace()
				end
			end)
		else
			selectedHotbarIndex = idx
			dprint("Selected hotbar index:", idx)
			showSlots()
			local equipReq = ReplicatedStorage:FindFirstChild("EquipRequest")
			if equipReq then pcall(function() equipReq:FireServer(idx) end) end
			local obj = nil
			if inventoryHandler.OBJECTS then
				if inventoryHandler.OBJECTS.HotBar then
					obj = inventoryHandler.OBJECTS.HotBar[idx]
				end
			end
			if obj then
				if obj.Tool then
					local humanoid = nil
					if player.Character then humanoid = player.Character:FindFirstChildWhichIsA("Humanoid") end
					if humanoid then pcall(function() humanoid:EquipTool(obj.Tool) end) end
				end
			end
		end
		return
	end

	if input.KeyCode == Enum.KeyCode.Quote then
		inventoryHandler.removeCurrentDescription()
		Inventory.Visible = not Inventory.Visible
		if Inventory.Visible then
			showSlots()
			local container = Inventory:FindFirstChild("Frame")
			if not container then container = Inventory end
			for i = 1, inventoryHandler.inventoryCapacity do
				local name = "InvSlot" .. tostring(i)
				if not container:FindFirstChild(name) then
					local okC, clone = pcall(function() return toolButton:Clone() end)
					if okC and clone then clone.Name = name; clone.Parent = container end
				end
			end
		end
	end
end)

local openBtn = GuiRoot:FindFirstChild("openButton")
if openBtn and openBtn:IsA("GuiObject") then
	openBtn.MouseButton1Click:Connect(function()
		inventoryHandler.removeCurrentDescription()
		Inventory.Visible = not Inventory.Visible
		if Inventory.Visible then showSlots() end
	end)
end

dprint("InventoryController loaded (AND-free)")
