# Security Policy

## Supported versions

Only the latest release of Shadow (app and CLI) receives security fixes.

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub private vulnerability reporting:
open the repository's Security tab and choose "Report a vulnerability"
(https://github.com/mk24x7/shadow/security/advisories/new).

Do not open a public issue for security problems.

Include the Shadow version, macOS version, whether you used the app or the CLI, and the smallest PATH layout or rc file that reproduces the problem.

You should receive an acknowledgement within 7 days. Once a fix is released the advisory will be published and you will be credited unless you ask otherwise.

## What Shadow executes

Shadow is read-only, but it does run programs, and that is where the risk lives:

- It starts `zsh`, `bash`, `sh` and (when installed) `fish` as login and interactive shells to capture PATH. Those shells read your rc files exactly as a new terminal would.
- It runs each copy of each requested tool it finds on PATH with a version argument (`--version`, `-version`, `version`), from argv arrays with a 5 second timeout, never through a shell string.
- It runs `xcrun --find`, `/usr/libexec/java_home` and `launchctl getenv PATH`.

It never runs the Xcode `/usr/bin` stubs when the developer tools are missing (that would open an installer), and never runs the Java stub when no JDK is installed.

## Scope

In scope:

- Any way Shadow writes to, modifies or deletes a file, rc file, environment variable or PATH entry.
- Any way a crafted tool name, directory name, rc-file line or version file makes Shadow execute something other than a copy of the requested tool found on a captured PATH, or pass it arguments other than the fixed version arguments.
- Command injection through the CLI arguments or the app's directory picker.

Out of scope: a malicious executable that is already on your PATH doing harm when Shadow asks it for its version. Any terminal command would run it too; do not put untrusted directories on PATH.
