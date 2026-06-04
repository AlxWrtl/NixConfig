{ ... }:

{

  homebrew = {
    enable = true;

    onActivation = {
      cleanup = "zap";
      autoUpdate = true;
      upgrade = true;
      # Newer Homebrew refuses `brew bundle install --cleanup` without one of
      # --force/--force-cleanup/$HOMEBREW_ASK. nix-darwin doesn't pass it yet
      # (upstream PR #1774). --force-cleanup is the non-interactive-safe choice
      # (HOMEBREW_ASK would prompt/hang). Drop once nix-darwin ships the fix.
      extraFlags = [ "--force-cleanup" ];
    };

    taps = [
      "rtk-ai/tap"
    ];

    brews = [
      "cloudflared"
      "rtk-ai/tap/rtk"
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
      "chatgpt"
      "claude"
      "claude-code@latest"
      "codex-app"
      "discord"
      "docker-desktop"
      "figma"
      "google-chrome"
      "notion"
      "obsidian"
      "raycast"
      "readdle-spark"
      "visual-studio-code"
      "microsoft-teams"
      "whatsapp"

      # No auto-updater — greedy keeps them current
      {
        name = "appcleaner";
        greedy = true;
      }
      {
        name = "coteditor";
        greedy = true;
      }
      {
        name = "ghostty";
        greedy = true;
      }
      {
        name = "jordanbaird-ice";
        greedy = true;
      }
      {
        name = "keka";
        greedy = true;
      }
      {
        name = "logi-options+";
        greedy = true;
      }
      {
        name = "ollama-app";
        greedy = true;
      }
      {
        name = "plex-media-server";
        greedy = true;
      }
      {
        name = "tailscale-app";
        greedy = true;
      }
      {
        name = "transmission";
        greedy = true;
      }
      {
        name = "vlc";
        greedy = true;
      }
      {
        name = "zed";
        greedy = true;
      }
    ];

    masApps = {
      "DaisyDisk" = 411643860;
      "Keynote" = 409183694;
      "Microsoft Excel" = 462058435;
      "Microsoft PowerPoint" = 462062816;
      "Microsoft Word" = 462054704;
      "Numbers" = 409203825;
      "Pages" = 409201541;
      "Trello" = 1278508951;
      "Affinity Photo" = 824183456;
      "Affinity Publisher" = 881418622;
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
