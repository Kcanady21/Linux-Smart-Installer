# Smart Tarball Installer

A lightweight, intelligent installer for pre-compiled Linux applications distributed as tarballs. Integrates with KDE Plasma's Dolphin file manager for right-click installation.

Built for **Fedora Linux with KDE Plasma**, but should work on any Linux distribution with KDE.

## Why?

Some applications are only distributed as `.tar.gz` or `.tar.xz` archives. Installing these manually means:

- Extracting to the right location
- Setting executable permissions
- Creating desktop entries for your app menu
- Creating symlinks for terminal access
- Remembering what you installed and where

**Smart Install automates all of this** with a single right-click.

## Features

- **Right-click installation** — Select "Smart Install" from Dolphin's context menu
- **Source code detection** — Automatically detects if an archive contains source code requiring compilation and halts with a helpful message
- **Conflict detection** — Searches standard installation locations for existing versions; offers to replace, install alongside, or abort
- **Desktop integration** — Creates/updates `.desktop` files so apps appear in your application menu
- **Terminal access** — Creates symlinks in `~/.local/bin/` for command-line launching
- **Comprehensive logging** — Every installation is logged for easy troubleshooting and uninstallation
- **Clean uninstallation** — Companion uninstaller removes apps and all associated files

## Installation

```bash
# Create required directories
mkdir -p ~/.local/share/kio/servicemenus ~/.local/bin ~/.local/share/smart-install-logs

# Download or copy the files, then:
cp smart-install.sh ~/.local/bin/
cp smart-uninstall.sh ~/.local/bin/
cp smart-install-tarball.desktop ~/.local/share/kio/servicemenus/

# Make executable
chmod +x ~/.local/bin/smart-install.sh
chmod +x ~/.local/bin/smart-uninstall.sh
chmod +x ~/.local/share/kio/servicemenus/smart-install-tarball.desktop

# Ensure ~/.local/bin is in your PATH (add to ~/.bashrc if needed)
export PATH="$HOME/.local/bin:$PATH"

# Rebuild KDE service cache
kbuildsycoca6  # or kbuildsycoca5 on older Plasma
```

## Usage

### Installing Applications

**Via Dolphin (GUI):**
1. Right-click any `.tar.gz` or `.tar.xz` file
2. Select **"Smart Install"**
3. Follow the dialogs

**Via Terminal:**
```bash
smart-install.sh /path/to/application.tar.gz
```

### Uninstalling Applications

**Interactive (GUI):**
```bash
smart-uninstall.sh
```

**List installed applications:**
```bash
smart-uninstall.sh --list
```

**Remove specific application:**
```bash
smart-uninstall.sh --remove <app-name>
```

## How It Works

1. **Extract** — Archive is extracted to a temporary directory for analysis
2. **Analyze** — Checks for source code indicators (configure, CMakeLists.txt, Makefile.in, etc.)
3. **Conflict check** — Searches `~/.local/share/`, `~/Applications/`, `~/.local/bin/`, and `~/bin/` for existing installations
4. **Install** — Copies files to `~/.local/share/<app-name>/`
5. **Integrate** — Creates desktop entry in `~/.local/share/applications/` and symlink in `~/.local/bin/`
6. **Log** — Records everything to `~/.local/share/smart-install-logs/`

## File Locations

| Component | Location |
|-----------|----------|
| Installer script | `~/.local/bin/smart-install.sh` |
| Uninstaller script | `~/.local/bin/smart-uninstall.sh` |
| Service menu | `~/.local/share/kio/servicemenus/smart-install-tarball.desktop` |
| Installed apps | `~/.local/share/<app-name>/` |
| Desktop entries | `~/.local/share/applications/` |
| Terminal symlinks | `~/.local/bin/` |
| Installation logs | `~/.local/share/smart-install-logs/` |

## Troubleshooting

### "You are not authorized to execute this file" in Dolphin

This is a KDE security feature. Try these solutions:

1. Rebuild the KDE service cache:
   ```bash
   kbuildsycoca6
   ```

2. Make the service menu file executable:
   ```bash
   chmod +x ~/.local/share/kio/servicemenus/smart-install-tarball.desktop
   ```

3. Log out and back in, or restart Dolphin:
   ```bash
   kquitapp6 dolphin && dolphin &
   ```

4. Use terminal as a workaround:
   ```bash
   smart-install.sh /path/to/your-app.tar.gz
   ```

### Menu entry doesn't appear

Run `kbuildsycoca6` (or `kbuildsycoca5` on older Plasma), or log out and back in.

### Script fails with "command not found"

Ensure required utilities are installed:
```bash
# Fedora
sudo dnf install kdialog libnotify tar

# Debian/Ubuntu
sudo apt install kdialog libnotify-bin tar
```

## Dependencies

- `bash`
- `tar`
- `kdialog` (for GUI dialogs; falls back to `zenity` if unavailable)
- `notify-send` (for desktop notifications)
- `find`, `sed`, `grep` (standard Unix utilities)

## Testing

A test application tarball is included for verifying your setup:

```bash
# Install the test app
smart-install.sh testapp-1.0.0-linux-x86_64.tar.gz

# Run it
testapp --cli

# Verify it appears in uninstaller
smart-uninstall.sh --list

# Remove it
smart-uninstall.sh --remove testapp
```
## Known Bugs
   1. "smart-uninstall.sh --list" in the terminal will return a blank list even when apps have been installed through the smart installer. However, "typing smart-install.sh" will display a gui that does properly show the apps installed via this method and can be easily uninstalled there.

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.

## License

MIT License — see [LICENSE](LICENSE) for details.
