# MMF-SRS-001 implementation status

| Requirements | Current evidence | Remaining work |
| --- | --- | --- |
| FR-BOOT-03/04/05/07 | Host and CLI tests cover deterministic order, package disablement, compatibility, dry runs, and rollback | Standalone host loads separately packaged mods in one VM. Exact game and UE4SS binary hashes gate startup. Certify live activation and restart |
| FR-REG-01 to 06 | Registry tests cover owner and schema, baseline recomputation, conflicts, freeze, and rollback | Certify reflected adapters and saved identities in a world |
| FR-HOOK-01/02/05 | Within one host, a reflected target can share one physical registration across listeners | Native ABI resolution and host-wide constraints, timing, and teardown evidence |
| FR-ASSET-01/02/03 | Pak hash validation, owned Unreal path resolver and Ruralities artwork adapter | Live owned assets, visual checks, and save/reload |
| FR-SAVE-01 to 04 | Sidecar unit coverage for identity, checksum, atomic publish, recovery, and migrations | Shared reflected adapter stages metadata in saved building tags. Certify durable save/reload and define an empty-settlement fallback bound to a confirmed save identity |
| FR-TOOL and FR-DOC | CLI, CI, SDK examples and adapter docs | Full onboarding and operations acceptance |
| FR-CONT | Ruralities exercises the building and upgrade adapters. Native item and recipe rows have offline tests | Shared item allocation, G3 building and item gameplay acceptance, and generic new entities |
| FR-OBS | Local logs, package order and error details | Full support bundle and performance/usage evidence |

## R1 acceptance still pending

The runtime and two separate package installs were prepared in Candidate 34
with MLE Lib 0.1.7. The offline integration fixture covers one registry,
one hook registration per target, state reload, and package disablement.
The live check must cover activation, construction and staffing, durable
save/reload across a full process restart, independent package disablement,
and saving after demolition. MLE Witness is a diagnostic package. The audit's
two gameplay package proof remains open. Mutation hooks and generic native
detours remain outside R1's reflected observer contract.
