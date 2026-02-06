local Players = game:GetService("Players")

local TICK = 2 -- alle 2 Sekunden aktualisieren

local function sumIncomeForPlot(plot, ownerName)
	if not plot then return 0 end
	local brainrotsFolder = workspace:FindFirstChild("Brainrots")
	if not brainrotsFolder then return 0 end
	local total = 0
	for _, obj in ipairs(brainrotsFolder:GetChildren()) do
		if obj:IsA("Model") then
			local stored = obj:FindFirstChild("StoredInSlot")
			local owner = obj:FindFirstChild("Owner")
			local inc = obj:FindFirstChild("IncomePerSec")
			if stored and stored.Value ~= "" and owner and owner.Value == ownerName and inc then
				total += tonumber(inc.Value) or 0
			end
		end
	end
	return total
end

while true do
	local plots = workspace:FindFirstChild("Plots")
	if plots then
		for _, plot in ipairs(plots:GetChildren()) do
			if plot:IsA("Model") or plot:IsA("Folder") then
				local ownerName = plot:GetAttribute("Owner")
				if ownerName then
					local income = sumIncomeForPlot(plot, ownerName)
					plot:SetAttribute("IncomePerSec", income)
					local pl = Players:FindFirstChild(ownerName)
					if pl then pl:SetAttribute("IncomePerSec", income) end
				end
			end
		end
	end
	task.wait(TICK)
end
