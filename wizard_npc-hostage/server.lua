local expectedResourceName = "wizard_npc-hostage"
local currentResourceName = GetCurrentResourceName()
if currentResourceName ~= expectedResourceName then
print("^1Resource renamed! Change it as it was! |wizard_npc-hostage|^0")
return
end
