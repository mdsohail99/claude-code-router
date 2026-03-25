# CCR and Claude Code Setup Restoration Guide

This folder contains the complete, hardened configuration state for the Claude Code Router and Claude Code Setup. If you ever need to set up this environment from scratch on a new laptop or after a format, these files contain the exact configuration required to run the router with full observability, matrix native-fallback, and stealth mode.

## What is Backed Up Here?
* `settings.json` -> Your exact `~/.claude/settings.json` configuring Claude Code to use the router.
* `config.json` -> Your exact `~/.claude-code-router/config.json` defining the CCR themes, model routing, and API forwarding.
* `ccr-route-matrix.json` -> Your custom model tiering, which is natively imported into CCR for `429/400` failovers.
* `ccr.ps1` -> The custom PowerShell entrypoint fixing dev paths and interactive switching context.

## How to Restore

**Method 1: Automated Script**
Simply run the included `restore-ccr-setup.ps1` script from this folder. It will interactively ask to overwrite your system configuration files with the backed-up CCR Setup files.

```powershell
.\restore-ccr-setup.ps1
```

**Method 2: Manual Copying**
1. Copy `settings.json` to `C:\Users\<username>\.claude\settings.json`
2. Copy `config.json` and `ccr-route-matrix.json` to `C:\Users\<username>\.claude-code-router\`
3. Copy `ccr.ps1` to `C:\Users\<username>\AppData\Roaming\npm\ccr.ps1`

## Post-Restore Verification
1. Open a terminal in `C:\Dev\claude-code-router` and run `pnpm install` then `pnpm build`.
2. Run `ccr restart` to launch the API and confirm it is running on `127.0.0.1:8080`.
3. Type `ccr code` in any directory to verify Claude correctly hits the router with your configured default strictly-reasoning model.
