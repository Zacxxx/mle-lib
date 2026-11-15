# Save companions

`mle_lib.sidecar` records package state outside the game save. The game adapter supplies the verified save identity and reports when the matching game save completes. Use one store per companion directory.

```lua
local Sidecar = require("mle_lib.sidecar")
local store = Sidecar.new({fs = filesystem, encode = codec.encode, decode = codec.decode, checksum = sha256})
local identity = {namespace = "example.seasons", save_id = "village-a", fingerprint = observed_fingerprint}
local ticket = store:prepare("example.seasons.village-a", identity, 1, {year = 2})
-- When the game adapter observes the committed save:
store:commit(ticket, observed_identity)
```

The filesystem adapter receives relative companion names and must confine them to a directory separate from the original game saves. `read(name)` returns bytes or nil for a missing file. `write(name, bytes)` must flush data before returning true, and `rename(from, to)` must atomically replace its destination on the same filesystem and persist the directory entry before returning true. `remove(name)` returns true after removing a prepared file. The codec must decode data without executing it. The checksum covers the encoded payload, including namespace, save identity and schema.

`prepare` writes and verifies the pending snapshot. `commit` checks the observed identity, keeps a verified copy of the previous companion and publishes the prepared snapshot. `discard` clears a cancelled save. `save(path, identity, schema, data)` combines prepare and commit for a save whose completion the adapter has already verified.

`load(path, identity, schema, migrations)` returns data and a status record. It validates the checksum and fingerprint of the primary snapshot, then checks the last good copy when needed. A prepared snapshot is never restored automatically. The returned status identifies interrupted commits and mismatches so callers can surface recovery information. Missing migration steps and newer schemas return a status without applying state.

Pass migration functions keyed by their source schema. The store runs them once per step on the decoded data and leaves files unchanged until the caller explicitly commits the migrated state. Manifests and package availability should be validated before constructing the save identity or restoring package state.

`lua tests/test_sidecar.lua` checks an interrupted commit, wrong fingerprints, corrupt state, migration and backup recovery with an injected filesystem. The game adapter still needs to correlate Manor Lords save completion with the prepared fingerprint.
