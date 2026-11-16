local Runtime = require("mle_lib.runtime")
local Codec = require("mle_lib.state_codec")
local Catalog = require("mle_lib.catalog")
local Path = "/Script/ManorLords.PawnCPP:requestSaveFile"
local Save = "/Script/ManorLords.IoHandler:SaveGameToSlot"
local Load = "/Script/ManorLords.IoHandler:LoadGameFromSlot"

local function boot(catalog)
    local calls, failures = {}, {}
    local capacity = 50
    local runtime = Runtime.new({
        registry = {
            fields = {buildings = {capacity = "integer"}},
            read = function() return capacity end,
            write = function(_, _, value) capacity = value end,
        },
        register_hook = function(path, before, after)
            assert(not calls[path], "Native hook registered twice")
            calls[path] = {before, after}
        end,
        is_save = function(object) return object ~= nil end,
        make_name = function(value) return value end,
        report = function(failure) failures[#failures + 1] = failure end,
    })
    Catalog.load(assert(arg[1]), catalog, runtime)
    assert(runtime:start())
    assert(runtime:bind_save())
    runtime:apply_registry()
    return runtime, calls, failures, capacity
end

if not arg[1] then return end
local function marshal(value)
    if type(value) == "table" then
        for _, entry in ipairs(value.savedBuildings) do
            entry.buildingTags.Empty = function(self)
                for index = #self, 1, -1 do self[index] = nil end
            end
        end
        return {get = function() return value end}
    end
    return {get = function() return nil end}
end

local both = "First\nSecond\n"
local runtime, hooks, failures, capacity = boot(both)
assert(capacity == 57 and #runtime:inspect().registry.definitions == 2)
assert(hooks[Path][1]() == nil and hooks[Path][1]() == nil)
local object = {daysTotal = 5, LevelName = "Fixture", savedBuildings = {{buildingTags = {"native-tag"}}}}
hooks[Save][1](nil, marshal(object))
assert(runtime:inspect().save.wrote == 1 and #failures == 0)
assert(object.savedBuildings[1].buildingTags[1] == "native-tag")
object.savedBuildings[1].buildingTags.Empty = nil
local persisted = assert(io.open(arg[1] .. "/fixture.sav", "wb"))
local tags = {}
for index, tag in ipairs(object.savedBuildings[1].buildingTags) do tags[tostring(index)] = tag end
assert(persisted:write(Codec.encode({day = object.daysTotal, level = object.LevelName, tags = tags})))
assert(persisted:close())
assert(runtime:stop())
assert(hooks[Path][1]() == nil)

persisted = assert(io.open(arg[1] .. "/fixture.sav", "rb"))
local disk = Codec.decode(assert(persisted:read("*a")))
local reloaded = {daysTotal = disk.day, LevelName = disk.level, savedBuildings = {{buildingTags = {}}}}
for index, tag in pairs(disk.tags) do reloaded.savedBuildings[1].buildingTags[tonumber(index)] = tag end
assert(persisted:close())
runtime, hooks, failures, capacity = boot(both)
hooks[Load][2](nil, marshal(reloaded))
assert(runtime:inspect().save.loaded == 1 and #failures == 0)
assert(_G.shared_fixture.first == 2 and _G.shared_fixture.second == 20)
assert(runtime:stop())

runtime, hooks, failures, capacity = boot("# First disabled\nSecond\n")
assert(capacity == 55 and #runtime:inspect().registry.definitions == 1)
hooks[Load][2](nil, marshal(reloaded))
assert(_G.shared_fixture.second == 20 and #failures == 0)
reloaded.daysTotal = 6
hooks[Save][1](nil, marshal(reloaded))
runtime, hooks, failures = boot(both)
hooks[Load][2](nil, marshal(reloaded))
assert(_G.shared_fixture.first == 2 and _G.shared_fixture.second == 20 and #failures == 0)
reloaded.LevelName = "Another world"
hooks[Load][2](nil, marshal(reloaded))
assert(_G.shared_fixture.first == nil and _G.shared_fixture.second == nil)
assert(runtime:inspect().save.blocked and #failures == 1)

runtime, hooks, failures = boot(both)
local empty = {daysTotal = 1, LevelName = "Empty", savedBuildings = {}}
hooks[Load][2](nil, marshal(empty))
assert(runtime:inspect().save.loaded == 0 and runtime:inspect().save.missing_loads == 1)
local empty_object = marshal(empty)
hooks[Save][1](nil, empty_object)
hooks[Save][2](nil, {get = function() return true end}, empty_object)
assert(runtime:inspect().save.game_saves_accepted == 1)
hooks[Save][2](nil, {get = function() return false end}, empty_object)
assert(runtime:inspect().save.game_saves_rejected == 1)
assert(runtime:inspect().save.wrote == 0 and runtime:inspect().save.failed == 1)
assert(#failures == 1)
