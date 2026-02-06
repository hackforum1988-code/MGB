-- Sucht in jedem Plot die SurfaceGui/TextLabel "SIGN", ankert das Schild und aktualisiert den Text.

local function findSignLabel(plot)
	for _, desc in ipairs(plot:GetDescendants()) do
		if desc:IsA("SurfaceGui") then
			local lbl = desc:FindFirstChild("SIGN")
			if lbl and lbl:IsA("TextLabel") then
				return lbl
			end
		end
	end
	return nil
end

local function anchorSignFromLabel(lbl)
	if not lbl then return end
	-- Versuche das übergeordnete Model (Schild) zu finden
	local signModel = lbl:FindFirstAncestorOfClass("Model")
	local function anchorParts(root)
		if not root then return end
		for _, p in ipairs(root:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = true
				p.CanCollide = true
			end
		end
	end
	if signModel then
		anchorParts(signModel)
	else
		-- Fallback: direkt den Part, an dem die SurfaceGui hängt
		local part = lbl.Parent and lbl.Parent:IsA("SurfaceGui") and lbl.Parent.Adornee
			or lbl:FindFirstAncestorWhichIsA("BasePart")
		if part then
			part.Anchored = true
			part.CanCollide = true
		end
	end
end

local function updateSign(plot, label)
	if not (plot and label) then return end
	local owner = plot:GetAttribute("Owner")
	if owner and owner ~= "" then
		label.Text = "Owner: " .. owner
		label.TextColor3 = Color3.fromRGB(180, 255, 180)
	else
		label.Text = "Frei"
		label.TextColor3 = Color3.fromRGB(255, 200, 200)
	end
end

local function setupPlot(plot)
	local lbl = findSignLabel(plot)
	if not lbl then return end
	anchorSignFromLabel(lbl)
	updateSign(plot, lbl)
	plot:GetAttributeChangedSignal("Owner"):Connect(function()
		updateSign(plot, lbl)
	end)
end

local plots = workspace:FindFirstChild("Plots")
if plots then
	for _, plot in ipairs(plots:GetChildren()) do
		setupPlot(plot)
	end
	plots.ChildAdded:Connect(function(child)
		task.wait(0.1)
		setupPlot(child)
	end)
end
