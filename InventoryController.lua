local InventoryController = {}  

-- Store the local player and humanoid  
local player = game.Players.LocalPlayer  
local humanoid  

-- Function to equip the tool locally  
local function equipToolLocal(index)  
    local tool = inventoryHandler.OBJECTS.HotBar[index].Tool  
    if tool and humanoid then  
        humanoid:EquipTool(tool)  
    end  
end  

-- Function to handle character change  
local function onCharacterAdded(character)  
    humanoid = character:WaitForChild("Humanoid")  
end  

-- Connect character added event  
player.CharacterAdded:Connect(onCharacterAdded)  

-- Function to handle hotbar key  
function handleHotbarKey(index)  
    -- Fire EquipRequest for server-side equipping  
    -- Existing functionality retained...
    equipToolLocal(index)  
end

return InventoryController