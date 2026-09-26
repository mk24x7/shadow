## Summary

<!-- What does this change and why? Link any related issue. -->

## Testing

<!-- How did you test it? Paste the relevant `shadow` output with private paths removed. -->

## Checklist

- [ ] `swift build` and `swift test` pass
- [ ] New detection rules or findings have a test on a fake PATH tree
- [ ] `scripts/check-ascii.sh` passes
- [ ] Shadow still never writes to rc files, PATH or anything outside its own output
- [ ] `CHANGELOG.md` has a line under `## [Unreleased]`
