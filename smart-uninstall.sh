#!/bin/bash
#
# Smart Tarball Uninstaller
# Companion to smart-install.sh - removes applications installed by Smart Install
# For Fedora Linux with KDE Plasma
#

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

LOG_DIR="$HOME/.local/share/smart-install-logs"
DESKTOP_DIR="$HOME/.local/share/applications"
BIN_DIR="$HOME/.local/bin"

# ============================================================================
# DIALOG FUNCTIONS
# ============================================================================

dialog_error() {
    kdialog --error "$1" --title "Smart Uninstall" 2>/dev/null || \
        zenity --error --text="$1" --title="Smart Uninstall" 2>/dev/null || \
        echo "ERROR: $1" >&2
}

dialog_info() {
    kdialog --msgbox "$1" --title "Smart Uninstall" 2>/dev/null || \
        zenity --info --text="$1" --title="Smart Uninstall" 2>/dev/null || \
        echo "INFO: $1"
}

dialog_yesno() {
    kdialog --yesno "$1" --title "Smart Uninstall" 2>/dev/null
}

dialog_menu() {
    local prompt="$1"
    shift
    kdialog --menu "$prompt" "$@" --title "Smart Uninstall" 2>/dev/null
}

dialog_checklist() {
    local prompt="$1"
    shift
    kdialog --checklist "$prompt" "$@" --title "Smart Uninstall" 2>/dev/null
}

notify_success() {
    notify-send -i package-remove "Smart Uninstall" "$1" 2>/dev/null || true
}

# ============================================================================
# LOG PARSING FUNCTIONS
# ============================================================================

