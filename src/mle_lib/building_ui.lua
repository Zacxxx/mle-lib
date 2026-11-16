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
    local mounted = {}
    local function unmount(key)
        local previous = mounted[key]
        mounted[key] = nil
        if previous then previous.cleanup() end
    end
    local function refresh_panels(screens)
        local visible = {}
        if not api.panels then return end
        for _, screen in ipairs(screens) do
            if valid(screen) and screen:IsVisible() and valid(screen.building) then
                local key, id = screen:GetAddress(), screen.building:GetType()
                if api.panels.panel_mounts(id) then
                    local instance = api.panels.instance_for(screen.building)
                    if instance then
                        visible[key] = true
                        if mounted[key] and mounted[key].instance ~= instance then unmount(key) end
                        if not mounted[key] then
                            mounted[key] = {instance = instance, cleanup = api.panels.mount_panel(id, screen, instance)}
                        end
                    end
                end
            end
        end
        for key in pairs(mounted) do if not visible[key] then unmount(key) end end
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
        local screens = api.find_all("Inventory_C") or {}
        for _, screen in ipairs(screens) do
            if valid(screen) and valid(screen.building) then
                local definition = definitions[screen.building:GetType()]
                if definition then assign(screen.buildingImage, definition.panel) end
            end
        end
        refresh_panels(screens)
    end
    function self.role(widget, definitions)
        if not valid(widget) or not valid(widget.building) or not valid(widget.JobText) then return end
        local definition = definitions[widget.building:GetType()]
        if definition and definition.worker_role then
            local label = api.translate and api.translate("MLE_Worker_" .. widget.building:GetType()) or definition.worker_role.en_US
            widget.JobText:SetText(api.make_text(label))
        end
    end
    function self.upgrade(widget, definitions)
        if not valid(widget) or not valid(widget.relevantBuilding) then return end
        local definition = definitions[widget.relevantBuilding:GetType()]
        if not definition or widget.ID ~= definition.upgrade_id then return end
        if valid(widget.name_txt) and definition.upgrade_name then
            local label = api.translate and api.translate("MLE_upgrade_name_" .. widget.relevantBuilding:GetType()) or definition.upgrade_name.en_US
            widget.name_txt:SetText(api.make_text(label))
        end
        if valid(widget.descr_RichTxt) and definition.upgrade_description then
            local label = api.translate and api.translate("MLE_upgrade_description_" .. widget.relevantBuilding:GetType()) or definition.upgrade_description.en_US
            widget.descr_RichTxt:SetText(api.make_text(label))
        end
    end
    function self.inventory(screen, definition)
        if valid(screen) and definition then assign(screen.buildingImage, definition.panel) end
    end
    local running, generation, removers = false, 0, {}
    function self.start(definitions)
        assert(not running, "Building UI lifecycle already running")
        assert(api.schedule and api.hooks and api.find_object, "Building UI lifecycle services missing")
        running, generation = true, generation + 1
        local current = generation
        local function protected(callback)
            if not running or current ~= generation then return end
            local ok, reason = pcall(callback)
            if not ok and api.log then api.log(tostring(reason)) end
        end
        local function panel(context)
            local screen = context:get()
            api.schedule(0, function()
                protected(function()
                    if valid(screen) and valid(screen.building) then
                        self.inventory(screen, definitions()[screen.building:GetType()])
                    end
                end)
            end)
        end
        for _, path in ipairs({"/Script/ManorLords.MLInventoryScreen:UpdateInventory",
            "/Game/ManorLords/UI/Widgets/Widgets_Inventory/Inventory.Inventory_C:InitFromBuilding",
            "/Game/ManorLords/UI/Widgets/Widgets_Inventory/Inventory.Inventory_C:OnLoaded_B172AFCD4C155EDA3CCC20B65E555612"}) do
            if valid(api.find_object(path)) then removers[#removers + 1] = api.hooks.add(path, panel) end
        end
        for path, method in pairs({
            ["/Game/UI/Inventory/Lists/FamilyEntry.FamilyEntry_C:Update"] = self.role,
            ["/Game/UI/Tooltips/BigTooltipUpgrade.BigTooltipUpgrade_C:UpdateWithBuilding"] = self.upgrade,
        }) do
            if api.make_text and valid(api.find_object(path)) then
                removers[#removers + 1] = api.hooks.add(path, function(context)
                    local widget = context:get()
                    api.schedule(0, function() protected(function() method(widget, definitions()) end) end)
                end)
            end
        end
        local function poll()
            protected(function()
                local entries = definitions()
                self.refresh(entries)
                if api.make_text then
                    for _, widget in ipairs(api.find_all("FamilyEntry_C") or {}) do self.role(widget, entries) end
                end
            end)
            if running and current == generation then api.schedule(250, poll) end
        end
        api.schedule(0, poll)
    end
    function self.stop()
        running, generation = false, generation + 1
        for _, remove in ipairs(removers) do remove() end
        removers = {}
        for key in pairs(mounted) do unmount(key) end
    end
    return self
end
return UI
