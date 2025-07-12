{ config, pkgs, lib, inputs, ... }:

{
  # Font configuration for development and system use
  # Programming fonts with Nerd Font support and international character sets
  # Optimized for terminal, code editors, and general system typography

  # ============================================================================
  # FONT PACKAGES
  # ============================================================================
  
  fonts = {
    packages = with pkgs; [

      # === Programming Fonts with Nerd Font Icons ===
      # These fonts include powerline glyphs, developer icons, and Unicode symbols
      nerd-fonts.meslo-lg                    # MesloLGS NF - recommended for Powerlevel10k/Starship
      nerd-fonts.hack                        # Hack Nerd Font - clean, readable programming font
      nerd-fonts.fira-code                   # FiraCode NF - programming ligatures for operators
      nerd-fonts.jetbrains-mono              # JetBrains Mono NF - modern geometric programming font
      nerd-fonts.sauce-code-pro              # Source Code Pro NF - Adobe's programming font

      # === Additional Programming Fonts ===
      # Modern programming fonts without Nerd Font patches
      cascadia-code                          # Microsoft Cascadia Code - VS Code's default font
      inconsolata                            # Google Inconsolata - humanist monospace font

      # === System & International Typography ===
      # Comprehensive Unicode support for international content
      noto-fonts                             # Google Noto - universal font family
      noto-fonts-cjk-sans                    # CJK (Chinese, Japanese, Korean) language support
      noto-fonts-emoji                       # Modern emoji support with latest Unicode standards

      # === Additional Font Families ===
      # Uncomment and add more fonts as needed:
      # liberation_ttf                        # LibreOffice-compatible fonts
      # dejavu_fonts                          # DejaVu font family
      # ubuntu_font_family                    # Ubuntu system fonts
      # source-sans-pro                       # Adobe Source Sans Pro
      # source-serif-pro                      # Adobe Source Serif Pro
    ];
  };

  # ============================================================================
  # FONT ENVIRONMENT CONFIGURATION
  # ============================================================================
  
  environment.variables = {
    # === Fontconfig System Integration ===
    FONTCONFIG_FILE = "${pkgs.fontconfig.out}/etc/fonts/fonts.conf";

    # === Default Font Preferences ===
    # These can be overridden by individual applications
    TERMINAL_FONT = "MesloLGS Nerd Font";     # Optimized for terminal and Starship prompt
    EDITOR_FONT = "JetBrainsMono Nerd Font";  # Modern programming font for code editors

    # === Additional Font Environment Variables ===
    # MONOSPACE_FONT = "Hack Nerd Font";      # Alternative monospace font
    # UI_FONT = "Inter";                      # Modern UI font (if available)
  };

  # ============================================================================
  # FONT CONFIGURATION NOTES
  # ============================================================================
  # 
  # Font Selection Strategy:
  # - Programming fonts with Nerd Font patches for terminal/editor use
  # - International fonts for global content support
  # - System fonts for native macOS integration
  #
  # Nerd Fonts Benefits:
  # - Powerline symbols for enhanced shell prompts
  # - Developer icons for file managers and status bars
  # - Extended Unicode coverage for technical symbols
  #
  # Font Management:
  # - System fonts are automatically available to all applications
  # - Use `fc-list` to view available fonts
  # - Run `fc-cache -f -v` to refresh font cache if needed
  # - Font preferences can be overridden in application settings
  #
  # Performance Considerations:
  # - Nerd Fonts are larger due to additional glyphs
  # - Consider system performance when adding many font families
  # - International fonts (CJK) significantly increase font cache size
  #
  # Application Integration:
  # - Terminal applications: Use TERMINAL_FONT variable
  # - Code editors: Use EDITOR_FONT variable or app-specific settings
  # - System UI: macOS uses San Francisco font by default
}