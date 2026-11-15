-- Shared presentation of registered building cards, hover tips and inventories.
local UI = {}
local function valid(value) return value and value:IsValid() end
function UI.new(api)
    assert(type(api.find_all) == "function" and type(api.texture) == "function", "Building UI requires widget lookup and texture loading")
    local self = {}
    local function assign(widget, reference)
        if reference and valid(widget) then
            local image = api.texture(reference)
            if valid(image) then widget:SetBrushFromTexture(image, false) end
        end
    end
    function self.refresh(definitions)
        for _, card in ipairs(api.find_all("W_HUD_BuildingCardV2_C") or {}) do
            if valid(card) then
                local definition = definitions[card:GetBuildingType()]
                if definition then assign(card.Icon, definition.card) end
            end
        end
        for _, tip in ipairs(api.find_all("BigBuildingTooltip_C") or {}) do
            if valid(tip) then
                local definition = definitions[tip.buildingID]
                if definition then assign(tip.Thumbnail, definition.panel or definition.card) end
            end
        end
    end
    function self.inventory(screen, definition)
        if valid(screen) and definition then assign(screen.buildingImage, definition.panel) end
    end
    return self
end
return UI
