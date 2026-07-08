{ ... }:

{

  homebrew = {
    enable = true;

    onActivation = {
      cleanup = "zap";
      autoUpdate = true;
      upgrade = true;
      # brew bundle runs as root during activation; `brew trust` writes to the
      # user's $HOMEBREW_USER_CONFIG_HOME/trust.json, which root never reads, so
      # third-party taps (rtk-ai/tap) get refused. Disable the trust gate for
      # the activation run — taps here are declared in this config, i.e. trusted.
      extraEnv = {
        HOMEBREW_NO_REQUIRE_TAP_TRUST = "1";
      };
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
      "postgresql@16"
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
        name = "android-platform-tools";
        greedy = true;
      }
      {
        name = "appcleaner";
        greedy = true;
      }
      {
        name = "balenaetcher";
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
        name = "hp-easy-admin";
        greedy = true;
      }
      {
        name = "hp-easy-start";
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
