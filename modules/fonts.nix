{ config, pkgs, lib, inputs, ... }:

{
  # === OPTIMIZED FONT CONFIGURATION ===

  fonts = {
    # System fonts with smart categorization
    packages = with pkgs; [

      # === PROGRAMMING FONTS WITH NERD FONT ICONS ===
      # These include powerline glyphs and developer icons
      nerd-fonts.meslo-lg      # MesloLGS NF (recommended for Powerlevel10k)
      nerd-fonts.hack          # Hack Nerd Font (clean programming font)
      nerd-fonts.fira-code     # FiraCode Nerd Font (programming ligatures)
      nerd-fonts.jetbrains-mono # JetBrains Mono Nerd Font (modern)
      nerd-fonts.sauce-code-pro # Source Code Pro Nerd Font (Adobe)

      # === ADDITIONAL PROGRAMMING FONTS ===
      cascadia-code           # Microsoft's Cascadia Code (VS Code default)
      inconsolata             # Inconsolata font (Google)

      # === INTERNATIONAL SUPPORT FONTS ===
      noto-fonts              # Google Noto fonts (universal coverage)
      noto-fonts-cjk-sans     # CJK (Chinese, Japanese, Korean) support
      noto-fonts-emoji        # Emoji support (latest Unicode standard)

    ];
  };

  # === FONT-RELATED ENVIRONMENT VARIABLES ===
  environment.variables = {
    # Fontconfig configuration path
    FONTCONFIG_FILE = "${pkgs.fontconfig.out}/etc/fonts/fonts.conf";

    # Terminal font preferences (can be overridden by terminal apps)
    TERMINAL_FONT = "MesloLGS Nerd Font";
    EDITOR_FONT = "JetBrainsMono Nerd Font";
  };
}