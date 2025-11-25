#!/bin/bash
#
# Smart Tarball Installer
# Intelligent installation of pre-compiled binary applications from tarballs
# For Fedora Linux with KDE Plasma
#

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

# Installation locations to check for conflicts (in order of preference)
INSTALL_LOCATIONS=(
    "$HOME/.local/share"
    "$HOME/Applications"
    "$HOME/.local/bin"
    "$HOME/bin"
)

# Primary installation target
PRIMARY_INSTALL_DIR="$HOME/.local/share"

# Desktop file location
DESKTOP_DIR="$HOME/.local/share/applications"

# Symlink location for terminal access
BIN_DIR="$HOME/.local/bin"

# Log directory
LOG_DIR="$HOME/.local/share/smart-install-logs"

# Temporary workspace base
TMP_BASE="/tmp"

# Source code indicators (files/patterns that suggest this needs compilation)
SOURCE_INDICATORS=(
    "configure"
    "configure.ac"
    "Makefile.in"
    "Makefile.am"
    "CMakeLists.txt"
    "meson.build"
    "setup.py"
    "Cargo.toml"
    "go.mod"
)

# ============================================================================
# GLOBAL VARIABLES
# ============================================================================

TARBALL_PATH=""
TARBALL_NAME=""
TMP_DIR=""
LOG_FILE=""
APP_NAME=""
INSTALL_DIR=""
EXTRACTED_ROOT=""

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

init_log() {
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    mkdir -p "$LOG_DIR"
    LOG_FILE="$LOG_DIR/${APP_NAME}-${timestamp}.log"
    
    {
        echo "========================================"
        echo "Smart Tarball Installer - Installation Log"
        echo "========================================"
        echo "Timestamp: $(date)"
        echo "Original archive: $TARBALL_PATH"
        echo "Archive filename: $TARBALL_NAME"
        echo "Derived app name: $APP_NAME"
        echo "----------------------------------------"
    } > "$LOG_FILE"
}

log() {
    echo "[$(date +%H:%M:%S)] $*" >> "$LOG_FILE"
}

# Log metadata without timestamp prefix for easy parsing by uninstaller
log_metadata() {
    echo "$*" >> "$LOG_FILE"
}

log_section() {
    {
        echo ""
        echo "=== $* ==="
    } >> "$LOG_FILE"
}

# ============================================================================
# NOTIFICATION FUNCTIONS
# ============================================================================

notify_success() {
    notify-send -i package-x-generic "Smart Install" "$1" 2>/dev/null || true
}

notify_error() {
    notify-send -u critical -i dialog-error "Smart Install Error" "$1" 2>/dev/null || true
}

notify_warning() {
    notify-send -u normal -i dialog-warning "Smart Install" "$1" 2>/dev/null || true
}

# ============================================================================
# DIALOG FUNCTIONS
# ============================================================================

dialog_error() {
    kdialog --error "$1" --title "Smart Install Error" 2>/dev/null || \
        zenity --error --text="$1" --title="Smart Install Error" 2>/dev/null || \
        echo "ERROR: $1" >&2
}

dialog_info() {
    kdialog --msgbox "$1" --title "Smart Install" 2>/dev/null || \
        zenity --info --text="$1" --title="Smart Install" 2>/dev/null || \
        echo "INFO: $1"
}

dialog_yesno() {
    kdialog --yesno "$1" --title "Smart Install" 2>/dev/null
}

dialog_input() {
    local prompt="$1"
    local default="$2"
    kdialog --inputbox "$prompt" "$default" --title "Smart Install" 2>/dev/null || \
        zenity --entry --text="$prompt" --entry-text="$default" --title="Smart Install" 2>/dev/null
}

dialog_menu() {
    local prompt="$1"
    shift
    # kdialog --menu expects: tag1 item1 tag2 item2 ...
    kdialog --menu "$prompt" "$@" --title "Smart Install" 2>/dev/null
}

