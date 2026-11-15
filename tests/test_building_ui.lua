local UI = require("mle_lib.building_ui")
local function valid() return true end
local function image()
    return {IsValid = valid, SetBrushFromTexture = function(self, texture) self.value = texture.path end}
end
local custom, vanilla = {IsValid = valid, GetBuildingType = function() return 600 end, Icon = image()},
    {IsValid = valid, GetBuildingType = function() return 72 end, Icon = image()}
local tip = {IsValid = valid, buildingID = 600, Thumbnail = image()}
local screen = {IsValid = valid, buildingImage = image()}
local ui = UI.new({find_all = function(kind)
    if kind == "W_HUD_BuildingCardV2_C" then return {custom, vanilla} end
    return {tip}
end, texture = function(path) return {IsValid = valid, path = path} end})
ui.refresh({[600] = {card = "house_card", panel = "house_panel"}})
assert(custom.Icon.value == "house_card" and vanilla.Icon.value == nil and tip.Thumbnail.value == "house_panel")
ui.inventory(screen, {panel = "house_panel"}); assert(screen.buildingImage.value == "house_panel")
print("PASS: registered building presentation updates preserve vanilla cards")
