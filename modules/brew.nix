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

    caskArgs.no_quarantine = true;

    onActivation = {
      cleanup = "zap";
      autoUpdate = true;
      upgrade = true;
    };

    global.brewfile = true;

    taps = [ ];

    brews = [
      "mas"
      "trash"
      "libomp"
    ];

    casks = [
      {
        name = "1password";
        greedy = true;
      }
      {
        name = "jordanbaird-ice";
        greedy = true;
      }
      {
        name = "logi-options+";
        greedy = true;
      }
      {
        name = "keka";
        greedy = true;
      }
      {
        name = "docker-desktop";
        greedy = true;
      }
      {
        name = "visual-studio-code";
        greedy = true;
      }
      {
        name = "chatgpt";
        greedy = true;
      }
      {
        name = "ollama-app";
        greedy = true;
      }
      {
        name = "ghostty";
        greedy = true;
      }
      {
        name = "raycast";
        greedy = true;
      }
      {
        name = "notion";
        greedy = true;
      }
      {
        name = "figma";
        greedy = true;
      }
      {
        name = "discord";
        greedy = true;
      }
      {
        name = "microsoft-teams";
        greedy = true;
      }
      {
        name = "whatsapp";
        greedy = true;
      }
      {
        name = "readdle-spark";
        greedy = true;
      }
      {
        name = "arc";
        greedy = true;
      }
      {
        name = "google-chrome";
        greedy = true;
      }
      {
        name = "vlc";
        greedy = true;
      }
      {
        name = "plex-media-server";
        greedy = true;
      }
      {
        name = "chatgpt-atlas";
        greedy = true;
      }
      {
        name = "coteditor";
        greedy = true;
      }
      {
        name = "claude-code";
        greedy = true;
      }
      {
        name = "claude";
        greedy = true;
      }
      {
        name = "codex";
        greedy = true;
      }
      {
        name = "appcleaner";
        greedy = true;
      }
      {
        name = "upscayl";
        greedy = true;
      }
      {
        name = "transmission";
        greedy = true;
      }
      {
        name = "qgis";
        greedy = true;
      }
      {
        name = "microsoft-office";
        greedy = true;
      }
    ];

    masApps = {
      "Pages" = 409201541;
      "Numbers" = 409203825;
      "Keynote" = 409183694;
      "Trello" = 1278508951;
      "DaisyDisk" = 411643860;
    };
  };

  environment.variables = {
    HOMEBREW_CASK_OPTS_NO_BINARIES = "1";
    MAS_NO_PROMPT = "1";
  };

  environment.systemPath = [
    "/opt/homebrew/bin"
    "/usr/local/bin"
  ];
}