dialog_checklist() {
    local prompt="$1"
    shift
    # kdialog --checklist expects: tag1 item1 status1 tag2 item2 status2 ...
    kdialog --checklist "$prompt" "$@" --title "Smart Install" 2>/dev/null
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

cleanup() {
    log "Cleaning up temporary files..."
    if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
        rm -rf "$TMP_DIR"
        log "Removed temporary directory: $TMP_DIR"
    fi
}

# Set trap for cleanup on exit
trap cleanup EXIT

derive_app_name() {
    local filename="$1"
    local name
    
    # Remove path
    name=$(basename "$filename")
    
    # Remove common extensions
    name="${name%.tar.gz}"
    name="${name%.tar.xz}"
    name="${name%.tgz}"
    name="${name%.txz}"
    
    # Remove architecture strings first (before version numbers to avoid partial matches)
    name=$(echo "$name" | sed -E 's/[-_](x86_64|x86-64|amd64|x64|i686|i386|arm64|aarch64)//gi')
    
    # Remove OS identifiers
    name=$(echo "$name" | sed -E 's/[-_](linux|Linux|gnu|GNU|win|windows|macos|darwin)//gi')
    
    # Remove version numbers (patterns like -1.2.3, _v1.2, -1.0.0-beta, etc.)
    # This pattern looks for version-like sequences: dash/underscore followed by numbers with dots
    name=$(echo "$name" | sed -E 's/[-_]v?[0-9]+(\.[0-9]+)*([-.][a-zA-Z0-9]+)?//g')
    
    # Remove release type suffixes
    name=$(echo "$name" | sed -E 's/[-_]+(release|stable|beta|alpha|rc[0-9]*)//gi')
    
    # Remove trailing dashes/underscores
    name=$(echo "$name" | sed -E 's/[-_]+$//')
    
    # Remove leading dashes/underscores
    name=$(echo "$name" | sed -E 's/^[-_]+//')
    
    # Convert to lowercase for consistency
    name=$(echo "$name" | tr '[:upper:]' '[:lower:]')
    
    # If we've stripped everything, fall back to first word of original filename
    if [[ -z "$name" ]]; then
        name=$(basename "$filename" | sed -E 's/[-_].*//' | tr '[:upper:]' '[:lower:]')
    fi
    
    echo "$name"
}

# ============================================================================
# ARCHIVE HANDLING
# ============================================================================

extract_archive() {
    local archive="$1"
    local dest="$2"
    
    log "Extracting archive to: $dest"
    
    case "$archive" in
        *.tar.gz|*.tgz)
            tar -xzf "$archive" -C "$dest" 2>>"$LOG_FILE"
            ;;
        *.tar.xz|*.txz)
            tar -xJf "$archive" -C "$dest" 2>>"$LOG_FILE"
            ;;
        *.tar)
            tar -xf "$archive" -C "$dest" 2>>"$LOG_FILE"
            ;;
        *)
            log "ERROR: Unsupported archive format: $archive"
            return 1
            ;;
    esac
    
    log "Extraction complete"
    return 0
}

find_extracted_root() {
    # Find the root of the extracted content
    # Could be a single directory, multiple directories, or files directly
    
    local contents
    contents=$(ls -A "$TMP_DIR/extract")
    local count
    count=$(echo "$contents" | wc -l)
    
    if [[ $count -eq 1 ]] && [[ -d "$TMP_DIR/extract/$contents" ]]; then
        # Single directory - this is the root
        EXTRACTED_ROOT="$TMP_DIR/extract/$contents"
        log "Extracted root (single directory): $EXTRACTED_ROOT"
    else
        # Multiple items or files at root level
        EXTRACTED_ROOT="$TMP_DIR/extract"
        log "Extracted root (multiple items): $EXTRACTED_ROOT"
    fi
}

# ============================================================================
# SOURCE CODE DETECTION
# ============================================================================

