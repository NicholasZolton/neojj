# Changelog

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 1.1.1 (2026-06-10)

**Full Changelog**: https://github.com/NicholasZolton/neojj/compare/v1.1.0...v1.1.1

## [1.1.0](https://github.com/NicholasZolton/neojj/compare/v1.0.0...v1.1.0) (2026-06-10)


### Features

* add neojj.version module ([1417897](https://github.com/NicholasZolton/neojj/commit/14178977b5e15dd6b885e6c23275d03d30ae0b7f))

## [1.0.0] - 2026-06-09

First release under stable semantic versioning. Introduces the new keybinding
convention: lowercase keys open popups; capital letters act on the item under
the cursor.

### Breaking
- The Squash, Workspace, Push, and Remote popups moved from `S`/`W`/`P`/`M` to
  `s`/`w`/`p`/`m`.
- Removed the `A` (abandon current change) and `N` (new change) bindings.

### Added
- `x` abandons the change under the cursor in the status and log views (variant
  rows by commit id, divergent parents warn, normal changes by change id with
  confirmation).
- `c a` abandons a change via the picker; `c n` / `O` / `B` create new changes.

### Migration
- Replace `S`/`W`/`P`/`M` with `s`/`w`/`p`/`m`.
- Replace `A` with `x` (under cursor) or `c a` (picker); replace `N` with
  `c n` / `O` / `B`.
- Custom `mappings.popup` configs are unaffected.

## [0.3.0] - 2026-06-09

Baseline release prior to the keybinding convention change. Uses the legacy
uppercase popup bindings (`S`/`W`/`P`/`M`) and the `A`/`N` bindings.

### Added
- `dt` ("diff trunk") command in the diff popup, showing the range from
  `trunk()` to the working copy (`@`).

[1.0.0]: https://github.com/NicholasZolton/neojj/compare/v0.3.0...v1.0.0
[0.3.0]: https://github.com/NicholasZolton/neojj/releases/tag/v0.3.0
