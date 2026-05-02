# ram-root

Run your OpenWrt router entirely from a RAM drive — with optional backup and restore to a local or remote server.

---

## Overview

**ram-root** creates a RAM-based overlay filesystem (using `tmpfs` or `zram`) and pivots your router's root into it. This gives you a writable, expanded environment to install packages, test configurations, and make changes — all without touching your router's flash storage. A simple reboot returns everything to its original state.

Optional backup and restore support lets you persist your RAM drive state across reboots by saving it to a local path or a remote server over SSH.

### Why use it?

- **No USB port?** Extend your usable storage into RAM without any hardware changes.
- **Limited flash?** Install and test packages that wouldn't fit on your flash drive.
- **Want a safe sandbox?** Try new configs or upgrades without risk — reboot to undo everything.
- **Need persistence?** Back up your RAM drive state and restore it automatically on next boot.

### How `zram` vs `tmpfs` affects memory

If `e2fsprogs`, `kmod-fs-ext4`, and `kmod-zram` are installed before running ram-root, the RAM drive is stored on a `zram` (compressed) block device. This uses approximately **half the memory** of a plain `tmpfs` mount, effectively doubling your usable capacity for the same memory footprint. Installing `zram-swap` is also recommended for an additional ~50% memory headroom.

---

## Installation

1. Download and extract the provided `.zip` file, placing the `ram-root` directory at the **root of your router's filesystem** (`/`). After extraction you should have `/ram-root/`.

2. Edit `/ram-root/ram-root.cfg` to match your setup (server address, backup options, packages, etc.) before running for the first time.

3. Optionally install recommended packages if your flash space allows:
   ```sh
   apk add e2fsprogs kmod-fs-ext4 kmod-zram zram-swap
   ```

4. Run the init command (see below) from a local console for first-time setup.

---

## Usage

### First-time setup
```sh
/ram-root/ram-root.sh init
```
Runs the first-time installation: sets up the RAM drive, configures the server (if using remote backup), installs any defined packages, and registers ram-root in `/etc/init.d/` for future use.

---

### Start
```sh
/etc/init.d/ram-root start
```
Starts ram-root, restoring from your backup if one exists.

### Stop
```sh
/etc/init.d/ram-root stop
```
Stops ram-root and reboots the router back to its original flash-based state. If the backup option is enabled, a backup is created before rebooting.

### Backup
```sh
/etc/init.d/ram-root backup
```
Saves the current RAM drive state to your configured local or remote backup location. Can be run at any time while ram-root is active. Backup is also performed automatically on first `init` if enabled in the config.

### Reset
```sh
/etc/init.d/ram-root reset
```
Starts a fresh RAM drive, **bypassing** the existing backup. Useful when you want to discard your saved state and start clean.

### Status
```sh
/etc/init.d/ram-root status
```
Shows whether ram-root is currently active.

### Upgrade
```sh
/etc/init.d/ram-root upgrade
```
Interactively upgrades installed packages using `apk upgrade`.

---

## Configuration highlights

The config file at `/ram-root/ram-root.cfg` is self-documented. Key options:

- **`SERVER`** — IP address of your backup server. Set to the router's own IP (or `localhost`) for local backup.
- **`BACKUP`** — Enable or disable backup/restore functionality.
- **`BACKGROUND_BACKUP`** — Run backups in the background so they don't block operation.
- **`PRE_PACKAGES`** — Packages installed fresh on every ram-root start, *not* included in the backup. Useful for large packages on routers with limited flash — they are re-installed each boot instead of being persisted.
- **`INIT_PACKAGES`** — Packages installed once during `init` and included in subsequent backups.
- **`EXCLUDE_FILE` / `INCLUDE_FILE`** — Fine-grained control over what gets included in backups.

### Enable autostart
Once you're confident everything works:
```sh
/etc/init.d/ram-root enable
```
This makes ram-root start automatically on every boot.

### Accessing the original filesystem
While ram-root is active, your original flash filesystem is mounted at `/old_root`. You can navigate there to make changes to the base system directly.

---

## Examples

**Example 1 — Remote backup server:**
You have a second router or PC that is always reachable. Run `init`, install and configure your packages, then run `backup`. On the next boot, `start` will restore everything automatically.

**Example 2 — No backup device, limited flash:**
Define your required packages in `PRE_PACKAGES`. ram-root will install them fresh on every start from the package repository. Only your configuration changes need to be backed up, keeping the backup file small and flash usage minimal. The trade-off is a slightly longer startup time while packages are downloaded and installed.

---

## Included tools (`/ram-root/tools/`)

| Script | Description |
|---|---|
| `opkgclean.sh` | Removes debris left by failed package installations due to flash storage shortage |
| `opkgdeps.sh` | Lists all dependencies for a given package |
| `opkgupgrade.sh` | Interactively upgrades all installed packages |
| `overlaypkgs.sh` | Saves user-installed packages before an upgrade and restores them afterward |
| `ssh-copy-id` | Copies SSH credentials to the remote backup device |
| `zram-status` | Displays zram drive statistics |

---

## Notes

- The previous (flash-based) root is always accessible at `/old_root` while ram-root is running.
- If a previous ram-root run did not complete successfully, a `/tmp/ram-root.failsafe` file is created. Remove it after fixing the problem to allow ram-root to run again.
- `zram` support requires `e2fsprogs`, `kmod-fs-ext4`, and `kmod-zram` to be installed **before** running `init`.
- Upgraded to new 'apk' repository management system.