detect_source_code() {
    local found_indicators=()
    
    log_section "Source Code Detection"
    
    for indicator in "${SOURCE_INDICATORS[@]}"; do
        if find "$EXTRACTED_ROOT" -maxdepth 3 -name "$indicator" -type f 2>/dev/null | grep -q .; then
            found_indicators+=("$indicator")
            log "Found source indicator: $indicator"
        fi
    done
    
    # Check for src directory with source files
    if find "$EXTRACTED_ROOT" -maxdepth 3 -type d -iname "src" 2>/dev/null | while read -r srcdir; do
        if find "$srcdir" -maxdepth 2 \( -name "*.c" -o -name "*.cpp" -o -name "*.h" -o -name "*.hpp" \) 2>/dev/null | grep -q .; then
            echo "found"
            break
        fi
    done | grep -q "found"; then
        found_indicators+=("src/ with C/C++ files")
        log "Found src directory with C/C++ source files"
    fi
    
    if [[ ${#found_indicators[@]} -gt 0 ]]; then
        local indicator_list
        indicator_list=$(printf ", %s" "${found_indicators[@]}")
        indicator_list="${indicator_list:2}"  # Remove leading ", "
        
        log "Source code detected! Indicators: $indicator_list"
        
        dialog_error "This archive appears to contain source code requiring manual compilation.

Found indicators: $indicator_list

Installation halted. Please compile this software manually using the appropriate build system."
        
        notify_warning "Source code detected - manual compilation required"
        return 1
    fi
    
    log "No source code indicators found - appears to be pre-compiled"
    return 0
}

# ============================================================================
# CONFLICT DETECTION
# ============================================================================

search_existing_installations() {
    local search_term="$1"
    local found_paths=()
    
    log_section "Conflict Detection"
    log "Search term: $search_term"
    
    for location in "${INSTALL_LOCATIONS[@]}"; do
        if [[ -d "$location" ]]; then
            # Case-insensitive search
            while IFS= read -r -d '' match; do
                found_paths+=("$match")
                log "Found match: $match"
            done < <(find "$location" -maxdepth 2 -type d -iname "*${search_term}*" -print0 2>/dev/null)
        fi
    done
    
    # Also check for desktop files
    if [[ -d "$DESKTOP_DIR" ]]; then
        while IFS= read -r -d '' match; do
            local desktop_name
            desktop_name=$(basename "$match" .desktop)
            log "Found matching desktop file: $match"
        done < <(find "$DESKTOP_DIR" -maxdepth 1 -type f -iname "*${search_term}*.desktop" -print0 2>/dev/null)
    fi
    
    printf '%s\n' "${found_paths[@]}"
}

handle_conflicts() {
    local search_term="$1"
    local -a conflicts=()
    
    # Read conflicts into array, filtering empty lines
    while IFS= read -r line; do
        [[ -n "$line" ]] && conflicts+=("$line")
    done < <(search_existing_installations "$search_term")
    
    if [[ ${#conflicts[@]} -eq 0 ]]; then
        log "No existing installations found"
        return 0  # No conflicts, proceed
    fi
    
    log "Found ${#conflicts[@]} potential conflicts"
    
    # Build list for display
    local conflict_list=""
    for path in "${conflicts[@]}"; do
        conflict_list+="• $path"$'\n'
    done
    
    # Present options to user
    local choice
    choice=$(dialog_menu "Found existing installation(s) matching '$search_term':

$conflict_list
What would you like to do?" \
        "replace" "Remove existing and install new version" \
        "anyway" "Install anyway (keep both)" \
        "abort" "Cancel installation")
    
    case "$choice" in
        "replace")
            log "User chose: Remove and replace"
            for path in "${conflicts[@]}"; do
                log "Removing: $path"
                rm -rf "$path"
                
                # Also remove associated desktop files
                local basename_lower
                basename_lower=$(basename "$path" | tr '[:upper:]' '[:lower:]')
                find "$DESKTOP_DIR" -maxdepth 1 -type f -iname "*${basename_lower}*.desktop" -delete 2>/dev/null || true
            done
            log "Existing installations removed"
            return 0
            ;;
        "anyway")
            log "User chose: Install anyway"
            return 0
            ;;
        "abort"|"")
            log "User chose: Abort installation"
            return 1
            ;;
    esac
}

# ============================================================================
# INSTALLATION
# ============================================================================

find_executables() {
    # Find executable files in the extracted content
    find "$EXTRACTED_ROOT" -type f -executable 2>/dev/null | while read -r exe; do
        # Filter out scripts and libraries, focus on ELF binaries
        if file "$exe" 2>/dev/null | grep -qE "(ELF|executable)"; then
            echo "$exe"
        fi
    done
}

find_desktop_file() {
    find "$EXTRACTED_ROOT" -maxdepth 3 -type f -name "*.desktop" 2>/dev/null | head -1
}

find_icon_file() {
    # Look for common icon locations and formats
    local icon=""
    
    # Check for icons in standard locations
    for pattern in "*.png" "*.svg" "*.xpm" "*.ico"; do
        icon=$(find "$EXTRACTED_ROOT" -maxdepth 4 -type f \( -iname "$pattern" \) \
            \( -path "*/icons/*" -o -path "*/pixmaps/*" -o -iname "*icon*" -o -iname "$APP_NAME*" \) \
            2>/dev/null | head -1)
        if [[ -n "$icon" ]]; then
            echo "$icon"
            return
        fi
    done
    
    # Fallback: any image file
    find "$EXTRACTED_ROOT" -maxdepth 4 -type f \( -name "*.png" -o -name "*.svg" \) 2>/dev/null | head -1
}

install_application() {
    log_section "Installation"
    
    # Determine final installation directory
    INSTALL_DIR="$PRIMARY_INSTALL_DIR/$APP_NAME"
    
    # Handle case where we're installing to a fresh location
    if [[ -d "$INSTALL_DIR" ]]; then
        # Add timestamp to avoid collision
        INSTALL_DIR="${INSTALL_DIR}-$(date +%Y%m%d%H%M%S)"
    fi
    
    log "Installation directory: $INSTALL_DIR"
    
    # Create installation directory and copy files
    mkdir -p "$INSTALL_DIR"
    cp -a "$EXTRACTED_ROOT"/* "$INSTALL_DIR"/
    
    log "Files copied to installation directory"
    
    # Find the main executable
    local main_exe
    main_exe=$(find_executables | head -1)
    
    if [[ -z "$main_exe" ]]; then
        log "WARNING: No executable found in archive"
        dialog_info "Warning: No executable binary was found in this archive. You may need to set permissions manually."
    else
        # Get the relative path within the installed location
        local exe_relative="${main_exe#$EXTRACTED_ROOT/}"
        local installed_exe="$INSTALL_DIR/$exe_relative"
        
        log "Main executable: $installed_exe"
        
        # Ensure executable permission
        chmod +x "$installed_exe"
        
        # Create symlink in bin directory
        local exe_name
        exe_name=$(basename "$installed_exe")
        local symlink_path="$BIN_DIR/$exe_name"
        
        # Remove existing symlink if present
        [[ -L "$symlink_path" ]] && rm "$symlink_path"
        
        ln -s "$installed_exe" "$symlink_path"
        log_metadata "Created symlink: $symlink_path -> $installed_exe"
    fi
    
    # Handle desktop file
    install_desktop_file "$main_exe"
    
    # Log installed files manifest
    log_section "Installed Files Manifest"
    find "$INSTALL_DIR" -type f -printf '%M %p\n' >> "$LOG_FILE" 2>/dev/null || \
        find "$INSTALL_DIR" -type f >> "$LOG_FILE"
    
    return 0
}

install_desktop_file() {
    local main_exe="$1"
    local desktop_file
    desktop_file=$(find_desktop_file)
    
    local dest_desktop="$DESKTOP_DIR/${APP_NAME}.desktop"
    
    log_section "Desktop Integration"
    
    if [[ -n "$desktop_file" ]]; then
        log "Found existing desktop file: $desktop_file"
        cp "$desktop_file" "$dest_desktop"
        
        # Update paths in the desktop file
        local exe_relative="${main_exe#$EXTRACTED_ROOT/}"
        local installed_exe="$INSTALL_DIR/$exe_relative"
        
        # Update Exec line to use absolute path
        sed -i "s|^Exec=.*|Exec=$installed_exe|" "$dest_desktop" 2>/dev/null || true
        
        # Handle Icon - make it absolute path if relative
        local current_icon
        current_icon=$(grep "^Icon=" "$dest_desktop" | cut -d= -f2)
        if [[ -n "$current_icon" && ! "$current_icon" = /* ]]; then
            # Icon is relative, try to find it
            local icon_file
            icon_file=$(find "$INSTALL_DIR" -name "$current_icon*" -type f 2>/dev/null | head -1)
            if [[ -n "$icon_file" ]]; then
                sed -i "s|^Icon=.*|Icon=$icon_file|" "$dest_desktop"
                log "Updated icon path: $icon_file"
            fi
        fi
    else
        log "No desktop file found, creating minimal one"
        
        # Find icon
        local icon_source
        icon_source=$(find_icon_file)
        local icon_path="application-x-executable"  # Default fallback
        
        if [[ -n "$icon_source" ]]; then
            # Copy icon to installed location if not already there
            local icon_name
            icon_name=$(basename "$icon_source")
            local icon_dest="$INSTALL_DIR/$icon_name"
            
            if [[ ! -f "$icon_dest" ]]; then
                cp "$icon_source" "$icon_dest"
            fi
            icon_path="$icon_dest"
            log "Icon: $icon_path"
        fi
        
        # Determine executable path
        local exe_path=""
        if [[ -n "$main_exe" ]]; then
            local exe_relative="${main_exe#$EXTRACTED_ROOT/}"
            exe_path="$INSTALL_DIR/$exe_relative"
        fi
        
        # Create minimal desktop file
        cat > "$dest_desktop" << EOF
[Desktop Entry]
Type=Application
Name=${APP_NAME^}
Exec=$exe_path
Icon=$icon_path
Terminal=false
Categories=Utility;
EOF
        log "Created minimal desktop file"
    fi
    
    # Make desktop file executable (required by some systems)
    chmod +x "$dest_desktop"
    log_metadata "Desktop file installed: $dest_desktop"
    
    # Update desktop database
    update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
}

# ============================================================================
# MAIN FUNCTION
# ============================================================================

main() {
    # Check for required argument
    if [[ $# -lt 1 ]]; then
        dialog_error "Usage: smart-install.sh <tarball-path>"
        exit 1
    fi
    
    TARBALL_PATH="$1"
    TARBALL_NAME=$(basename "$TARBALL_PATH")
    
    # Verify file exists
    if [[ ! -f "$TARBALL_PATH" ]]; then
        dialog_error "File not found: $TARBALL_PATH"
        exit 1
    fi
    
    # Derive application name from filename
    APP_NAME=$(derive_app_name "$TARBALL_NAME")
    
    # Initialize logging
    init_log
    log "Starting installation process"
    
    # Create temporary workspace
    TMP_DIR=$(mktemp -d "$TMP_BASE/smart-install-XXXXXX")
    mkdir -p "$TMP_DIR/extract"
    log "Temporary directory: $TMP_DIR"
    
    # Extract archive
    if ! extract_archive "$TARBALL_PATH" "$TMP_DIR/extract"; then
        dialog_error "Failed to extract archive. Check that it's a valid tarball."
        log "ERROR: Extraction failed"
        exit 1
    fi
    
    # Find the extracted root
    find_extracted_root
    
    # Check for source code
    if ! detect_source_code; then
        log "Installation aborted: source code detected"
        exit 0
    fi
    
    # Prompt user for search string (for conflict detection)
    local search_string
    search_string=$(dialog_input "Enter search string for detecting existing installations:" "$APP_NAME")
    
    if [[ -z "$search_string" ]]; then
        search_string="$APP_NAME"
    fi
    
    log "User-confirmed search string: $search_string"
    
    # Check for conflicts
    if ! handle_conflicts "$search_string"; then
        log "Installation aborted by user"
        dialog_info "Installation cancelled."
        exit 0
    fi
    
    # Perform installation
    if install_application; then
        log_section "Installation Complete"
        log_metadata "Final installation directory: $INSTALL_DIR"
        log "Log file: $LOG_FILE"
        
        notify_success "Successfully installed to:
$INSTALL_DIR"
        
        dialog_info "Installation complete!

Application: ${APP_NAME^}
Location: $INSTALL_DIR
Log file: $LOG_FILE

The application should now appear in your application menu."
    else
        dialog_error "Installation failed. Check log file for details:
$LOG_FILE"
        exit 1
    fi
}

# Run main function
main "$@"
