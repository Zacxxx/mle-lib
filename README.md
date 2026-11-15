# MLE Lib

Shared Lua modding services for Manor Lords. This repository is independent of the ML Expanded game content projects.

This first release covers the package host, reflected hook broker, pre-world registration and patch transactions, UE asset loading, diagnostics, and storage primitives. The supported development profile targets Manor Lords 0.8.117 and the pinned UE4SS build.

```sh
python3 scripts/mle.py doctor
python3 scripts/mle.py validate examples
python3 scripts/mle.py test
```

Ruralities pins a Git commit and includes the matching SDK modules in its bundle. Its UE4SS entry point creates one host for its packages. Shared native state across separate UE4SS Lua VMs and the full native capability matrix are future work.

See [the delivery plan](docs/PLAN.md), [registry API](docs/registry.md), and [save companions](docs/sidecar.md). The planned R1 and R2 live acceptance evidence is tracked separately from the offline test results.

The [building registration API](docs/buildings.md) now provides definition validation and atomic adapter orchestration. Native building adapter extraction and Ruralities migration remain in progress.
