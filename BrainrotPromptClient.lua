local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local pickupRemote = ReplicatedStorage:WaitForChild("BrainrotPickup")
local localPlayer = Players.LocalPlayer

ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
	if player ~= localPlayer then return end
	if not prompt or not prompt:IsDescendantOf(workspace) then return end

	local model = prompt.Parent
	if model and model:IsA("BasePart") then
		model = model.Parent
	end
	local modelName = prompt:GetAttribute("ModelName") or (model and model.Name)

	-- Sende sowohl die Prompt-Instanz als auch den Modelnamen (Fallback)
	pcall(function()
		pickupRemote:FireServer(prompt, modelName)
	end)
end)
