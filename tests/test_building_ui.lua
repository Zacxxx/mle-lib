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
local queue, callbacks, removed = {}, {}, 0
local lifecycle = UI.new({find_all = function() return {} end, texture = function(path) return {IsValid = valid, path = path} end,
    find_object = function() return {IsValid = valid} end,
    schedule = function(_, callback) queue[#queue + 1] = callback end,
    hooks = {add = function(path, callback)
        callbacks[path] = callback
        return function() callbacks[path] = nil; removed = removed + 1 end
    end}})
lifecycle.start(function() return {[600] = {panel = "lifecycle_panel"}} end)
screen.building = {IsValid = valid, GetType = function() return 600 end}
callbacks["/Script/ManorLords.MLInventoryScreen:UpdateInventory"]({get = function() return screen end})
queue[#queue]()
assert(screen.buildingImage.value == "lifecycle_panel")
lifecycle.stop()
local count = #queue
for _, callback in ipairs(queue) do callback() end
assert(#queue == count and removed == 3 and next(callbacks) == nil)
print("PASS: native building UI deferred inventory lifecycle and callback cleanup")
