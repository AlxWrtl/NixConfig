{
  config,
  pkgs,
  lib,
  ...
}:

{
  xdg.configFile."ghostty/config" = {
    force = true;
    text = ''
      # General
      auto-update = download
      cursor-click-to-move = true
      window-inherit-working-directory = true
      quit-after-last-window-closed = true
      term = xterm-256color

      # Appearance
      theme = Catppuccin Macchiato
      background-opacity = 0.9
      background-blur = 10
      font-family = MesloLGS Nerd Font
      font-size = 12
      font-thicken = false
      macos-window-shadow = true
      minimum-contrast = 1.1
      macos-titlebar-style = transparent

      # Custom icon
      macos-icon = custom-style
      macos-icon-ghost-color = 292b3b
      macos-icon-screen-color = 292b3b

      # Window
      confirm-close-surface = false
      title = " "
      window-new-tab-position = current
      window-save-state = always
      window-padding-x = 10
      window-padding-y = 10
      window-padding-balance = true
      window-decoration = true
      window-step-resize = true
      resize-overlay = never
      resize-overlay-position = center
      resize-overlay-duration = 750ms

      # Focus & splits
      focus-follows-mouse = false
      unfocused-split-opacity = 0.7
      unfocused-split-fill = #292b3b

      # Clipboard
      clipboard-read = allow
      clipboard-write = allow
      clipboard-trim-trailing-spaces = true
      clipboard-paste-protection = true
      clipboard-paste-bracketed-safe = true

      # Mouse
      copy-on-select = true
      mouse-hide-while-typing = true
      mouse-shift-capture = false
      click-repeat-interval = 500

      # Selection
      selection-foreground = #c6d0f5
      selection-background = #626880

      # Cursor (non-blinking bar)
      cursor-style = bar
      cursor-style-blink =
      cursor-opacity = 1.0
      cursor-color = #87a2bf
      cursor-text = #292b3b

      # Shell integration (no cursor override)
      shell-integration = detect
      shell-integration-features = no-cursor

      # Performance
      scrollback-limit = 134217728
      image-storage-limit = 335544320
      window-vsync = true
      window-inherit-font-size = true

      # Input
      macos-option-as-alt = true
      mouse-scroll-multiplier = 1.0

      # Quick terminal (Cmd+Shift+Space)
      keybind = global:cmd+shift+space=toggle_quick_terminal
      quick-terminal-position = top
      quick-terminal-screen = main
      quick-terminal-animation-duration = 0.3
      quick-terminal-autohide = true

      # Features
      link-url = true
      bold-is-bright = false
      adjust-cell-width = 0
      adjust-cell-height = 0
      title-report = false
      desktop-notifications = true

      # macOS security
      macos-auto-secure-input = true
      macos-secure-input-indication = true
      macos-non-native-fullscreen = false
      macos-titlebar-proxy-icon = hidden

      # Shell
      working-directory = ${config.home.homeDirectory}
      command = /run/current-system/sw/bin/zsh

      # Keybindings
      keybind = shift+enter=text:\n
    '';
  };
}
