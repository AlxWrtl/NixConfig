{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

{

  homebrew = {
    enable = true;

    onActivation = {
      cleanup = "zap";
      autoUpdate = true;
      upgrade = true;
    };

    brews = [
      "cloudflared"
      "displayplacer"
      "ffmpeg"
      "libomp"
      "mas"
      "trash"
    ];

    # Apps with auto-updaters: simple strings (no greedy)
    # Apps without auto-updaters: greedy = true to keep them current
    casks = [
      # Auto-updating apps
      "1password"
      "arc"
      "claude"
      "claude-code"
      "discord"
      "docker-desktop"
      "figma"
      "google-chrome"
      "microsoft-excel"
      "microsoft-powerpoint"
      "microsoft-teams"
      "microsoft-word"
      "notion"
      "obsidian"
      "raycast"
      "readdle-spark"
      "visual-studio-code"
      "whatsapp"

      # No auto-updater — greedy keeps them current
      { name = "appcleaner"; greedy = true; }
      { name = "coteditor"; greedy = true; }
      { name = "ghostty"; greedy = true; }
      { name = "jordanbaird-ice"; greedy = true; }
      { name = "keka"; greedy = true; }
      { name = "logi-options+"; greedy = true; }
      { name = "ollama-app"; greedy = true; }
      { name = "plex-media-server"; greedy = true; }
      { name = "tailscale-app"; greedy = true; }
      { name = "transmission"; greedy = true; }
      { name = "upscayl"; greedy = true; }
      { name = "vlc"; greedy = true; }
    ];

    masApps = {
      "DaisyDisk" = 411643860;
      "Keynote" = 409183694;
      "Numbers" = 409203825;
      "Pages" = 409201541;
      "Trello" = 1278508951;
    };
  };

  environment.variables = {
    MAS_NO_PROMPT = "1";
  };

  environment.systemPath = [
    "/opt/homebrew/bin"
    "/usr/local/bin"
  ];
}
