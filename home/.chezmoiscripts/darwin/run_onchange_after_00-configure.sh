#!/usr/bin/env bash

set -eufo pipefail


function _test_full_disk_access() {
  if ! ls ~/Library/Mail &>/dev/null; then
    echo "❌ Terminal does not have full disk access."
    echo "Grant it in System Settings > Privacy & Security > Full Disk Access."
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    return 1
  fi
}


# zsh location symlink — needed on every macOS box (incl. a clawbot's minimal zsh).
ln -sf "$HOME/.config/zsh/.zshenv" "$HOME/.zshenv"

# GUI is environmental — detect at runtime (not baked). Explicit GUI in env wins.
case "${GUI:-}" in
  1|true|yes) GUI=true ;;
  0|false|no) GUI=false ;;
  *) if [ "$(uname)" = Darwin ] || [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then GUI=true; else GUI=false; fi ;;
esac

# Everything below is personal macOS desktop configuration. $CLAWBOT comes from
# chezmoi scriptEnv; a clawbot or headless box stops here.
if [ -n "${CLAWBOT:-}" ] || [ "$GUI" != true ]; then
  echo "configure: not a personal GUI machine — skipping macOS defaults."
  exit 0
fi

_test_full_disk_access || true

# Configure macOS

# Close any open System Preferences panes, to prevent them from overriding
# settings we’re about to change
osascript -e 'tell application "System Preferences" to quit'

# # Ask for the administrator password upfront
# sudo -v

# # Keep-alive: update existing `sudo` time stamp until `.macos` has finished
# while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

###############################################################################
# General                                                                    #
###############################################################################

if [[ ! -f /etc/pam.d/sudo_local ]]; then
  echo "Enabling Touch ID for sudo"
  sed -e 's/^#auth/auth/' /etc/pam.d/sudo_local.template | sudo tee /etc/pam.d/sudo_local
else
  echo "ℹ️ Touch ID for sudo seems to be already enabled!"
fi

# Set computer name (as done via System Preferences → Sharing)
# sudo scutil --set ComputerName "macarm"
# sudo scutil --set HostName "macarm"
# sudo scutil --set LocalHostName "macarm"

###############################################################################
# General UI/UX                                                               #
###############################################################################

# Enable dark mode
defaults write NSGlobalDomain AppleInterfaceStyle -string "Dark"

# Disable “natural” (Lion-style) scrolling
defaults write NSGlobalDomain com.apple.swipescrolldirection -bool false

# Expand save panel by default
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true

# Hide desktop icons
defaults write com.apple.WindowManager StandardHideDesktopIcons -bool true

###############################################################################
# Finder                                                                      #
###############################################################################

# Finder: allow quitting via ⌘ + Q; doing so will also hide desktop icons
defaults write com.apple.finder QuitMenuItem -bool true

# Finder: open in new tabs instead of new windows
defaults write com.apple.finder FinderSpawnTab -bool false

# Set the default location for new Finder windows
defaults write com.apple.finder NewWindowTarget -string "PfHm"
defaults write com.apple.finder NewWindowTargetPath -string "file://${HOME}/work/"

# Show icons for hard drives, servers, and removable media on the desktop
defaults write com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
defaults write com.apple.finder ShowHardDrivesOnDesktop -bool true
defaults write com.apple.finder ShowMountedServersOnDesktop -bool true
defaults write com.apple.finder ShowRemovableMediaOnDesktop -bool true

# Finder: show hidden files by default
defaults write com.apple.finder AppleShowAllFiles -bool true

# Finder: show all filename extensions
defaults write NSGlobalDomain AppleShowAllExtensions -bool true

# Finder: show status bar
defaults write com.apple.finder ShowStatusBar -bool true

# Finder: show path bar
defaults write com.apple.finder ShowPathbar -bool true

# Display full POSIX path as Finder window title
# defaults write com.apple.finder _FXShowPosixPathInTitle -bool true

# Keep folders on top when sorting by name
defaults write com.apple.finder _FXSortFoldersFirst -bool true

# When performing a search, search the current folder by default
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"

# Disable the warning when changing a file extension
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

# Not show tags in the sidebar
defaults write com.apple.finder ShowRecentTags -bool false

# Enable spring loading for directories
defaults write NSGlobalDomain com.apple.springing.enabled -bool true

# Remove the spring loading delay for directories
defaults write NSGlobalDomain com.apple.springing.delay -float 0

# # Automatically open a new Finder window when a volume is mounted NOT TESTED!
# defaults write com.apple.frameworks.diskimages auto-open-ro-root -bool true
# defaults write com.apple.frameworks.diskimages auto-open-rw-root -bool true
# defaults write com.apple.finder OpenWindowForNewRemovableDisk -bool true

# Use list view in all Finder windows by default
# Four-letter codes for the other view modes: `icnv`, `clmv`, `glyv`
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"

###############################################################################
# Dock                                            #
###############################################################################

# Automatically hide and show the Dock
defaults write com.apple.dock autohide -bool false

# Remove the auto-hiding Dock delay
defaults write com.apple.dock autohide-delay -float 0

# # Remove the animation when hiding/showing the Dock
# defaults write com.apple.dock autohide-time-modifier -float 0

# Set the icon size of Dock items to 36 pixels
defaults write com.apple.dock tilesize -int 36

# Change dock position to left
defaults write com.apple.dock orientation -string "left"

# Change minimize/maximize window effect
# defaults write com.apple.dock mineffect -string "scale"

# Minimize windows into their application’s icon
# defaults write com.apple.dock minimize-to-application -bool true

# Enable spring loading for all Dock items
defaults write com.apple.dock enable-spring-load-actions-on-all-items -bool true

# Show indicator lights for open applications in the Dock
defaults write com.apple.dock show-process-indicators -bool true

# Show only open applications in the Dock
#defaults write com.apple.dock static-only -bool true

# Don’t animate opening applications from the Dock
# defaults write com.apple.dock launchanim -bool false

# Disable Dashboard
# defaults write com.apple.dashboard mcx-disabled -bool true

# Don’t show Dashboard as a Space
# defaults write com.apple.dock dashboard-in-overlay -bool true

# Don’t automatically rearrange Spaces based on most recent use
# defaults write com.apple.dock mru-spaces -bool false

# # Make Dock icons of hidden applications translucent
# defaults write com.apple.dock showhidden -bool true

# # Don’t show recent applications in Dock
# defaults write com.apple.dock show-recents -bool false

###############################################################################
# Safari & WebKit                                                             #
###############################################################################

# Open new tabs and windows with a blank page
defaults write com.apple.Safari NewTabBehavior -int 1
defaults write com.apple.Safari NewWindowBehavior -int 1

# # Privacy: don’t send search queries to Apple
defaults write com.apple.Safari UniversalSearchEnabled -bool false
defaults write com.apple.Safari SuppressSearchSuggestions -bool true

# Disable preloading of top hit in the background
defaults write com.apple.Safari PreloadTopHit -bool false

# Configure search default engine
defaults write com.apple.Safari PrivateSearchEngineUsesNormalSearchEngineToggle -bool false
defaults write com.apple.Safari PrivateSearchProviderShortName -string "DuckDuckGo"
defaults write com.apple.Safari WBSLastPrivateSearchEngineStringExplicitlyChosenByUserKey -string "com.com.duckduckgo"

# Warn before using HTTP
defaults write com.apple.Safari UseHTTPSOnly -bool false # change it to true if needed!

# # Press Tab to highlight each item on a web page
defaults write com.apple.Safari WebKitPreferences.tabFocusesLinks -bool true
defaults write com.apple.Safari WebKitTabToLinksPreferenceKey -bool true

# # Show the full URL in the address bar (note: this still hides the scheme)
defaults write com.apple.Safari ShowFullURLInSmartSearchField -bool true

# Prevent Safari from opening ‘safe’ files automatically after downloading
defaults write com.apple.Safari AutoOpenSafeDownloads -bool false

# Save articles to read offline
defaults write com.apple.Safari ReadingListSaveArticlesOfflineAutomatically -bool true

# # Show Safari’s bookmarks bar by default
defaults write com.apple.Safari ShowFavoritesBar-v2 -bool true

###############################################################################
# Spotlight shortcuts (⌘-Space / ⌥⌘-Space) — disabled so they don't clash      #
###############################################################################

function _disable_spotlight_shortcuts() {
  echo "ℹ️  Disabling Spotlight shortcuts…"
  local plist="$HOME/Library/Preferences/com.apple.symbolichotkeys.plist"

  if /usr/libexec/PlistBuddy "$plist" \
      -c "Set :AppleSymbolicHotKeys:64:enabled false" \
      -c "Set :AppleSymbolicHotKeys:65:enabled false" >/dev/null 2>&1; then
    return 0
  fi

  /usr/libexec/PlistBuddy "$plist" \
    -c "Delete :AppleSymbolicHotKeys:64" \
    -c "Add :AppleSymbolicHotKeys:64:enabled bool false" \
    -c "Add :AppleSymbolicHotKeys:64:value:parameters array" \
    -c "Add :AppleSymbolicHotKeys:64:value:parameters: integer 32" \
    -c "Add :AppleSymbolicHotKeys:64:value:parameters: integer 49" \
    -c "Add :AppleSymbolicHotKeys:64:value:parameters: integer 1048576" \
    -c "Add :AppleSymbolicHotKeys:64:type string standard" >/dev/null 2>&1 || true

  /usr/libexec/PlistBuddy "$plist" \
    -c "Delete :AppleSymbolicHotKeys:65" \
    -c "Add :AppleSymbolicHotKeys:65:enabled bool false" \
    -c "Add :AppleSymbolicHotKeys:65:value:parameters array" \
    -c "Add :AppleSymbolicHotKeys:65:value:parameters: integer 32" \
    -c "Add :AppleSymbolicHotKeys:65:value:parameters: integer 49" \
    -c "Add :AppleSymbolicHotKeys:65:value:parameters: integer 1572864" \
    -c "Add :AppleSymbolicHotKeys:65:type string standard" >/dev/null 2>&1 || true
}

_disable_spotlight_shortcuts || echo "⚠️  Spotlight shortcut tweak skipped."

###############################################################################
# Screen-recording permission report (informational)                          #
###############################################################################

_apps_needing_permissions=()

function _check_screen_recording() {
  local app_name="$1"
  if [[ ! -d "/Applications/${app_name}.app" && ! -d "$HOME/Applications/${app_name}.app" ]]; then
    return 0
  fi
  local bundle_id; bundle_id=$(osascript -e "id of app \"${app_name}\"" 2>/dev/null)
  [ -z "$bundle_id" ] && return 0

  local sys usr
  sys=$(sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
    "SELECT auth_value FROM access WHERE service='kTCCServiceScreenCapture' AND client='${bundle_id}';" 2>/dev/null)
  usr=$(sqlite3 "$HOME/Library/Application Support/com.apple.TCC/TCC.db" \
    "SELECT auth_value FROM access WHERE service='kTCCServiceScreenCapture' AND client='${bundle_id}';" 2>/dev/null)
  if [[ "$sys" == "2" || "$usr" == "2" ]]; then
    echo "✅ ${app_name} has screen recording access"
  else
    echo "❌ ${app_name} lacks screen recording access"
    _apps_needing_permissions+=("$app_name")
  fi
}

echo "🔎 Checking screen-recording permissions…"
for _app in "Slack" "zoom.us" "Google Chrome" "Brave Browser"; do
  _check_screen_recording "$_app"
done
if (( ${#_apps_needing_permissions[@]} > 0 )); then
  echo "⚙️  Grant screen recording in System Settings > Privacy & Security > Screen & System Audio Recording for:"
  printf '    • %s\n' "${_apps_needing_permissions[@]}"
  open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture" 2>/dev/null || true
fi

###############################################################################
# Manual TODOs                                                                #
###############################################################################
# 1. Enable developer menu in Safari
