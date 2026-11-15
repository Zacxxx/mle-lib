# MLE Lib delivery plan

1. Establish a private, independent GitHub repository and a reproducible offline test suite.
2. Build the versioned Lua package host with capability and dependency validation, ordered lifecycle and events, and shared registration services. Keep the API independent of Ruralities.
3. Move reusable game adapters into the dependency and pin the library commit in the Ruralities bundle. Keep game content and rules in Ruralities packages.
4. Integrate and exercise independent package switches before world initialization. Keep persisted content identities available for existing saves. Report dependency failures before activation.
5. Run offline acceptance against the exact game profile. Track loaded-world construction, upgrade, UI, and save validation separately from offline results.

The specification's R1 acceptance and R2 capability gates require evidence from a loaded game. Track native hook composition, sidecars, SDK tooling, and broader content adapters by their specification requirement IDs. Publish no game assets or internal specification.
