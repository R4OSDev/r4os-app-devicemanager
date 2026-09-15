# DEVMGR.R4X

`DEVMGR.R4X` is an independent R4OS application implemented in Zig.

## Package

- Version: `0.1.4`
- Image target: `/R4OS/SOFTWARE/DESKTOP/DEVMGR.R4X`
- Image scope: `full`
- Canonical project manifest: `module.R4MF`

The manifest is the single source of truth for the artifact, imports, image
target, and package metadata.

## Build

On Windows:

    Build.bat

On Linux:

    ./Build.sh

The build starters resolve the current local R4OS dependency checkouts through
`Settings.R4S`. The URL and hash entries in `build.zig.zon` record the
last verified standalone dependency identities; workspace builds use the
mapped local checkouts.

## GPU telemetry

Selecting a graphics device refreshes its power policy, target clocks,
temperatures, power limit and utilization once per second. Unsupported or
stale values remain explicitly unknown. Console output and the export to
`C:\Temp\HWREPORT.TXT` use the same data, including the GPU global timer.
Firmware targets are distinct from measured effective clocks; timer deltas
are sampling intervals. Collection does not generate graphics workloads.

## Documentation

Detailed German technical notes from the migration are preserved in
`DOCUMENTATION.de.txt`. Source-transfer provenance is recorded in
`PROVENANCE.txt`.

## License

Original R4OS material is licensed under Apache License 2.0. See `LICENSE`
and `NOTICE`. Any repository-specific external material is documented in
`THIRD_PARTY_NOTICES.md`.
