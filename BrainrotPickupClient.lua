-- ... (bestehender Inhalt bleibt) ...

local ProximityPromptService = game:GetService("ProximityPromptService")

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

ProximityPromptService.PromptTriggered:Connect(function(prompt, plr)
	if plr ~= player then return end
	if not prompt or not prompt:IsDescendantOf(workspace) then return end

	-- Slot-Prompt: Attr IsSlotPrompt oder Name beginnt mit "Slot" oder Parent-Name beginnt mit "Slot"
	local isSlot = prompt:GetAttribute("IsSlotPrompt") or prompt.Name == "SlotPlace" or (prompt.Parent and tostring(prompt.Parent.Name):match("^Slot"))
	if not isSlot then return end

	local equippedName = getEquippedToolName()
	if not equippedName then
		showToast("Kein Item ausgerüstet zum Platzieren.")
		return
	end

	local slotInstance = prompt.Parent  -- BasePart des Slots
	placeRemote:FireServer(slotInstance)
end)

print("✅ BrainrotPickupClient ready (robust handlers + SlotPromptListener)")
