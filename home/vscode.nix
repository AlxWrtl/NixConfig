{
  config,
  pkgs,
  lib,
  ...
}:

let
  settingsPath = "Library/Application Support/Code/User";

  extensions = [
    "anthropic.claude-code"
    "bradlc.vscode-tailwindcss"
    "charliermarsh.ruff"
    "eamodio.gitlens"
    "esbenp.prettier-vscode"
    "github.copilot-chat"
    "jnoortheen.nix-ide"
    "ms-python.debugpy"
    "ms-python.python"
    "ms-python.vscode-pylance"
    "ms-python.vscode-python-envs"
    "ms-vscode-remote.remote-ssh"
    "ms-vscode-remote.remote-ssh-edit"
    "ms-vscode.remote-explorer"
    "openai.chatgpt"
    "prisma.prisma"
  ];

  settings = {
    # Format on save/paste/type
    "editor.formatOnPaste" = true;
    "editor.formatOnType" = true;
    "editor.formatOnSave" = true;
    "editor.codeActionsOnSave" = {
      "source.fixAll.eslint" = "always";
      "source.organizeImports" = "always";
      "source.addMissingImports" = "always";
      "source.fixAll" = "always";
    };
    "editor.stickyTabStops" = true;
    "files.trimTrailingWhitespace" = true;
    "editor.defaultFormatter" = null;

    # Appearance
    "diffEditor.ignoreTrimWhitespace" = false;
    "editor.fontSize" = 13;
    "editor.fontFamily" = "'FantasqueSansM Nerd Font Mono',Fira Code,hack nerd, FiraCode-Regular";
    "editor.cursorBlinking" = "expand";
    "editor.cursorSmoothCaretAnimation" = "on";
    "editor.cursorStyle" = "line-thin";
    "editor.cursorSurroundingLines" = 5;
    "editor.minimap.enabled" = false;

    "workbench.colorCustomizations" = {
      "editor.background" = "#1f2335";
      "activityBar.background" = "#1f2335";
      "activityBar.border" = "#1f2335";
      "sideBar.background" = "#1b1e2c";
      "sideBarSectionHeader.background" = "#1f2335";
      "editorMarkerNavigation.background" = "#1f2335";
      "editorHoverWidget.background" = "#1f2335";
      "editorBracketMatch.background" = "#1f2335";
      "editorGroupHeader.tabsBackground" = "#1f2335";
      "editorGroupHeader.noTabsBackground" = "#1f2335";
      "editorPane.background" = "#1f2335";
      "editorWidget.background" = "#1f2335";
      "tab.activeBackground" = "#1f2335";
      "tab.inactiveBackground" = "#1f2335";
      "panel.background" = "#1f2335";
      "titleBar.activeBackground" = "#1f2335";
      "titleBar.inactiveBackground" = "#1f2335";
      "breadcrumb.background" = "#1f2335";
      "peekViewEditor.background" = "#1f2335";
      "editorSuggestWidget.background" = "#1f2335";
      "notebook.cellEditorBackground" = "#1f2335";
      "editorGroup.emptyBackground" = "#1f2335";
      "editorGutter.background" = "#1f2335";
      "activityBar.activeBackground" = "#2F4858";
      "list.activeSelectionBackground" = "#2F4858";
      "list.inactiveSelectionBackground" = "#2F4858";
      "editorSuggestWidget.selectedBackground" = "#2e8b8d";
      "editorSuggestWidget.highlightForeground" = "#ff6a00";
      "editorSuggestWidget.focusHighlightForeground" = "#ffffff";
      "tree.indentGuidesStroke" = "#67EEAA";
      "panel.border" = "#67EEAA";
      "sideBar.border" = "#375948";
      "scrollbar.shadow" = "#282C34";
      "gitDecoration.untrackedResourceForeground" = "#4fdbdb";
      "list.errorForeground" = "#903b24";
      "list.warningForeground" = "#00d9ff";
      "gitDecoration.modifiedResourceForeground" = "#f3b361";
      "gitDecoration.ignoredResourceForeground" = "#5a5757";
      "editorBracketHighlight.foreground1" = "#ffb86c";
      "editorBracketHighlight.foreground2" = "#8be9fd";
      "editorBracketHighlight.foreground3" = "#bd93f9";
      "editorBracketHighlight.foreground4" = "#50fa7b";
      "editorBracketHighlight.foreground5" = "#f1fa8c";
      "editorBracketHighlight.foreground6" = "#abb2c0";
      "editorBracketHighlight.unexpectedBracket.foreground" = "#ff5555";
      "terminal.background" = "#00000000";
    };

    "workbench.sideBar.location" = "right";
    "workbench.editor.tabActionCloseVisibility" = false;
    "explorer.compactFolders" = false;
    "editor.scrollbar.verticalScrollbarSize" = 10;
    "editor.showFoldingControls" = "never";
    "workbench.layoutControl.enabled" = false;
    "window.title" = " ";
    "window.commandCenter" = false;
    "editor.occurrencesHighlight" = "off";
    "editor.lightbulb.enabled" = "off";

    # Linked editing (HTML tags)
    "editor.linkedEditing" = true;

    # Language: C
    "[c]" = {
      "editor.defaultFormatter" = "ms-vscode.cpptools";
      "editor.insertSpaces" = false;
      "editor.tabSize" = 4;
    };

    # Language: Python
    "[python]" = {
      "editor.defaultFormatter" = "ms-python.autopep8";
      "editor.formatOnSave" = true;
      "editor.formatOnType" = true;
      "editor.formatOnPaste" = true;
    };
    "python.languageServer" = "Pylance";
    "isort.args" = [ "--profile" "autopep8" ];
    "python.terminal.executeInFileDir" = true;
    "python.experiments.enabled" = false;

    # Language: JavaScript
    "[javascript]" = {
      "editor.formatOnSave" = true;
      "editor.tabSize" = 2;
      "editor.defaultFormatter" = "esbenp.prettier-vscode";
    };
    "javascript.updateImportsOnFileMove.enabled" = "always";

    # Language: HTML
    "[html]" = {
      "editor.tabSize" = 2;
      "editor.defaultFormatter" = "esbenp.prettier-vscode";
    };

    # Language: CSS / Tailwind
    "[css]" = {
      "editor.tabSize" = 2;
      "editor.defaultFormatter" = "esbenp.prettier-vscode";
    };
    "files.associations" = {
      "*.css" = "tailwindcss";
      "*.tsx" = "typescriptreact";
    };

    # Language: JSON
    "[jsonc]" = {
      "editor.defaultFormatter" = "esbenp.prettier-vscode";
    };

    # Language: TypeScript
    "typescript.updateImportsOnFileMove.enabled" = "always";
    "[typescriptreact]" = {
      "editor.defaultFormatter" = "esbenp.prettier-vscode";
      "editor.insertSpaces" = true;
    };
    "[typescript]" = {
      "editor.defaultFormatter" = "esbenp.prettier-vscode";
      "editor.insertSpaces" = true;
      "typescript.preferences.renameMatchingJsxTags" = true;
    };

    # Language: SQL
    "[sql]" = {
      "editor.defaultFormatter" = "inferrinizzard.prettier-sql-vscode";
    };

    # Extensions
    "workbench.editor.enablePreview" = false;
    "javascript.suggest.autoImports" = true;
    "eslint.validate" = [ "javascript" "javascriptreact" "typescript" "typescriptreact" ];
    "eslint.workingDirectories" = [ { mode = "auto"; } ];
    "typescript.enablePromptUseWorkspaceTsdk" = true;
    "extensions.ignoreRecommendations" = true;
    "files.autoSave" = "afterDelay";
    "explorer.confirmDelete" = false;
    "debug.disassemblyView.showSourceCode" = false;
    "explorer.confirmDragAndDrop" = false;
    "notebook.stickyScroll.enabled" = true;
    "git.openRepositoryInParentFolders" = "never";
    "workbench.startupEditor" = "none";
    "github.copilot.editor.enableAutoCompletions" = true;
    "security.workspace.trust.untrustedFiles" = "open";

    # Git
    "git.mergeEditor" = true;
    "git.autofetch" = true;
    "git.confirmSync" = false;
    "git.untrackedChanges" = "separate";
    "git.suggestSmartCommit" = false;

    # Terminal
    "code-runner.runInTerminal" = true;
    "terminal.integrated.sendKeybindingsToShell" = true;
    "terminal.integrated.cursorStyleInactive" = "line";
    "terminal.integrated.defaultProfile.osx" = "zsh";
    "terminal.external.osxExec" = "iTerm.app";
    "terminal.integrated.fontFamily" = "'MesloLGS NF' ,FantasqueSansM Nerd Font Mono, Fira Code, hack nerd, FiraCode-Regular";
    "terminal.integrated.cursorStyle" = "line";
    "terminal.integrated.fontSize" = 12;
    "terminal.integrated.shellIntegration.enabled" = false;

    # Suggestions & UI
    "editor.inlineSuggest.suppressSuggestions" = true;
    "editor.guides.bracketPairs" = true;
    "editor.guides.bracketPairsHorizontal" = "active";
    "diffEditor.maxComputationTime" = 0;
    "workbench.activityBar.location" = "hidden";
    "workbench.settings.applyToAllProfiles" = [ "workbench.colorCustomizations" ];
    "window.titleBarStyle" = "custom";
    "frosted-glass-theme.fakeMica.enabled" = true;
    "workbench.iconTheme" = "eq-material-theme-icons-palenight";

    # Misc
    "security.workspace.trust.enabled" = false;
    "typescript.format.insertSpaceAfterOpeningAndBeforeClosingNonemptyBrackets" = true;
    "github.copilot.nextEditSuggestions.enabled" = true;
    "claudeCode.selectedModel" = "default";
    "claudeCode.preferredLocation" = "panel";
  };

  keybindings = [
    {
      key = "alt+f";
      command = "editor.action.formatDocument";
      when = "editorHasDocumentFormattingProvider && editorTextFocus && !editorReadonly && !inCompositeEditor";
    }
    {
      key = "shift+alt+f";
      command = "-editor.action.formatDocument";
      when = "editorHasDocumentFormattingProvider && editorTextFocus && !editorReadonly && !inCompositeEditor";
    }
    {
      key = "shift+cmd+o";
      command = "editor.action.organizeImports";
      when = "editorTextFocus && !editorReadonly && supportedCodeAction =~ /(\\s|^)source\\.organizeImports\\b/";
    }
    {
      key = "shift+cmd+i";
      command = "editor.action.sourceAction";
      args = {
        kind = "source.addMissingImports";
        apply = "first";
      };
    }
  ];

  extensionInstallScript = lib.concatMapStringsSep "\n" (ext: "code --install-extension ${ext} --force") extensions;
in

{
  # VS Code settings (app installed via brew, config managed here)
  home.file."${settingsPath}/settings.json".text = builtins.toJSON settings;
  home.file."${settingsPath}/keybindings.json".text = builtins.toJSON keybindings;

  # Extension install script (run after clean install: vscode-install-extensions)
  home.file.".local/bin/vscode-install-extensions" = {
    text = ''
      #!/bin/sh
      # VS Code extensions managed by nix-darwin
      # Run this script after a clean install to restore extensions
      ${extensionInstallScript}
      echo "Done: ${toString (builtins.length extensions)} extensions installed"
    '';
    executable = true;
  };
}
