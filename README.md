# MLE Lib

Shared Lua modding services for Manor Lords. This repository is independent of the ML Expanded game content projects.

The library covers the package host, reflected hook broker, pre-world registration and patch transactions, UE asset loading, diagnostics, and storage primitives. The supported development profile targets Manor Lords 0.8.117 and the pinned UE4SS build.

```sh
python3 scripts/mle.py doctor
python3 scripts/mle.py validate examples
python3 scripts/mle.py test
```

The separately installed [shared runtime](docs/shared-runtime.md) loads Ruralities and other content packages into one UE4SS Lua VM. It coordinates registry patches, reflected hook subscriptions and save providers. Ruralities pins the runtime version in its package manifest and installer receipt.

See [the delivery plan](docs/PLAN.md), [registry API](docs/registry.md), and [save companions](docs/sidecar.md). The planned R1 and R2 live acceptance evidence is tracked separately from the offline test results.

The [building registration API](docs/buildings.md) includes the native adapter, building IDs, construction and preview bindings, upgrade dispatch, localization and UI lifecycle. Ruralities consumes the same pinned implementation. Offline tests and native bridge compilation pass; loaded-game acceptance is tracked separately.

## License

MLE Lib is distributed under the [MIT License](LICENSE).

The [item and recipe API](docs/items.md) registers native rows, resolves recipe inputs and outputs and shares the library's row transaction.
