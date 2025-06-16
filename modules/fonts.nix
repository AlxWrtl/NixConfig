{ config, pkgs, lib, inputs, ... }:

{
  # Font configuration

  fonts = {
    # Enable font management
    fontDir.enable = true;

    # System fonts
    packages = with pkgs; [
      # Nerd Fonts (includes powerline glyphs and icons)
      nerd-fonts.meslo-lg      # MesloLGS NF (recommended for Powerlevel10k)
      nerd-fonts.hack          # Hack Nerd Font (good programming font)
      nerd-fonts.fira-code     # FiraCode Nerd Font (ligatures)
      nerd-fonts.jetbrains-mono # JetBrains Mono Nerd Font
      nerd-fonts.source-code-pro # Source Code Pro Nerd Font

      # Standard fonts
      meslo-lgs-nf             # MesloLGS NF (direct package)

      # Apple system fonts (if available)
      # These are usually included with macOS

      # Additional programming fonts
      cascadia-code           # Microsoft's Cascadia Code
      inconsolata             # Inconsolata font
      source-code-pro         # Adobe Source Code Pro

      # Additional fonts for international support
      noto-fonts              # Google Noto fonts
      noto-fonts-cjk          # CJK (Chinese, Japanese, Korean) support
      noto-fonts-emoji        # Emoji support

      # Apple fonts (system fonts, usually available by default on macOS)
      # These don't need to be explicitly installed on macOS
    ];
  };

  # Font-related environment variables
  environment.variables = {
    # Fontconfig configuration
    FONTCONFIG_FILE = "${pkgs.fontconfig.out}/etc/fonts/fonts.conf";
  };

  # System defaults for font rendering (macOS specific)
  system.defaults = {
    NSGlobalDomain = {
      # Font smoothing
      AppleFontSmoothing = 1; # Enable font smoothing for external displays

      # Text rendering improvements
      CGFontRenderingFontSmoothingDisabled = false;
    };
  };
}