get_installed_apps() {
    # Parse log files to find installed applications
    # Returns: app_name|install_dir|log_file|timestamp
    # Deduplicates by app_name, keeping the most recent log
    
    if [[ ! -d "$LOG_DIR" ]]; then
        return
    fi
    
    # Use associative array to deduplicate by app_name
    declare -A seen_apps
    
    # Process log files (sorted by name, newest first due to timestamp in filename)
    for log_file in $(ls -r "$LOG_DIR"/*.log 2>/dev/null); do
        [[ -f "$log_file" ]] || continue
        
        # Reset variables for each file
        local app_name=""
        local install_dir=""
        local timestamp=""
        
        # Extract info from log file using grep for reliability
        app_name=$(grep "^Derived app name: " "$log_file" 2>/dev/null | head -1 | sed 's/^Derived app name: //')
        install_dir=$(grep "^Final installation directory: " "$log_file" 2>/dev/null | head -1 | sed 's/^Final installation directory: //')
        timestamp=$(grep "^Timestamp: " "$log_file" 2>/dev/null | head -1 | sed 's/^Timestamp: //')
        
        # Only include if we found valid installation info and directory still exists
        if [[ -n "$app_name" && -n "$install_dir" && -d "$install_dir" ]]; then
            # Skip if we've already seen this app (keeps first/newest due to sort order)
            if [[ -z "${seen_apps[$app_name]:-}" ]]; then
                seen_apps[$app_name]=1
                echo "${app_name}|${install_dir}|${log_file}|${timestamp}"
            fi
        fi
    done
}

parse_log_for_removal() {
    local log_file="$1"
    
    local install_dir=""
    local desktop_file=""
    local symlinks=()
    local app_name=""
    
    local in_manifest=false
    
    while IFS= read -r line; do
        # Get app name
        if [[ "$line" == "Derived app name: "* ]]; then
            app_name="${line#Derived app name: }"
        fi
        
        # Get installation directory
        if [[ "$line" == "Final installation directory: "* ]]; then
            install_dir="${line#Final installation directory: }"
        fi
        
        # Get desktop file
        if [[ "$line" == "Desktop file installed: "* ]]; then
            desktop_file="${line#Desktop file installed: }"
        fi
        
        # Get symlinks - look for pattern "Created symlink: /path -> /target"
        if [[ "$line" == *"Created symlink: "* ]]; then
            local symlink_part="${line#*Created symlink: }"
            local symlink_path="${symlink_part%% -> *}"
            symlinks+=("$symlink_path")
        fi
        
    done < "$log_file"
    
    # Output parsed info
    echo "APP_NAME=$app_name"
    echo "INSTALL_DIR=$install_dir"
    echo "DESKTOP_FILE=$desktop_file"
    echo "SYMLINKS=${symlinks[*]:-}"
}

# ============================================================================
# UNINSTALL FUNCTIONS
# ============================================================================

remove_application() {
    local log_file="$1"
    local removed_items=()
    local failed_items=()
    
    # Parse log file
    local app_name=""
    local install_dir=""
    local desktop_file=""
    local symlinks=""
    
    while IFS='=' read -r key value; do
        case "$key" in
            APP_NAME) app_name="$value" ;;
            INSTALL_DIR) install_dir="$value" ;;
            DESKTOP_FILE) desktop_file="$value" ;;
            SYMLINKS) symlinks="$value" ;;
        esac
    done < <(parse_log_for_removal "$log_file")
    
    echo "Removing: $app_name"
    echo "  Install dir: $install_dir"
    echo "  Desktop file: $desktop_file"
    echo "  Symlinks: $symlinks"
    
    # Remove symlinks first
    for symlink in $symlinks; do
        if [[ -L "$symlink" ]]; then
            if rm "$symlink" 2>/dev/null; then
                removed_items+=("Symlink: $symlink")
            else
                failed_items+=("Symlink: $symlink")
            fi
        fi
    done
    
    # Remove desktop file
    if [[ -n "$desktop_file" && -f "$desktop_file" ]]; then
        if rm "$desktop_file" 2>/dev/null; then
            removed_items+=("Desktop file: $desktop_file")
        else
            failed_items+=("Desktop file: $desktop_file")
        fi
    fi
    
    # Also check for desktop file by app name pattern
    for df in "$DESKTOP_DIR"/*"$app_name"*.desktop; do
        if [[ -f "$df" ]]; then
            if rm "$df" 2>/dev/null; then
                removed_items+=("Desktop file: $df")
            else
                failed_items+=("Desktop file: $df")
            fi
        fi
    done
    
    # Remove installation directory
    if [[ -n "$install_dir" && -d "$install_dir" ]]; then
        if rm -rf "$install_dir" 2>/dev/null; then
            removed_items+=("Directory: $install_dir")
        else
            failed_items+=("Directory: $install_dir")
        fi
    fi
    
    # Archive the log file (don't delete, rename with .removed suffix)
    if [[ -f "$log_file" ]]; then
        mv "$log_file" "${log_file%.log}.removed.log"
        removed_items+=("Log archived: ${log_file%.log}.removed.log")
    fi
    
    # Update desktop database
    update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true
    
    # Report results
    echo ""
    echo "=== Removal Summary ==="
    
    if [[ ${#removed_items[@]} -gt 0 ]]; then
        echo "Successfully removed:"
        printf '  • %s\n' "${removed_items[@]}"
    fi
    
    if [[ ${#failed_items[@]} -gt 0 ]]; then
        echo "Failed to remove:"
        printf '  • %s\n' "${failed_items[@]}"
        return 1
    fi
    
    return 0
}

# ============================================================================
# INTERACTIVE MODE
# ============================================================================

interactive_uninstall() {
    # Get list of installed apps
    local apps_data
    apps_data=$(get_installed_apps)
    
    if [[ -z "$apps_data" ]]; then
        dialog_info "No applications installed by Smart Install were found.

Either no applications have been installed, or they have already been removed."
        exit 0
    fi
    
    # Build menu items
    local -a menu_items=()
    local -A app_logs=()
    
    while IFS='|' read -r app_name install_dir log_file timestamp; do
        local display_name="${app_name^} ($(basename "$install_dir"))"
        menu_items+=("$app_name" "$display_name - installed $timestamp")
        app_logs["$app_name"]="$log_file"
    done <<< "$apps_data"
    
    if [[ ${#menu_items[@]} -eq 0 ]]; then
        dialog_info "No applications found to uninstall."
        exit 0
    fi
    
    # Show selection dialog
    local selected
    selected=$(dialog_menu "Select an application to uninstall:" "${menu_items[@]}")
    
    if [[ -z "$selected" ]]; then
        exit 0
    fi
    
    local log_file="${app_logs[$selected]}"
    
    # Parse and show what will be removed
    local app_name=""
    local install_dir=""
    local desktop_file=""
    local symlinks=""
    
    while IFS='=' read -r key value; do
        case "$key" in
            APP_NAME) app_name="$value" ;;
            INSTALL_DIR) install_dir="$value" ;;
            DESKTOP_FILE) desktop_file="$value" ;;
            SYMLINKS) symlinks="$value" ;;
        esac
    done < <(parse_log_for_removal "$log_file")
    
    # Build confirmation message
    local confirm_msg="Are you sure you want to uninstall ${app_name^}?

The following will be removed:"
    
    [[ -n "$install_dir" && -d "$install_dir" ]] && confirm_msg+="
• $install_dir"
    
    [[ -n "$desktop_file" && -f "$desktop_file" ]] && confirm_msg+="
• $desktop_file"
    
    for symlink in $symlinks; do
        [[ -L "$symlink" ]] && confirm_msg+="
• $symlink"
    done
    
    confirm_msg+="

This action cannot be undone."
    
    if ! dialog_yesno "$confirm_msg"; then
        dialog_info "Uninstall cancelled."
        exit 0
    fi
    
    # Perform removal
    if remove_application "$log_file"; then
        notify_success "${app_name^} has been uninstalled"
        dialog_info "${app_name^} has been successfully uninstalled."
    else
        dialog_error "Some items could not be removed. Check permissions and try again."
        exit 1
    fi
}

# ============================================================================
# CLI MODE
# ============================================================================

list_installed() {
    echo "Applications installed by Smart Install:"
    echo "========================================="
    echo ""
    
    local apps_data
    apps_data=$(get_installed_apps)
    
    if [[ -z "$apps_data" ]]; then
        echo "No applications found."
        return
    fi
    
    local count=0
    while IFS='|' read -r app_name install_dir log_file timestamp; do
        ((count++))
        echo "$count. ${app_name^}"
        echo "   Location: $install_dir"
        echo "   Installed: $timestamp"
        echo "   Log: $log_file"
        echo ""
    done <<< "$apps_data"
}

cli_uninstall() {
    local target="$1"
    
    # Find matching app
    local apps_data
    apps_data=$(get_installed_apps)
    
    local log_file=""
    while IFS='|' read -r app_name install_dir lf timestamp; do
        if [[ "${app_name,,}" == "${target,,}" ]]; then
            log_file="$lf"
            break
        fi
    done <<< "$apps_data"
    
    if [[ -z "$log_file" ]]; then
        echo "Error: Application '$target' not found."
        echo "Use --list to see installed applications."
        exit 1
    fi
    
    echo "Uninstalling: $target"
    
    if remove_application "$log_file"; then
        echo ""
        echo "Successfully uninstalled $target"
        notify_success "$target has been uninstalled"
    else
        echo ""
        echo "Warning: Some items could not be removed"
        exit 1
    fi
}

# ============================================================================
# HELP
# ============================================================================

show_help() {
    cat << 'EOF'
Smart Uninstall - Remove applications installed by Smart Install

Usage:
  smart-uninstall.sh              Interactive mode (KDE dialogs)
  smart-uninstall.sh --list       List all installed applications
  smart-uninstall.sh --remove APP Remove specific application by name
  smart-uninstall.sh --help       Show this help message

Examples:
  smart-uninstall.sh --list
  smart-uninstall.sh --remove minecraft
  smart-uninstall.sh --remove curseforge

The uninstaller reads installation logs from:
  ~/.local/share/smart-install-logs/

And removes:
  • Application directory
  • Desktop menu entry
  • Terminal symlinks
  • Archives (not deletes) the installation log
EOF
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    case "${1:-}" in
        --help|-h)
            show_help
            ;;
        --list|-l)
            list_installed
            ;;
        --remove|-r)
            if [[ -z "${2:-}" ]]; then
                echo "Error: --remove requires an application name"
                echo "Use --list to see installed applications"
                exit 1
            fi
            cli_uninstall "$2"
            ;;
        "")
            interactive_uninstall
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
