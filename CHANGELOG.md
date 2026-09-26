# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- First release: the `shadow` CLI and the Shadow macOS app.
- Resolves 28 default tools (node, python, ruby, java, go, rust, swift, php, git and more) in
  zsh, bash, sh and fish login and interactive shells, the current environment and the GUI app
  environment, and lists every copy each winner shadows.
- Detects nvm, fnm, Volta, asdf, mise, pyenv, rbenv, jenv, nodenv, SDKMAN!, rustup, Conda,
  Homebrew (including versioned kegs), MacPorts, Nix, Python.org, JDK bundles, Docker Desktop,
  JetBrains Toolbox, Xcode and Command Line Tools stubs, and macOS system binaries.
- Explains the winner with the rc-file line that put its directory on PATH, including manager
  init lines, `/etc/paths` and `/etc/paths.d`.
- Reports `.nvmrc`, `.node-version`, `.python-version`, `.ruby-version`, `.java-version`,
  `.tool-versions` and `rust-toolchain` files and whether the winner honours them.
- Findings for duplicate version managers, shims ahead of Homebrew, system binaries winning over
  managed ones, missing and duplicated PATH entries, login and interactive shells disagreeing,
  GUI apps missing a manager, and ignored or mismatched version files.
- JSON output and exit codes for scripting.

[Unreleased]: https://github.com/mk24x7/shadow/compare/8f32faf...HEAD
