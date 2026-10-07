_:

{

  homebrew = {
    enable = true;

    onActivation = {
      cleanup = "zap";
      autoUpdate = true;
      upgrade = true;
    };

    # Homebrew 6+ refuses untrusted third-party taps. Activation runs
    # `brew bundle` as homebrew.user (sudo --user), and bundle records the
    # Brewfile `trusted: true` in that user's trust store itself.
    taps = [
      {
        name = "rtk-ai/tap";
        trusted = true;
      }
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
      # Épinglé le 2026-10-07 (`brew pin --cask chatgpt`) : le téléchargement du
      # cask 26.1002.51308 renvoyait 404 et cassait `rebuild`. `brew bundle` saute
      # les casks épinglés ; l'app continue de se mettre à jour seule (auto_updates).
      # `brew unpin --cask chatgpt` une fois le cask corrigé en amont ; jamais
      # retirer l'entrée (cleanup zap = désinstallation).
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
      "jellyfin"

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
        name = "blender";
        greedy = true;
      }
      {
        name = "codex";
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
      "Keynote" = 361285480;
      # NE PAS commenter cette ligne pour contourner un échec de MAJ mas.
      # Mesuré le 2026-09-23 : `brew bundle --zap --force-cleanup` (la commande
      # que lance nix-darwin) DÉSINSTALLE une app App Store retirée du Brewfile.
      # Elle part à la corbeille, et la remettre exige `sudo` — le bundle est
      # root:wheel. Si mas échoue sur un timeout App Store, attendre ou traiter
      # `upgrade`, jamais retirer l'entrée.
      "Microsoft Excel" = 462058435;
      "Microsoft PowerPoint" = 462062816;
      "Microsoft Word" = 462054704;
      "Numbers" = 361304891;
      "Pages" = 361309726;
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
