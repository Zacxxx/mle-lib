local Rows = require("mle_lib.rows")
local storage = {vanilla = true}
local data = {
    FindRow = function(_, id) return storage[id] end,
    AddRow = function(_, id, row) storage[id] = row end,
    RemoveRow = function(_, id) storage[id] = nil end,
}
local ok = pcall(Rows.run, function(tx)
    local table = tx.table(data)
    assert(tx.table(table) == table, "Wrapping a transaction table twice must reuse the existing journal")
    table:AddRow("barn", true)
    tx.table(data):AddRow("part", true)
    error("native binding refused")
end)
assert(not ok and storage.vanilla and not storage.barn and not storage.part)
Rows.run(function(tx) tx.table(data):AddRow("barn", true) end)
assert(storage.barn)
print("PASS transaction rollback and successful commit")
