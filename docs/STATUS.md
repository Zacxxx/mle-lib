# MMF-SRS-001 implementation status

| Requirements | Current evidence | Remaining work |
| --- | --- | --- |
| FR-BOOT-03/04/05/07 | Host and CLI tests cover deterministic order, package disablement, compatibility, dry runs, and rollback | Certify process-wide shared host and full game lifecycle, FR-BOOT-01/02/06 |
| FR-REG-01 to 06 | Registry tests cover owner and schema, baseline recomputation, conflicts, freeze, and rollback | Certify reflected adapters and saved identities in a world |
| FR-HOOK-01/02/05 | Within one host, a reflected target can share one physical registration across listeners | Native ABI resolution and host-wide constraints, timing, and teardown evidence |
| FR-ASSET-01/02/03 | Pak hash validation, owned Unreal path resolver and Ruralities artwork adapter | Live owned assets, visual checks, and save/reload |
| FR-SAVE-01 to 04 | Sidecar unit coverage for identity, checksum, atomic publish, recovery, and migrations | Correlate to game save completion and migrate existing sidecar users |
| FR-TOOL and FR-DOC | CLI, CI, SDK examples and adapter docs | Full onboarding and operations acceptance |
| FR-CONT | Ruralities exercises the building, upgrade and recipe adapters | G3 building and item gameplay acceptance. Generic new entities are deferred |
| FR-OBS | Local logs, package order and error details | Full support bundle and performance/usage evidence |
