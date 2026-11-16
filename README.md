# MLE Lib

Shared Lua modding services for Manor Lords. This repository is independent of the ML Expanded game content projects.

The library covers the package host, reflected hook broker, pre-world registration and patch transactions, UE asset loading, diagnostics, and storage primitives. The supported development profile targets Manor Lords 0.8.117 and the pinned UE4SS build.

```sh
python3 scripts/mle.py doctor
python3 scripts/mle.py validate examples
python3 scripts/mle.py test
```

Ruralities pins a Git commit and includes the matching SDK modules in its bundle. Its UE4SS entry point creates one host for its packages. Building consumers can use a common shared_directory for native dispatch and identity allocation. Lua callbacks remain in each consumer VM. The supported native capability profile is documented with the building API.

See [the delivery plan](docs/PLAN.md), [registry API](docs/registry.md), and [save companions](docs/sidecar.md). The planned R1 and R2 live acceptance evidence is tracked separately from the offline test results.

The [building registration API](docs/buildings.md) includes the native adapter, building IDs, construction and preview bindings, upgrade dispatch, localization and UI lifecycle. Ruralities consumes the same pinned implementation. Offline tests and native bridge compilation pass; loaded-game acceptance is tracked separately.

## License

MLE Lib is distributed under the [MIT License](LICENSE).
