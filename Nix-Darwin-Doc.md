nix-darwin Configuration Options
Version 25.11.1dd19f1
\_module.args
Additional arguments passed to each module in addition to ones like lib, config, and pkgs, modulesPath.

This option is also available to all submodules. Submodules do not inherit args from their parent module, nor do they provide args to their parent module or sibling submodules. The sole exception to this is the argument name which is provided by parent modules to a submodule and contains the attribute name the submodule is bound to, or a unique generated name if it is not bound to an attribute.

Some arguments are already passed by default, of which the following cannot be changed with this option:

lib: The nixpkgs library.

config: The results of all options after merging the values from all modules together.

options: The options declared in all modules.

specialArgs: The specialArgs argument passed to evalModules.

All attributes of specialArgs

Whereas option values can generally depend on other option values thanks to laziness, this does not apply to imports, which must be computed statically before anything else.

For this reason, callers of the module system can provide specialArgs which are available during import resolution.

For NixOS, specialArgs includes modulesPath, which allows you to import extra modules from the nixpkgs package tree without having to somehow make the module aware of the location of the nixpkgs or NixOS directories.

{ modulesPath, ... }: {
imports = [
(modulesPath + "/profiles/minimal.nix")
];
}
For NixOS, the default value for this option includes at least this argument:

pkgs: The nixpkgs package set according to the nixpkgs.pkgs option.

Type: lazy attribute set of raw value

Declared by:

<nixpkgs/lib/modules.nix>
documentation.enable
Whether to install documentation of packages from environment.systemPackages into the generated system path.

See “Multiple-output packages” chapter in the nixpkgs manual for more info.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/documentation>
documentation.doc.enable
Whether to install documentation distributed in packages’ /share/doc. Usually plain text and/or HTML. This also includes “doc” outputs.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/documentation>
documentation.info.enable
Whether to install info pages and the info command. This also includes “info” outputs.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/documentation>
documentation.man.enable
Whether to install manual pages and the man command. This also includes “man” outputs.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/documentation>
environment.enableAllTerminfo
Whether to install all terminfo outputs

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/config/terminfo.nix>
environment.darwinConfig
The path of the darwin configuration.nix used to configure the system, this updates the default darwin-config entry in NIX_PATH. Since this changes an environment variable it will only apply to new shells.

NOTE: Changing this requires running darwin-rebuild switch -I darwin-config=/path/to/configuration.nix the first time to make darwin-rebuild aware of the custom location.

Type: null or absolute path or string

Default:

if config.nixpkgs.flake.setNixPath then

# Don’t set this for flake‐based systems.

null
else if config.system.stateVersion >= 6 then
"/etc/nix-darwin/configuration.nix"
else
"${config.system.primaryUserHome}/.nixpkgs/darwin-configuration.nix"

Declared by:

<nix-darwin/modules/environment>
environment.defaultPackages
Set of default packages that aren’t strictly necessary for a running system, entries can be removed for a more minimal NixOS installation.

Like with systemPackages, packages are installed to /run/current-system/sw. They are automatically available to all users, and are automatically updated every time you rebuild the system configuration.

Type: list of package

Default: these packages, with their meta.priority numerically increased (thus lowering their installation priority):

[ ]
Example: [ ]

Declared by:

<nix-darwin/modules/config/system-path.nix>
environment.etc
Set of files that have to be linked in /etc.

Type: attribute set of (submodule)

Default: { }

Declared by:

<nix-darwin/modules/system/etc.nix>
environment.etc.<name>.enable
Whether this file should be generated. This option allows specific files to be disabled.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/system/etc.nix>
environment.etc.<name>.source
Path of the source file.

Type: absolute path

Declared by:

<nix-darwin/modules/system/etc.nix>
environment.etc.<name>.target
Name of symlink. Defaults to the attribute name.

Type: string

Default: "‹name›"

Declared by:

<nix-darwin/modules/system/etc.nix>
environment.etc.<name>.text
Text of the file.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/system/etc.nix>
environment.extraInit
Shell script code called during global environment initialisation after all variables and profileVariables have been set. This code is asumed to be shell-independent, which means you should stick to pure sh without sh word split.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/environment>
environment.extraOutputsToInstall
Entries listed here will be appended to the meta.outputsToInstall attribute for each package in environment.systemPackages, and the files from the corresponding derivation outputs symlinked into /run/current-system/sw.

For example, this can be used to install the dev and info outputs for all packages in the system environment, if they are available.

To use specific outputs instead of configuring them globally, select the corresponding attribute on the package derivation, e.g. libxml2.dev or coreutils.info.

Type: list of string

Default: [ ]

Example:

[
"dev"
"info"
]
Declared by:

<nix-darwin/modules/config/system-path.nix>
environment.extraSetup
Shell fragments to be run after the system environment has been created. This should only be used for things that need to modify the internals of the environment, e.g. generating MIME caches. The environment being built can be accessed at $out.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/config/system-path.nix>
environment.interactiveShellInit
Shell script code called during interactive shell initialisation. This code is asumed to be shell-independent, which means you should stick to pure sh without sh word split.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/environment>
environment.launchAgents
Set of files that have to be linked in /Library/LaunchAgents.

Type: attribute set of (submodule)

Default: { }

Declared by:

<nix-darwin/modules/system/launchd.nix>
environment.launchAgents.<name>.enable
Whether this file should be generated. This option allows specific files to be disabled.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/system/launchd.nix>
environment.launchAgents.<name>.source
Path of the source file.

Type: absolute path

Declared by:

<nix-darwin/modules/system/launchd.nix>
environment.launchAgents.<name>.target
Name of symlink. Defaults to the attribute name.

Type: string

Default: "‹name›"

Declared by:

<nix-darwin/modules/system/launchd.nix>
environment.launchAgents.<name>.text
Text of the file.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/system/launchd.nix>
environment.launchDaemons
Set of files that have to be linked in /Library/LaunchDaemons.

Type: attribute set of (submodule)

Default: { }

Declared by:

<nix-darwin/modules/system/launchd.nix>
environment.launchDaemons.<name>.enable
Whether this file should be generated. This option allows specific files to be disabled.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/system/launchd.nix>
environment.launchDaemons.<name>.source
Path of the source file.

Type: absolute path

Declared by:

<nix-darwin/modules/system/launchd.nix>
environment.launchDaemons.<name>.target
Name of symlink. Defaults to the attribute name.

Type: string

Default: "‹name›"

Declared by:

<nix-darwin/modules/system/launchd.nix>
environment.launchDaemons.<name>.text
Text of the file.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/system/launchd.nix>
environment.loginShellInit
Shell script code called during login shell initialisation. This code is asumed to be shell-independent, which means you should stick to pure sh without sh word split.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/environment>
environment.pathsToLink
List of directories to be symlinked in /run/current-system/sw.

Type: list of string

Default: [ ]

Example:

[
"/share/doc"
]
Declared by:

<nix-darwin/modules/config/system-path.nix>
environment.profiles
A list of profiles used to setup the global environment.

Type: list of string

Declared by:

<nix-darwin/modules/environment>
environment.shellAliases
An attribute set that maps aliases (the top level attribute names in this option) to command strings or directly to build outputs. The alises are added to all users’ shells.

Type: attribute set of string

Default: { }

Example:

{
ll = "ls -l";
}
Declared by:

<nix-darwin/modules/environment>
environment.shellInit
Shell script code called during shell initialisation. This code is asumed to be shell-independent, which means you should stick to pure sh without sh word split.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/environment>
environment.shells
A list of permissible login shells for user accounts.

The default macOS shells will be automatically included:

/bin/bash

/bin/csh

/bin/dash

/bin/ksh

/bin/sh

/bin/tcsh

/bin/zsh

Type: list of (package or absolute path)

Default: [ ]

Example: [ pkgs.bashInteractive pkgs.zsh ]

Declared by:

<nix-darwin/modules/system/shells.nix>
environment.systemPackages
The set of packages that appear in /run/current-system/sw. These packages are automatically available to all users, and are automatically updated every time you rebuild the system configuration. (The latter is the main difference with installing them in the default profile, /nix/var/nix/profiles/default.

Type: list of package

Default: [ ]

Example: [ pkgs.firefox pkgs.thunderbird ]

Declared by:

<nix-darwin/modules/config/system-path.nix>
environment.systemPath
The set of paths that are added to PATH.

Type: list of (absolute path or string)

Declared by:

<nix-darwin/modules/config/system-path.nix>
environment.userLaunchAgents
Set of files that have to be linked in ~/Library/LaunchAgents.

Type: attribute set of (submodule)

Default: { }

Declared by:

<nix-darwin/modules/system/launchd.nix>
environment.userLaunchAgents.<name>.enable
Whether this file should be generated. This option allows specific files to be disabled.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/system/launchd.nix>
environment.userLaunchAgents.<name>.source
Path of the source file.

Type: absolute path

Declared by:

<nix-darwin/modules/system/launchd.nix>
environment.userLaunchAgents.<name>.target
Name of symlink. Defaults to the attribute name.

Type: string

Default: "‹name›"

Declared by:

<nix-darwin/modules/system/launchd.nix>
environment.userLaunchAgents.<name>.text
Text of the file.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/system/launchd.nix>
environment.variables
A set of environment variables used in the global environment. These variables will be set on shell initialisation. The value of each variable can be either a string or a list of strings. The latter is concatenated, interspersed with colon characters.

Type: attribute set of (string or list of string)

Default: { }

Example:

{
EDITOR = "vim";
LANG = "nl_NL.UTF-8";
}
Declared by:

<nix-darwin/modules/environment>
fonts.packages
List of fonts to install into /Library/Fonts/Nix Fonts.

Type: list of absolute path

Default: [ ]

Example: [ pkgs.dejavu_fonts ]

Declared by:

<nix-darwin/modules/fonts>
homebrew.enable
Whether to enable nix-darwin to manage installing/updating/upgrading Homebrew taps, formulae, and casks, as well as Mac App Store apps and Docker containers, using Homebrew Bundle.

Note that enabling this option does not install Homebrew, see the Homebrew website for installation instructions.

Use the homebrew.brews, homebrew.casks, homebrew.masApps, and homebrew.whalebrews options to list the Homebrew formulae, casks, Mac App Store apps, and Docker containers you’d like to install. Use the homebrew.taps option, to make additional formula repositories available to Homebrew. This module uses those options (along with the homebrew.caskArgs options) to generate a Brewfile that nix-darwin passes to the brew bundle command during system activation.

The default configuration of this module prevents Homebrew Bundle from auto-updating Homebrew and all formulae, as well as upgrading anything that’s already installed, so that repeated invocations of darwin-rebuild switch (without any change to the configuration) are idempotent. You can modify this behavior using the options under homebrew.onActivation.

This module also provides a few options for modifying how Homebrew commands behave when you manually invoke them, under homebrew.global.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.brewPrefix
The path prefix where the brew executable is located. This will be set to the correct value based on your system’s platform, and should only need to be changed if you manually installed Homebrew in a non-standard location.

Type: string

Default:

if pkgs.stdenv.hostPlatform.isAarch64 then "/opt/homebrew/bin"
else "/usr/local/bin"

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.brews
List of Homebrew formulae to install.

Formulae defined as strings, e.g., "imagemagick", are a shorthand for:

{ name = "imagemagick"; }

Type: list of ((submodule) or string convertible to it)

Default: [ ]

Example:

# Adapted from https://docs.brew.sh/Brew-Bundle-and-Brewfile

[

# `brew install`

"imagemagick"

# `brew install --with-rmtp`, `brew services restart` on version changes

{
name = "denji/nginx/nginx-full";
args = [ "with-rmtp" ];
restart_service = "changed";
}

# `brew install`, always `brew services restart`, `brew link`, `brew unlink mysql` (if it is installed)

{
name = "mysql@5.6";
restart_service = true;
link = true;
conflicts_with = [ "mysql" ];
}
]

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.brews.\*.args
Arguments flags to pass to brew install. Values should not include the leading "--".

Type: null or (list of string)

Default: null

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.brews.\*.conflicts_with
List of formulae that should be unlinked and their services stopped (if they are installed).

Type: null or (list of string)

Default: null

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.brews.\*.link
Whether to link the formula to the Homebrew prefix. When this option is null, Homebrew will use it’s default behavior which is to link the formula if it’s currently unlinked and not keg-only, and to unlink the formula if it’s currently linked and keg-only.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.brews.\*.name
The name of the formula to install.

Type: string

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.brews.\*.restart_service
Whether to run brew services restart for the formula and register it to launch at login (or boot). If set to "changed", the service will only be restarted on version changes.

Homebrew’s default is false.

Type: null or boolean or value “changed” (singular enum)

Default: null

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.brews.\*.start_service
Whether to run brew services start for the formula and register it to launch at login (or boot).

Homebrew’s default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.caskArgs
Arguments passed to brew install --cask for all casks listed in homebrew.casks.

Type: submodule

Default: { }

Example:

{
appdir = "~/Applications";
require_sha = true;
}

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.caskArgs.appdir
Target location for Applications.

Homebrew’s default is /Applications.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.caskArgs.audio_unit_plugindir
Target location for Audio Unit Plugins.

Homebrew’s default is ~/Library/Audio/Plug-Ins/Components.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.caskArgs.colorpickerdir
Target location for Color Pickers.

Homebrew’s default is ~/Library/ColorPickers.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.caskArgs.dictionarydir
Target location for Dictionaries.

Homebrew’s default is ~/Library/Dictionaries.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.caskArgs.fontdir
Target location for Fonts.

Homebrew’s default is ~/Library/Fonts.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.caskArgs.ignore_dependencies
Ignore casks dependencies in case you manage them extrenally

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.caskArgs.input_methoddir
Target location for Input Methods.

Homebrew’s default is ~/Library/Input Methods.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.caskArgs.internet_plugindir
Target location for Internet Plugins.

Homebrew’s default is ~/Library/Internet Plug-Ins.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.caskArgs.language
Comma-separated list of language codes to prefer for cask installation. The first matching language is used, otherwise it reverts to the cask’s default language. The default value is the language of your system.

Type: null or string

Default: null

Example: "zh-TW"

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.caskArgs.mdimporterdir
Target location for Spotlight Plugins.

Homebrew’s default is ~/Library/Spotlight.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.caskArgs.no_binaries
Whether to disable linking of helper executables.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.caskArgs.no_quarantine
Whether to disable quarantining of downloads.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.caskArgs.prefpanedir
Target location for Preference Panes.

Homebrew’s default is ~/Library/PreferencePanes.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.caskArgs.qlplugindir
Target location for QuickLook Plugins.

Homebrew’s default is ~/Library/QuickLook.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.caskArgs.require_sha
Whether to require cask(s) to have a checksum.

Homebrew’s default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.caskArgs.screen_saverdir
Target location for Screen Savers.

Homebrew’s default is ~/Library/Screen Savers.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.caskArgs.servicedir
Target location for Services.

Homebrew’s default is ~/Library/Services.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.caskArgs.vst3_plugindir
Target location for VST3 Plugins.

Homebrew’s default is ~/Library/Audio/Plug-Ins/VST3.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.caskArgs.vst_plugindir
Target location for VST Plugins.

Homebrew’s default is ~/Library/Audio/Plug-Ins/VST.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.casks
List of Homebrew casks to install.

Casks defined as strings, e.g., "google-chrome", are a shorthand for:

{ name = "google-chrome"; }

Type: list of ((submodule) or string convertible to it)

Default: [ ]

Example:

# Adapted from https://docs.brew.sh/Brew-Bundle-and-Brewfile

[

# `brew install --cask`

"google-chrome"

# `brew install --cask --appdir=~/my-apps/Applications`

{
name = "firefox";
args = { appdir = "~/my-apps/Applications"; };
}

# always upgrade auto-updated or unversioned cask to latest version even if already installed

{
name = "opera";
greedy = true;
}
]

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.casks.\*.args
Arguments passed to brew install --cask when installing this cask. See homebrew.caskArgs for the available options.

Type: null or (submodule)

Default: null

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.casks.\*.greedy
Whether to always upgrade this cask regardless of whether it’s unversioned or it updates itself.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.casks.\*.name
The name of the cask to install.

Type: string

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.extraConfig
Extra lines to be added verbatim to the bottom of the generated Brewfile.

Type: strings concatenated with “\n”

Default: ""

Example:

''

# 'brew cask install' only if '/usr/libexec/java_home --failfast' fails

cask "java" unless system "/usr/libexec/java_home --failfast"
''
Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.global
Options for configuring the behavior of Homebrew commands when you manually invoke them.

Type: submodule

Default: { }

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.global.autoUpdate
Whether to enable Homebrew to auto-update itself and all formulae when you manually invoke commands like brew install, brew upgrade, brew tap, and brew bundle [install].

Note that Homebrew auto-updates when you manually invoke commands like the ones mentioned above if it’s been more then 5 minutes since it last updated.

You may want to consider disabling this option if you have homebrew.onActivation.upgrade enabled, and homebrew.onActivation.autoUpdate disabled, if you want to ensure that your installed formulae will only be upgraded during nix-darwin system activation, after you’ve explicitly run brew update.

Implementation note: when disabled, this option sets the HOMEBREW_NO_AUTO_UPDATE environment variable, by adding it to environment.variables.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.global.brewfile
Whether to enable Homebrew to automatically use the Brewfile that this module generates in the Nix store, when you manually invoke brew bundle.

Enabling this option will change the default value of homebrew.global.lockfiles to false since, with this option enabled, brew bundle [install] will default to using the Brewfile that this module generates in the Nix store, unless you explicitly point it at another Brewfile using the --file flag. As a result, it will try to write the lockfile in the Nix store, and complain that it can’t (though the command will run successfully regardless).

Implementation note: when enabled, this option sets the HOMEBREW_BUNDLE_FILE environment variable to the path of the Brewfile that this module generates in the Nix store, by adding it to environment.variables.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.global.lockfiles
Whether to enable Homebrew to generate lockfiles when you manually invoke brew bundle [install].

This option will default to false if homebrew.global.brewfile is enabled since, with that option enabled, brew bundle [install] will default to using the Brewfile that this module generates in the Nix store, unless you explicitly point it at another Brewfile using the --file flag. As a result, it will try to write the lockfile in the Nix store, and complain that it can’t (though the command will run successfully regardless).

Implementation note: when disabled, this option sets the HOMEBREW_BUNDLE_NO_LOCK environment variable, by adding it to environment.variables.

Type: boolean

Default: !config.homebrew.global.brewfile

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.greedyCasks
Whether to always upgrade casks listed in homebrew.casks regardless of whether it’s unversioned or it updates itself.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.masApps
Applications to install from Mac App Store using mas.

Note that you need to be signed into the Mac App Store for mas to successfully install and upgrade applications, and that unfortunately apps removed from this option will not be uninstalled automatically even if homebrew.onActivation.cleanup is set to "uninstall" or "zap" (this is currently a limitation of Homebrew Bundle).

For more information on mas see: github.com/mas-cli/mas.

Type: attribute set of (positive integer, meaning >0)

Default: { }

Example:

{
"1Password for Safari" = 1569813296;
Xcode = 497799835;
}

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.onActivation
Options for configuring the behavior of the brew bundle command that nix-darwin runs during system activation.

Type: submodule

Default: { }

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.onActivation.autoUpdate
Whether to enable Homebrew to auto-update itself and all formulae during nix-darwin system activation. The default is false so that repeated invocations of darwin-rebuild switch are idempotent.

Note that Homebrew auto-updates when it’s been more then 5 minutes since it last updated.

Although auto-updating is disabled by default during system activation, note that Homebrew will auto-update when you manually invoke certain Homebrew commands. To modify this behavior see homebrew.global.autoUpdate.

Implementation note: when disabled, this option sets the HOMEBREW_NO_AUTO_UPDATE environment variable when nix-darwin invokes brew bundle [install] during system activation.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.onActivation.cleanup
This option manages what happens to formulae installed by Homebrew, that aren’t present in the Brewfile generated by this module, during nix-darwin system activation.

When set to "none" (the default), formulae not present in the generated Brewfile are left installed.

When set to "uninstall", nix-darwin invokes brew bundle [install] with the --cleanup flag. This uninstalls all formulae not listed in generated Brewfile, i.e., brew uninstall is run for those formulae.

When set to "zap", nix-darwin invokes brew bundle [install] with the --cleanup --zap flags. This uninstalls all formulae not listed in the generated Brewfile, and if the formula is a cask, removes all files associated with that cask. In other words, brew uninstall --zap is run for all those formulae.

If you plan on exclusively using nix-darwin to manage formulae installed by Homebrew, you probably want to set this option to "uninstall" or "zap".

Type: one of “none”, “uninstall”, “zap”

Default: "none"

Example: "uninstall"

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.onActivation.extraFlags
Extra flags to pass to brew bundle [install] during nix-darwin system activation.

Type: list of string

Default: [ ]

Example:

[
"--verbose"
]
Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.onActivation.upgrade
Whether to enable Homebrew to upgrade outdated formulae and Mac App Store apps during nix-darwin system activation. The default is false so that repeated invocations of darwin-rebuild switch are idempotent.

Implementation note: when disabled, nix-darwin invokes brew bundle [install] with the --no-upgrade flag during system activation.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.taps
List of Homebrew formula repositories to tap.

Taps defined as strings, e.g., "user/repo", are a shorthand for:

{ name = "user/repo"; }

Type: list of ((submodule) or string convertible to it)

Default: [ ]

Example:

# Adapted from https://docs.brew.sh/Brew-Bundle-and-Brewfile

[

# `brew tap`

"apple/apple"

# `brew tap` with custom Git URL and arguments

{
name = "user/tap-repo";
clone_target = "https://user@bitbucket.org/user/homebrew-tap-repo.git";
force_auto_update = true;
}
]

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.taps.\*.clone_target
Use this option to tap a formula repository from anywhere, using any transport protocol that git handles. When clone_target is specified, taps can be cloned from places other than GitHub and using protocols other than HTTPS, e.g., SSH, git, HTTP, FTP(S), rsync.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.taps.\*.force_auto_update
Whether to auto-update the tap even if it is not hosted on GitHub. By default, only taps hosted on GitHub are auto-updated (for performance reasons).

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.taps.\*.name
When clone_target is unspecified, this is the name of a formula repository to tap from GitHub using HTTPS. For example, "user/repo" will tap https://github.com/user/homebrew-repo.

Type: string

Example: "apple/apple"

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.user
The user that owns the Homebrew installation. In most cases this should be the normal user account that you installed Homebrew as.

Type: string

Default: config.system.primaryUser

Declared by:

<nix-darwin/modules/homebrew.nix>
homebrew.whalebrews
List of Docker images to install using whalebrew.

When this option is used, "whalebrew" is automatically added to homebrew.brews.

For more information on whalebrew see: github.com/whalebrew/whalebrew.

Type: list of string

Default: [ ]

Example:

[
"whalebrew/wget"
]
Declared by:

<nix-darwin/modules/homebrew.nix>
launchd.agents
Definition of per-user launchd agents.

When a user logs in, a per-user launchd is started. It does the following:

It loads the parameters for each launch-on-demand user agent from the property list files found in /System/Library/LaunchAgents, /Library/LaunchAgents, and the user’s individual Library/LaunchAgents directory.

It registers the sockets and file descriptors requested by those user agents.

It launches any user agents that requested to be running all the time.

As requests for a particular service arrive, it launches the corresponding user agent and passes the request to it.

When the user logs out, it sends a SIGTERM signal to all of the user agents that it started.

Type: attribute set of (submodule)

Default: { }

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.command
Command executed as the service’s main process.

Type: string or absolute path

Default: ""

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.environment
Environment variables passed to the service’s processes.

Type: attribute set of (string or list of string)

Default: { }

Example:

{
LANG = "nl_NL.UTF-8";
PATH = "/foo/bar/bin";
}
Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.path
Packages added to the service’s PATH environment variable. Only the bin and subdirectories of each package is added.

Type: list of (absolute path or string)

Default: [ ]

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.script
Shell commands executed as the service’s main process.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig
Each attribute in this set specifies an option for a key in the plist. https://developer.apple.com/legacy/library/documentation/Darwin/Reference/ManPages/man5/launchd.plist.5.html

Type: submodule

Default: { }

Example:

{
KeepAlive = true;
Program = "/run/current-system/sw/bin/nix-daemon";
}
Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.AbandonProcessGroup
When a job dies, launchd kills any remaining processes with the same process group ID as the job. Setting this key to true disables that behavior.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.Debug
This optional key specifies that launchd should adjust its log mask temporarily to LOG_DEBUG while dealing with this job.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.Disabled
This optional key is used as a hint to launchctl(1) that it should not submit this job to launchd when loading a job or jobs. The value of this key does NOT reflect the current state of the job on the running system. If you wish to know whether a job is loaded in launchd, reading this key from a configuration file yourself is not a sufficient test. You should query launchd for the presence of the job using the launchctl(1) list subcommand or use the ServiceManagement framework’s SMJobCopyDictionary() method.

Note that as of Mac OS X v10.6, this key’s value in a configuration file conveys a default value, which is changed with the [-w] option of the launchctl(1) load and unload subcommands. These subcommands no longer modify the configuration file, so the value displayed in the configuration file is not necessarily the value that launchctl(1) will apply. See launchctl(1) for more information.

Please also be mindful that you should only use this key if the provided on-demand and KeepAlive criteria are insufficient to describe the conditions under which your job needs to run. The cost to have a job loaded in launchd is negligible, so there is no harm in loading a job which only runs once or very rarely.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.EnableGlobbing
This flag causes launchd to use the glob(3) mechanism to update the program arguments before invocation.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.EnableTransactions
This flag instructs launchd that the job promises to use vproc_transaction_begin(3) and vproc_transaction_end(3) to track outstanding transactions that need to be reconciled before the process can safely terminate. If no outstanding transactions are in progress, then launchd is free to send the SIGKILL signal.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.EnvironmentVariables
This optional key is used to specify additional environment variables to be set before running the job.

Type: null or (attribute set of string)

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.ExitTimeOut
The amount of time launchd waits before sending a SIGKILL signal. The default value is 20 seconds. The value zero is interpreted as infinity.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.GroupName
This optional key specifies the group to run the job as. This key is only applicable when launchd is running as root. If UserName is set and GroupName is not, the the group will be set to the default group of the user.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.HardResourceLimits
Resource limits to be imposed on the job. These adjust variables set with setrlimit(2). The following keys apply:

Type: null or (submodule)

Default: null

Example:

{
NumberOfFiles = 4096;
}
Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.HardResourceLimits.CPU
The maximum amount of cpu time (in seconds) to be used by each process.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.HardResourceLimits.Core
The largest size (in bytes) core file that may be created.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.HardResourceLimits.Data
The maximum size (in bytes) of the data segment for a process; this defines how far a program may extend its break with the sbrk(2) system call.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.HardResourceLimits.FileSize
The largest size (in bytes) file that may be created.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.HardResourceLimits.MemoryLock
The maximum size (in bytes) which a process may lock into memory using the mlock(2) function.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.HardResourceLimits.NumberOfFiles
The maximum number of open files for this process. Setting this value in a system wide daemon will set the sysctl(3) kern.maxfiles (SoftResourceLimits) or kern.maxfilesperproc (HardResourceLimits) value in addition to the setrlimit(2) values.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.HardResourceLimits.NumberOfProcesses
The maximum number of simultaneous processes for this user id. Setting this value in a system wide daemon will set the sysctl(3) kern.maxproc (SoftResourceLimits) or kern.maxprocperuid (HardResourceLimits) value in addition to the setrlimit(2) values.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.HardResourceLimits.ResidentSetSize
The maximum size (in bytes) to which a process’s resident set size may grow. This imposes a limit on the amount of physical memory to be given to a process; if memory is tight, the system will prefer to take memory from processes that are exceeding their declared resident set size.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.HardResourceLimits.Stack
The maximum size (in bytes) of the stack segment for a process; this defines how far a program’s stack segment may be extended. Stack extension is performed automatically by the system.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.InitGroups
This optional key specifies whether initgroups(3) should be called before running the job. The default is true in 10.5 and false in 10.4. This key will be ignored if the UserName key is not set.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.KeepAlive
This optional key is used to control whether your job is to be kept continuously running or to let demand and conditions control the invocation. The default is false and therefore only demand will start the job. The value may be set to true to unconditionally keep the job alive. Alternatively, a dictionary of conditions may be specified to selectively control whether launchd keeps a job alive or not. If multiple keys are provided, launchd ORs them, thus providing maximum flexibility to the job to refine the logic and stall if necessary. If launchd finds no reason to restart the job, it falls back on demand based invocation. Jobs that exit quickly and frequently when configured to be kept alive will be throttled to converve system resources.

Type: null or boolean or (submodule)

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.Label
This required key uniquely identifies the job to launchd.

Type: string

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.LaunchEvents
Specifies higher-level event types to be used as launch-on-demand event sources. Each sub-dictionary defines events for a particular event subsystem, such as “com.apple.iokit.matching”, which can be used to launch jobs based on the appearance of nodes in the IORegistry. Each dictionary within the sub-dictionary specifies an event descriptor that is specified to each event subsystem. With this key, the job promises to use the xpc_set_event_stream_handler(3) API to consume events. See xpc_events(3) for more details on event sources.

Type: null or (attribute set)

Default: null

Example:

{
"com.apple.iokit.matching" = {
"com.apple.usb.device" = {
IOMatchLaunchStream = true;
IOProviderClass = "IOUSBDevice";
idProduct = "_";
idVendor = "_";
};
};
}
Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.LaunchOnlyOnce
This optional key specifies whether the job can only be run once and only once. In other words, if the job cannot be safely respawned without a full machine reboot, then set this key to be true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.LimitLoadFromHosts
This configuration file only applies to hosts NOT listed with this key. Note: One should set kern.hostname in sysctl.conf(5) for this feature to work reliably.

Type: null or (list of string)

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.LimitLoadToHosts
This configuration file only applies to the hosts listed with this key. Note: One should set kern.hostname in sysctl.conf(5) for this feature to work reliably.

Type: null or (list of string)

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.LimitLoadToSessionType
This configuration file only applies to sessions of the type specified. This key is used in concert with the -S flag to launchctl.

Type: null or string or list of string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.LowPriorityBackgroundIO
This optional key specifies whether the kernel should consider this daemon to be low priority when doing file system I/O when the process is throttled with the Darwin-background classification.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.LowPriorityIO
This optional key specifies whether the kernel should consider this daemon to be low priority when doing file system I/O.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.MachServices
This optional key is used to specify Mach services to be registered with the Mach bootstrap sub-system. Each key in this dictionary should be the name of service to be advertised. The value of the key must be a boolean and set to true. Alternatively, a dictionary can be used instead of a simple true value.

Finally, for the job itself, the values will be replaced with Mach ports at the time of check-in with launchd.

Type: null or (attribute set of (boolean or (submodule)))

Default: null

Example:

{
"org.nixos.service" = {
ResetAtClose = true;
};
}
Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.Nice
This optional key specifies what nice(3) value should be applied to the daemon.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.OnDemand
This key was used in Mac OS X 10.4 to control whether a job was kept alive or not. The default was true. This key has been deprecated and replaced in Mac OS X 10.5 and later with the more powerful KeepAlive option.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.ProcessType
This optional key describes, at a high level, the intended purpose of the job. The system will apply resource limits based on what kind of job it is. If left unspecified, the system will apply light resource limits to the job, throttling its CPU usage and I/O bandwidth. The following are valid values:

Background
Background jobs are generally processes that do work that was not directly requested by the user. The resource limits applied to Background jobs are intended to prevent them from disrupting the user experience.

Standard
Standard jobs are equivalent to no ProcessType being set.

Adaptive
Adaptive jobs move between the Background and Interactive classifications based on activity over XPC connections. See xpc_transaction_begin(3) for details.

Interactive
Interactive jobs run with the same resource limitations as apps, that is to say, none. Interactive jobs are critical to maintaining a responsive user experience, and this key should only be used if an app’s ability to be responsive depends on it, and cannot be made Adaptive.

Type: null or one of “Background”, “Standard”, “Adaptive”, “Interactive”

Default: null

Example: "Background"

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.Program
This key maps to the first argument of execvp(3). If this key is missing, then the first element of the array of strings provided to the ProgramArguments will be used instead. This key is required in the absence of the ProgramArguments key.

Type: null or absolute path

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.ProgramArguments
This key maps to the second argument of execvp(3). This key is required in the absence of the Program key. Please note: many people are confused by this key. Please read execvp(3) very carefully!

Type: null or (list of string)

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.QueueDirectories
Much like the WatchPaths option, this key will watch the paths for modifications. The difference being that the job will only be started if the path is a directory and the directory is not empty.

Type: null or (list of string)

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.RootDirectory
This optional key is used to specify a directory to chroot(2) to before running the job.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.RunAtLoad
This optional key is used to control whether your job is launched once at the time the job is loaded. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.ServiceIPC
This optional key specifies whether the job participates in advanced communication with launchd. The default is false. This flag is incompatible with the inetdCompatibility key.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.SessionCreate
This key specifies that the job should be spawned into a new security audit session rather than the default session for the context is belongs to. See auditon(2) for details.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.Sockets
This optional key is used to specify launch on demand sockets that can be used to let launchd know when to run the job. The job must check-in to get a copy of the file descriptors using APIs outlined in launch(3). The keys of the top level Sockets dictionary can be anything. They are meant for the application developer to use to differentiate which descriptors correspond to which application level protocols (e.g. http vs. ftp vs. DNS…). At check-in time, the value of each Sockets dictionary key will be an array of descriptors. Daemon/Agent writers should consider all descriptors of a given key to be to be effectively equivalent, even though each file descriptor likely represents a different networking protocol which conforms to the criteria specified in the job configuration file.

The parameters below are used as inputs to call getaddrinfo(3).

Type: null or (attribute set of (submodule))

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.Sockets.<name>.Bonjour
This optional key can be used to request that the service be registered with the mDNSResponder(8). If the value is boolean, the service name is inferred from the SockServiceName.

Type: null or boolean or list of string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.Sockets.<name>.MulticastGroup
This optional key can be used to request that the datagram socket join a multicast group. If the value is a hostname, then getaddrinfo(3) will be used to join the correct multicast address for a given socket family. If an explicit IPv4 or IPv6 address is given, it is required that the SockFamily family also be set, otherwise the results are undefined.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.Sockets.<name>.SecureSocketWithKey
This optional key is a variant of SockPathName. Instead of binding to a known path, a securely generated socket is created and the path is assigned to the environment variable that is inherited by all jobs spawned by launchd.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.Sockets.<name>.SockFamily
This optional key can be used to specifically request that “IPv4” or “IPv6” socket(s) be created.

Type: null or one of “IPv4”, “IPv6”

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.Sockets.<name>.SockNodeName
This optional key specifies the node to connect(2) or bind(2) to.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.Sockets.<name>.SockPassive
This optional key specifies whether listen(2) or connect(2) should be called on the created file descriptor. The default is true (“to listen”).

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.Sockets.<name>.SockPathMode
This optional key specifies the mode of the socket. Known bug: Property lists don’t support octal, so please convert the value to decimal.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.Sockets.<name>.SockPathName
This optional key implies SockFamily is set to “Unix”. It specifies the path to connect(2) or bind(2) to.

Type: null or absolute path

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.Sockets.<name>.SockProtocol
This optional key specifies the protocol to be passed to socket(2). The only value understood by this key at the moment is “TCP”.

Type: null or value “TCP” (singular enum)

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.Sockets.<name>.SockServiceName
This optional key specifies the service on the node to connect(2) or bind(2) to.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.Sockets.<name>.SockType
This optional key tells launchctl what type of socket to create. The default is “stream” and other valid values for this key are “dgram” and “seqpacket” respectively.

Type: null or one of “stream”, “dgram”, “seqpacket”

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.SoftResourceLimits
Resource limits to be imposed on the job. These adjust variables set with setrlimit(2). The following keys apply:

Type: null or (submodule)

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.SoftResourceLimits.CPU
The maximum amount of cpu time (in seconds) to be used by each process.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.SoftResourceLimits.Core
The largest size (in bytes) core file that may be created.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.SoftResourceLimits.Data
The maximum size (in bytes) of the data segment for a process; this defines how far a program may extend its break with the sbrk(2) system call.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.SoftResourceLimits.FileSize
The largest size (in bytes) file that may be created.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.SoftResourceLimits.MemoryLock
The maximum size (in bytes) which a process may lock into memory using the mlock(2) function.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.SoftResourceLimits.NumberOfFiles
The maximum number of open files for this process. Setting this value in a system wide daemon will set the sysctl(3) kern.maxfiles (SoftResourceLimits) or kern.maxfilesperproc (HardResourceLimits) value in addition to the setrlimit(2) values.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.SoftResourceLimits.NumberOfProcesses
The maximum number of simultaneous processes for this user id. Setting this value in a system wide daemon will set the sysctl(3) kern.maxproc (SoftResourceLimits) or kern.maxprocperuid (HardResourceLimits) value in addition to the setrlimit(2) values.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.SoftResourceLimits.ResidentSetSize
The maximum size (in bytes) to which a process’s resident set size may grow. This imposes a limit on the amount of physical memory to be given to a process; if memory is tight, the system will prefer to take memory from processes that are exceeding their declared resident set size.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.SoftResourceLimits.Stack
The maximum size (in bytes) of the stack segment for a process; this defines how far a program’s stack segment may be extended. Stack extension is performed automatically by the system.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.StandardErrorPath
This optional key specifies what file should be used for data being sent to stderr when using stdio(3).

Type: null or absolute path

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.StandardInPath
This optional key specifies what file should be used for data being supplied to stdin when using stdio(3).

Type: null or absolute path

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.StandardOutPath
This optional key specifies what file should be used for data being sent to stdout when using stdio(3).

Type: null or absolute path

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.StartCalendarInterval
This optional key causes the job to be started every calendar interval as specified. The semantics are much like crontab(5): Missing attributes are considered to be wildcard. Unlike cron which skips job invocations when the computer is asleep, launchd will start the job the next time the computer wakes up. If multiple intervals transpire before the computer is woken, those events will be coalesced into one event upon waking from sleep.

Important
The list must not be empty and must not contain duplicate entries (attrsets which compare equally).

Caution
Since missing attrs become wildcards, an empty attrset effectively means “every minute”.

Type: null or (submodule) or unique (non-empty (list of (submodule)))

Default: null

Example:

[
{
Hour = 2;
Minute = 30;
}
]
Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.StartInterval
This optional key causes the job to be started every N seconds. If the system is asleep, the job will be started the next time the computer wakes up. If multiple intervals transpire before the computer is woken, those events will be coalesced into one event upon wake from sleep.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.StartOnMount
This optional key causes the job to be started every time a filesystem is mounted.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.ThrottleInterval
This key lets one override the default throttling policy imposed on jobs by launchd. The value is in seconds, and by default, jobs will not be spawned more than once every 10 seconds. The principle behind this is that jobs should linger around just in case they are needed again in the near future. This not only reduces the latency of responses, but it encourages developers to amortize the cost of program invocation.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.TimeOut
The recommended idle time out (in seconds) to pass to the job. If no value is specified, a default time out will be supplied by launchd for use by the job at check in time.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.Umask
This optional key specifies what value should be passed to umask(2) before running the job. Known bug: Property lists don’t support octal, so please convert the value to decimal.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.UserName
This optional key specifies the user to run the job as. This key is only applicable when launchd is running as root.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.WaitForDebugger
This optional key specifies that launchd should instruct the kernel to have the job wait for a debugger to attach before any code in the job is executed.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.WatchPaths
This optional key causes the job to be started if any one of the listed paths are modified.

Type: null or (list of absolute path)

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.WorkingDirectory
This optional key is used to specify a directory to chdir(2) to before running the job.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.inetdCompatibility
The presence of this key specifies that the daemon expects to be run as if it were launched from inetd.

Type: null or (submodule)

Default: null

Example:

{
Wait = true;
}
Declared by:

<nix-darwin/modules/launchd>
launchd.agents.<name>.serviceConfig.inetdCompatibility.Wait
This flag corresponds to the “wait” or “nowait” option of inetd. If true, then the listening socket is passed via the standard in/out/error file descriptors. If false, then accept(2) is called on behalf of the job, and the result is passed via the standard in/out/error descriptors.

Type: null or boolean or string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons
Definition of launchd daemons.

After the system is booted and the kernel is running, launchd is run to finish the system initialization. As part of that initialization, it goes through the following steps:

It loads the parameters for each launch-on-demand system-level daemon from the property list files found in /System/Library/LaunchDaemons/ and /Library/LaunchDaemons/.

It registers the sockets and file descriptors requested by those daemons.

It launches any daemons that requested to be running all the time.

As requests for a particular service arrive, it launches the corresponding daemon and passes the request to it.

When the system shuts down, it sends a SIGTERM signal to all of the daemons that it started.

Type: attribute set of (submodule)

Default: { }

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.command
Command executed as the service’s main process.

Type: string or absolute path

Default: ""

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.environment
Environment variables passed to the service’s processes.

Type: attribute set of (string or list of string)

Default: { }

Example:

{
LANG = "nl_NL.UTF-8";
PATH = "/foo/bar/bin";
}
Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.path
Packages added to the service’s PATH environment variable. Only the bin and subdirectories of each package is added.

Type: list of (absolute path or string)

Default: [ ]

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.script
Shell commands executed as the service’s main process.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig
Each attribute in this set specifies an option for a key in the plist. https://developer.apple.com/legacy/library/documentation/Darwin/Reference/ManPages/man5/launchd.plist.5.html

Type: submodule

Default: { }

Example:

{
KeepAlive = true;
Program = "/run/current-system/sw/bin/nix-daemon";
}
Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.AbandonProcessGroup
When a job dies, launchd kills any remaining processes with the same process group ID as the job. Setting this key to true disables that behavior.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.Debug
This optional key specifies that launchd should adjust its log mask temporarily to LOG_DEBUG while dealing with this job.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.Disabled
This optional key is used as a hint to launchctl(1) that it should not submit this job to launchd when loading a job or jobs. The value of this key does NOT reflect the current state of the job on the running system. If you wish to know whether a job is loaded in launchd, reading this key from a configuration file yourself is not a sufficient test. You should query launchd for the presence of the job using the launchctl(1) list subcommand or use the ServiceManagement framework’s SMJobCopyDictionary() method.

Note that as of Mac OS X v10.6, this key’s value in a configuration file conveys a default value, which is changed with the [-w] option of the launchctl(1) load and unload subcommands. These subcommands no longer modify the configuration file, so the value displayed in the configuration file is not necessarily the value that launchctl(1) will apply. See launchctl(1) for more information.

Please also be mindful that you should only use this key if the provided on-demand and KeepAlive criteria are insufficient to describe the conditions under which your job needs to run. The cost to have a job loaded in launchd is negligible, so there is no harm in loading a job which only runs once or very rarely.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.EnableGlobbing
This flag causes launchd to use the glob(3) mechanism to update the program arguments before invocation.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.EnableTransactions
This flag instructs launchd that the job promises to use vproc_transaction_begin(3) and vproc_transaction_end(3) to track outstanding transactions that need to be reconciled before the process can safely terminate. If no outstanding transactions are in progress, then launchd is free to send the SIGKILL signal.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.EnvironmentVariables
This optional key is used to specify additional environment variables to be set before running the job.

Type: null or (attribute set of string)

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.ExitTimeOut
The amount of time launchd waits before sending a SIGKILL signal. The default value is 20 seconds. The value zero is interpreted as infinity.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.GroupName
This optional key specifies the group to run the job as. This key is only applicable when launchd is running as root. If UserName is set and GroupName is not, the the group will be set to the default group of the user.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.HardResourceLimits
Resource limits to be imposed on the job. These adjust variables set with setrlimit(2). The following keys apply:

Type: null or (submodule)

Default: null

Example:

{
NumberOfFiles = 4096;
}
Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.HardResourceLimits.CPU
The maximum amount of cpu time (in seconds) to be used by each process.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.HardResourceLimits.Core
The largest size (in bytes) core file that may be created.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.HardResourceLimits.Data
The maximum size (in bytes) of the data segment for a process; this defines how far a program may extend its break with the sbrk(2) system call.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.HardResourceLimits.FileSize
The largest size (in bytes) file that may be created.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.HardResourceLimits.MemoryLock
The maximum size (in bytes) which a process may lock into memory using the mlock(2) function.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.HardResourceLimits.NumberOfFiles
The maximum number of open files for this process. Setting this value in a system wide daemon will set the sysctl(3) kern.maxfiles (SoftResourceLimits) or kern.maxfilesperproc (HardResourceLimits) value in addition to the setrlimit(2) values.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.HardResourceLimits.NumberOfProcesses
The maximum number of simultaneous processes for this user id. Setting this value in a system wide daemon will set the sysctl(3) kern.maxproc (SoftResourceLimits) or kern.maxprocperuid (HardResourceLimits) value in addition to the setrlimit(2) values.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.HardResourceLimits.ResidentSetSize
The maximum size (in bytes) to which a process’s resident set size may grow. This imposes a limit on the amount of physical memory to be given to a process; if memory is tight, the system will prefer to take memory from processes that are exceeding their declared resident set size.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.HardResourceLimits.Stack
The maximum size (in bytes) of the stack segment for a process; this defines how far a program’s stack segment may be extended. Stack extension is performed automatically by the system.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.InitGroups
This optional key specifies whether initgroups(3) should be called before running the job. The default is true in 10.5 and false in 10.4. This key will be ignored if the UserName key is not set.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.KeepAlive
This optional key is used to control whether your job is to be kept continuously running or to let demand and conditions control the invocation. The default is false and therefore only demand will start the job. The value may be set to true to unconditionally keep the job alive. Alternatively, a dictionary of conditions may be specified to selectively control whether launchd keeps a job alive or not. If multiple keys are provided, launchd ORs them, thus providing maximum flexibility to the job to refine the logic and stall if necessary. If launchd finds no reason to restart the job, it falls back on demand based invocation. Jobs that exit quickly and frequently when configured to be kept alive will be throttled to converve system resources.

Type: null or boolean or (submodule)

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.Label
This required key uniquely identifies the job to launchd.

Type: string

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.LaunchEvents
Specifies higher-level event types to be used as launch-on-demand event sources. Each sub-dictionary defines events for a particular event subsystem, such as “com.apple.iokit.matching”, which can be used to launch jobs based on the appearance of nodes in the IORegistry. Each dictionary within the sub-dictionary specifies an event descriptor that is specified to each event subsystem. With this key, the job promises to use the xpc_set_event_stream_handler(3) API to consume events. See xpc_events(3) for more details on event sources.

Type: null or (attribute set)

Default: null

Example:

{
"com.apple.iokit.matching" = {
"com.apple.usb.device" = {
IOMatchLaunchStream = true;
IOProviderClass = "IOUSBDevice";
idProduct = "_";
idVendor = "_";
};
};
}
Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.LaunchOnlyOnce
This optional key specifies whether the job can only be run once and only once. In other words, if the job cannot be safely respawned without a full machine reboot, then set this key to be true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.LimitLoadFromHosts
This configuration file only applies to hosts NOT listed with this key. Note: One should set kern.hostname in sysctl.conf(5) for this feature to work reliably.

Type: null or (list of string)

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.LimitLoadToHosts
This configuration file only applies to the hosts listed with this key. Note: One should set kern.hostname in sysctl.conf(5) for this feature to work reliably.

Type: null or (list of string)

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.LimitLoadToSessionType
This configuration file only applies to sessions of the type specified. This key is used in concert with the -S flag to launchctl.

Type: null or string or list of string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.LowPriorityBackgroundIO
This optional key specifies whether the kernel should consider this daemon to be low priority when doing file system I/O when the process is throttled with the Darwin-background classification.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.LowPriorityIO
This optional key specifies whether the kernel should consider this daemon to be low priority when doing file system I/O.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.MachServices
This optional key is used to specify Mach services to be registered with the Mach bootstrap sub-system. Each key in this dictionary should be the name of service to be advertised. The value of the key must be a boolean and set to true. Alternatively, a dictionary can be used instead of a simple true value.

Finally, for the job itself, the values will be replaced with Mach ports at the time of check-in with launchd.

Type: null or (attribute set of (boolean or (submodule)))

Default: null

Example:

{
"org.nixos.service" = {
ResetAtClose = true;
};
}
Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.Nice
This optional key specifies what nice(3) value should be applied to the daemon.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.OnDemand
This key was used in Mac OS X 10.4 to control whether a job was kept alive or not. The default was true. This key has been deprecated and replaced in Mac OS X 10.5 and later with the more powerful KeepAlive option.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.ProcessType
This optional key describes, at a high level, the intended purpose of the job. The system will apply resource limits based on what kind of job it is. If left unspecified, the system will apply light resource limits to the job, throttling its CPU usage and I/O bandwidth. The following are valid values:

Background
Background jobs are generally processes that do work that was not directly requested by the user. The resource limits applied to Background jobs are intended to prevent them from disrupting the user experience.

Standard
Standard jobs are equivalent to no ProcessType being set.

Adaptive
Adaptive jobs move between the Background and Interactive classifications based on activity over XPC connections. See xpc_transaction_begin(3) for details.

Interactive
Interactive jobs run with the same resource limitations as apps, that is to say, none. Interactive jobs are critical to maintaining a responsive user experience, and this key should only be used if an app’s ability to be responsive depends on it, and cannot be made Adaptive.

Type: null or one of “Background”, “Standard”, “Adaptive”, “Interactive”

Default: null

Example: "Background"

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.Program
This key maps to the first argument of execvp(3). If this key is missing, then the first element of the array of strings provided to the ProgramArguments will be used instead. This key is required in the absence of the ProgramArguments key.

Type: null or absolute path

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.ProgramArguments
This key maps to the second argument of execvp(3). This key is required in the absence of the Program key. Please note: many people are confused by this key. Please read execvp(3) very carefully!

Type: null or (list of string)

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.QueueDirectories
Much like the WatchPaths option, this key will watch the paths for modifications. The difference being that the job will only be started if the path is a directory and the directory is not empty.

Type: null or (list of string)

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.RootDirectory
This optional key is used to specify a directory to chroot(2) to before running the job.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.RunAtLoad
This optional key is used to control whether your job is launched once at the time the job is loaded. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.ServiceIPC
This optional key specifies whether the job participates in advanced communication with launchd. The default is false. This flag is incompatible with the inetdCompatibility key.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.SessionCreate
This key specifies that the job should be spawned into a new security audit session rather than the default session for the context is belongs to. See auditon(2) for details.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.Sockets
This optional key is used to specify launch on demand sockets that can be used to let launchd know when to run the job. The job must check-in to get a copy of the file descriptors using APIs outlined in launch(3). The keys of the top level Sockets dictionary can be anything. They are meant for the application developer to use to differentiate which descriptors correspond to which application level protocols (e.g. http vs. ftp vs. DNS…). At check-in time, the value of each Sockets dictionary key will be an array of descriptors. Daemon/Agent writers should consider all descriptors of a given key to be to be effectively equivalent, even though each file descriptor likely represents a different networking protocol which conforms to the criteria specified in the job configuration file.

The parameters below are used as inputs to call getaddrinfo(3).

Type: null or (attribute set of (submodule))

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.Sockets.<name>.Bonjour
This optional key can be used to request that the service be registered with the mDNSResponder(8). If the value is boolean, the service name is inferred from the SockServiceName.

Type: null or boolean or list of string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.Sockets.<name>.MulticastGroup
This optional key can be used to request that the datagram socket join a multicast group. If the value is a hostname, then getaddrinfo(3) will be used to join the correct multicast address for a given socket family. If an explicit IPv4 or IPv6 address is given, it is required that the SockFamily family also be set, otherwise the results are undefined.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.Sockets.<name>.SecureSocketWithKey
This optional key is a variant of SockPathName. Instead of binding to a known path, a securely generated socket is created and the path is assigned to the environment variable that is inherited by all jobs spawned by launchd.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.Sockets.<name>.SockFamily
This optional key can be used to specifically request that “IPv4” or “IPv6” socket(s) be created.

Type: null or one of “IPv4”, “IPv6”

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.Sockets.<name>.SockNodeName
This optional key specifies the node to connect(2) or bind(2) to.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.Sockets.<name>.SockPassive
This optional key specifies whether listen(2) or connect(2) should be called on the created file descriptor. The default is true (“to listen”).

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.Sockets.<name>.SockPathMode
This optional key specifies the mode of the socket. Known bug: Property lists don’t support octal, so please convert the value to decimal.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.Sockets.<name>.SockPathName
This optional key implies SockFamily is set to “Unix”. It specifies the path to connect(2) or bind(2) to.

Type: null or absolute path

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.Sockets.<name>.SockProtocol
This optional key specifies the protocol to be passed to socket(2). The only value understood by this key at the moment is “TCP”.

Type: null or value “TCP” (singular enum)

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.Sockets.<name>.SockServiceName
This optional key specifies the service on the node to connect(2) or bind(2) to.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.Sockets.<name>.SockType
This optional key tells launchctl what type of socket to create. The default is “stream” and other valid values for this key are “dgram” and “seqpacket” respectively.

Type: null or one of “stream”, “dgram”, “seqpacket”

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.SoftResourceLimits
Resource limits to be imposed on the job. These adjust variables set with setrlimit(2). The following keys apply:

Type: null or (submodule)

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.SoftResourceLimits.CPU
The maximum amount of cpu time (in seconds) to be used by each process.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.SoftResourceLimits.Core
The largest size (in bytes) core file that may be created.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.SoftResourceLimits.Data
The maximum size (in bytes) of the data segment for a process; this defines how far a program may extend its break with the sbrk(2) system call.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.SoftResourceLimits.FileSize
The largest size (in bytes) file that may be created.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.SoftResourceLimits.MemoryLock
The maximum size (in bytes) which a process may lock into memory using the mlock(2) function.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.SoftResourceLimits.NumberOfFiles
The maximum number of open files for this process. Setting this value in a system wide daemon will set the sysctl(3) kern.maxfiles (SoftResourceLimits) or kern.maxfilesperproc (HardResourceLimits) value in addition to the setrlimit(2) values.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.SoftResourceLimits.NumberOfProcesses
The maximum number of simultaneous processes for this user id. Setting this value in a system wide daemon will set the sysctl(3) kern.maxproc (SoftResourceLimits) or kern.maxprocperuid (HardResourceLimits) value in addition to the setrlimit(2) values.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.SoftResourceLimits.ResidentSetSize
The maximum size (in bytes) to which a process’s resident set size may grow. This imposes a limit on the amount of physical memory to be given to a process; if memory is tight, the system will prefer to take memory from processes that are exceeding their declared resident set size.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.SoftResourceLimits.Stack
The maximum size (in bytes) of the stack segment for a process; this defines how far a program’s stack segment may be extended. Stack extension is performed automatically by the system.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.StandardErrorPath
This optional key specifies what file should be used for data being sent to stderr when using stdio(3).

Type: null or absolute path

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.StandardInPath
This optional key specifies what file should be used for data being supplied to stdin when using stdio(3).

Type: null or absolute path

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.StandardOutPath
This optional key specifies what file should be used for data being sent to stdout when using stdio(3).

Type: null or absolute path

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.StartCalendarInterval
This optional key causes the job to be started every calendar interval as specified. The semantics are much like crontab(5): Missing attributes are considered to be wildcard. Unlike cron which skips job invocations when the computer is asleep, launchd will start the job the next time the computer wakes up. If multiple intervals transpire before the computer is woken, those events will be coalesced into one event upon waking from sleep.

Important
The list must not be empty and must not contain duplicate entries (attrsets which compare equally).

Caution
Since missing attrs become wildcards, an empty attrset effectively means “every minute”.

Type: null or (submodule) or unique (non-empty (list of (submodule)))

Default: null

Example:

[
{
Hour = 2;
Minute = 30;
}
]
Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.StartInterval
This optional key causes the job to be started every N seconds. If the system is asleep, the job will be started the next time the computer wakes up. If multiple intervals transpire before the computer is woken, those events will be coalesced into one event upon wake from sleep.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.StartOnMount
This optional key causes the job to be started every time a filesystem is mounted.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.ThrottleInterval
This key lets one override the default throttling policy imposed on jobs by launchd. The value is in seconds, and by default, jobs will not be spawned more than once every 10 seconds. The principle behind this is that jobs should linger around just in case they are needed again in the near future. This not only reduces the latency of responses, but it encourages developers to amortize the cost of program invocation.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.TimeOut
The recommended idle time out (in seconds) to pass to the job. If no value is specified, a default time out will be supplied by launchd for use by the job at check in time.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.Umask
This optional key specifies what value should be passed to umask(2) before running the job. Known bug: Property lists don’t support octal, so please convert the value to decimal.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.UserName
This optional key specifies the user to run the job as. This key is only applicable when launchd is running as root.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.WaitForDebugger
This optional key specifies that launchd should instruct the kernel to have the job wait for a debugger to attach before any code in the job is executed.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.WatchPaths
This optional key causes the job to be started if any one of the listed paths are modified.

Type: null or (list of absolute path)

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.WorkingDirectory
This optional key is used to specify a directory to chdir(2) to before running the job.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.inetdCompatibility
The presence of this key specifies that the daemon expects to be run as if it were launched from inetd.

Type: null or (submodule)

Default: null

Example:

{
Wait = true;
}
Declared by:

<nix-darwin/modules/launchd>
launchd.daemons.<name>.serviceConfig.inetdCompatibility.Wait
This flag corresponds to the “wait” or “nowait” option of inetd. If true, then the listening socket is passed via the standard in/out/error file descriptors. If false, then accept(2) is called on behalf of the job, and the result is passed via the standard in/out/error descriptors.

Type: null or boolean or string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.envVariables
A set of environment variables to be set on all future processes launched by launchd in the caller’s context. The value of each variable can be either a string or a list of strings. The latter is concatenated, interspersed with colon characters.

Type: attribute set of (string or list of string)

Default: { }

Example:

{
LANG = "nl_NL.UTF-8";
}
Declared by:

<nix-darwin/modules/launchd>
launchd.labelPrefix
The default prefix of the service label. Individual services can override this by setting the Label attribute.

Type: string

Default: "org.nixos"

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents
Definition of per-user launchd agents.

When a user logs in, a per-user launchd is started. It does the following:

It loads the parameters for each launch-on-demand user agent from the property list files found in /System/Library/LaunchAgents, /Library/LaunchAgents, and the user’s individual Library/LaunchAgents directory.

It registers the sockets and file descriptors requested by those user agents.

It launches any user agents that requested to be running all the time.

As requests for a particular service arrive, it launches the corresponding user agent and passes the request to it.

When the user logs out, it sends a SIGTERM signal to all of the user agents that it started.

Type: attribute set of (submodule)

Default: { }

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.command
Command executed as the service’s main process.

Type: string or absolute path

Default: ""

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.environment
Environment variables passed to the service’s processes.

Type: attribute set of (string or list of string)

Default: { }

Example:

{
LANG = "nl_NL.UTF-8";
PATH = "/foo/bar/bin";
}
Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.path
Packages added to the service’s PATH environment variable. Only the bin and subdirectories of each package is added.

Type: list of (absolute path or string)

Default: [ ]

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.script
Shell commands executed as the service’s main process.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig
Each attribute in this set specifies an option for a key in the plist. https://developer.apple.com/legacy/library/documentation/Darwin/Reference/ManPages/man5/launchd.plist.5.html

Type: submodule

Default: { }

Example:

{
KeepAlive = true;
Program = "/run/current-system/sw/bin/nix-daemon";
}
Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.AbandonProcessGroup
When a job dies, launchd kills any remaining processes with the same process group ID as the job. Setting this key to true disables that behavior.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.Debug
This optional key specifies that launchd should adjust its log mask temporarily to LOG_DEBUG while dealing with this job.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.Disabled
This optional key is used as a hint to launchctl(1) that it should not submit this job to launchd when loading a job or jobs. The value of this key does NOT reflect the current state of the job on the running system. If you wish to know whether a job is loaded in launchd, reading this key from a configuration file yourself is not a sufficient test. You should query launchd for the presence of the job using the launchctl(1) list subcommand or use the ServiceManagement framework’s SMJobCopyDictionary() method.

Note that as of Mac OS X v10.6, this key’s value in a configuration file conveys a default value, which is changed with the [-w] option of the launchctl(1) load and unload subcommands. These subcommands no longer modify the configuration file, so the value displayed in the configuration file is not necessarily the value that launchctl(1) will apply. See launchctl(1) for more information.

Please also be mindful that you should only use this key if the provided on-demand and KeepAlive criteria are insufficient to describe the conditions under which your job needs to run. The cost to have a job loaded in launchd is negligible, so there is no harm in loading a job which only runs once or very rarely.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.EnableGlobbing
This flag causes launchd to use the glob(3) mechanism to update the program arguments before invocation.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.EnableTransactions
This flag instructs launchd that the job promises to use vproc_transaction_begin(3) and vproc_transaction_end(3) to track outstanding transactions that need to be reconciled before the process can safely terminate. If no outstanding transactions are in progress, then launchd is free to send the SIGKILL signal.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.EnvironmentVariables
This optional key is used to specify additional environment variables to be set before running the job.

Type: null or (attribute set of string)

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.ExitTimeOut
The amount of time launchd waits before sending a SIGKILL signal. The default value is 20 seconds. The value zero is interpreted as infinity.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.GroupName
This optional key specifies the group to run the job as. This key is only applicable when launchd is running as root. If UserName is set and GroupName is not, the the group will be set to the default group of the user.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.HardResourceLimits
Resource limits to be imposed on the job. These adjust variables set with setrlimit(2). The following keys apply:

Type: null or (submodule)

Default: null

Example:

{
NumberOfFiles = 4096;
}
Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.HardResourceLimits.CPU
The maximum amount of cpu time (in seconds) to be used by each process.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.HardResourceLimits.Core
The largest size (in bytes) core file that may be created.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.HardResourceLimits.Data
The maximum size (in bytes) of the data segment for a process; this defines how far a program may extend its break with the sbrk(2) system call.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.HardResourceLimits.FileSize
The largest size (in bytes) file that may be created.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.HardResourceLimits.MemoryLock
The maximum size (in bytes) which a process may lock into memory using the mlock(2) function.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.HardResourceLimits.NumberOfFiles
The maximum number of open files for this process. Setting this value in a system wide daemon will set the sysctl(3) kern.maxfiles (SoftResourceLimits) or kern.maxfilesperproc (HardResourceLimits) value in addition to the setrlimit(2) values.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.HardResourceLimits.NumberOfProcesses
The maximum number of simultaneous processes for this user id. Setting this value in a system wide daemon will set the sysctl(3) kern.maxproc (SoftResourceLimits) or kern.maxprocperuid (HardResourceLimits) value in addition to the setrlimit(2) values.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.HardResourceLimits.ResidentSetSize
The maximum size (in bytes) to which a process’s resident set size may grow. This imposes a limit on the amount of physical memory to be given to a process; if memory is tight, the system will prefer to take memory from processes that are exceeding their declared resident set size.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.HardResourceLimits.Stack
The maximum size (in bytes) of the stack segment for a process; this defines how far a program’s stack segment may be extended. Stack extension is performed automatically by the system.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.InitGroups
This optional key specifies whether initgroups(3) should be called before running the job. The default is true in 10.5 and false in 10.4. This key will be ignored if the UserName key is not set.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.KeepAlive
This optional key is used to control whether your job is to be kept continuously running or to let demand and conditions control the invocation. The default is false and therefore only demand will start the job. The value may be set to true to unconditionally keep the job alive. Alternatively, a dictionary of conditions may be specified to selectively control whether launchd keeps a job alive or not. If multiple keys are provided, launchd ORs them, thus providing maximum flexibility to the job to refine the logic and stall if necessary. If launchd finds no reason to restart the job, it falls back on demand based invocation. Jobs that exit quickly and frequently when configured to be kept alive will be throttled to converve system resources.

Type: null or boolean or (submodule)

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.Label
This required key uniquely identifies the job to launchd.

Type: string

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.LaunchEvents
Specifies higher-level event types to be used as launch-on-demand event sources. Each sub-dictionary defines events for a particular event subsystem, such as “com.apple.iokit.matching”, which can be used to launch jobs based on the appearance of nodes in the IORegistry. Each dictionary within the sub-dictionary specifies an event descriptor that is specified to each event subsystem. With this key, the job promises to use the xpc_set_event_stream_handler(3) API to consume events. See xpc_events(3) for more details on event sources.

Type: null or (attribute set)

Default: null

Example:

{
"com.apple.iokit.matching" = {
"com.apple.usb.device" = {
IOMatchLaunchStream = true;
IOProviderClass = "IOUSBDevice";
idProduct = "_";
idVendor = "_";
};
};
}
Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.LaunchOnlyOnce
This optional key specifies whether the job can only be run once and only once. In other words, if the job cannot be safely respawned without a full machine reboot, then set this key to be true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.LimitLoadFromHosts
This configuration file only applies to hosts NOT listed with this key. Note: One should set kern.hostname in sysctl.conf(5) for this feature to work reliably.

Type: null or (list of string)

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.LimitLoadToHosts
This configuration file only applies to the hosts listed with this key. Note: One should set kern.hostname in sysctl.conf(5) for this feature to work reliably.

Type: null or (list of string)

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.LimitLoadToSessionType
This configuration file only applies to sessions of the type specified. This key is used in concert with the -S flag to launchctl.

Type: null or string or list of string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.LowPriorityBackgroundIO
This optional key specifies whether the kernel should consider this daemon to be low priority when doing file system I/O when the process is throttled with the Darwin-background classification.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.LowPriorityIO
This optional key specifies whether the kernel should consider this daemon to be low priority when doing file system I/O.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.MachServices
This optional key is used to specify Mach services to be registered with the Mach bootstrap sub-system. Each key in this dictionary should be the name of service to be advertised. The value of the key must be a boolean and set to true. Alternatively, a dictionary can be used instead of a simple true value.

Finally, for the job itself, the values will be replaced with Mach ports at the time of check-in with launchd.

Type: null or (attribute set of (boolean or (submodule)))

Default: null

Example:

{
"org.nixos.service" = {
ResetAtClose = true;
};
}
Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.Nice
This optional key specifies what nice(3) value should be applied to the daemon.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.OnDemand
This key was used in Mac OS X 10.4 to control whether a job was kept alive or not. The default was true. This key has been deprecated and replaced in Mac OS X 10.5 and later with the more powerful KeepAlive option.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.ProcessType
This optional key describes, at a high level, the intended purpose of the job. The system will apply resource limits based on what kind of job it is. If left unspecified, the system will apply light resource limits to the job, throttling its CPU usage and I/O bandwidth. The following are valid values:

Background
Background jobs are generally processes that do work that was not directly requested by the user. The resource limits applied to Background jobs are intended to prevent them from disrupting the user experience.

Standard
Standard jobs are equivalent to no ProcessType being set.

Adaptive
Adaptive jobs move between the Background and Interactive classifications based on activity over XPC connections. See xpc_transaction_begin(3) for details.

Interactive
Interactive jobs run with the same resource limitations as apps, that is to say, none. Interactive jobs are critical to maintaining a responsive user experience, and this key should only be used if an app’s ability to be responsive depends on it, and cannot be made Adaptive.

Type: null or one of “Background”, “Standard”, “Adaptive”, “Interactive”

Default: null

Example: "Background"

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.Program
This key maps to the first argument of execvp(3). If this key is missing, then the first element of the array of strings provided to the ProgramArguments will be used instead. This key is required in the absence of the ProgramArguments key.

Type: null or absolute path

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.ProgramArguments
This key maps to the second argument of execvp(3). This key is required in the absence of the Program key. Please note: many people are confused by this key. Please read execvp(3) very carefully!

Type: null or (list of string)

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.QueueDirectories
Much like the WatchPaths option, this key will watch the paths for modifications. The difference being that the job will only be started if the path is a directory and the directory is not empty.

Type: null or (list of string)

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.RootDirectory
This optional key is used to specify a directory to chroot(2) to before running the job.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.RunAtLoad
This optional key is used to control whether your job is launched once at the time the job is loaded. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.ServiceIPC
This optional key specifies whether the job participates in advanced communication with launchd. The default is false. This flag is incompatible with the inetdCompatibility key.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.SessionCreate
This key specifies that the job should be spawned into a new security audit session rather than the default session for the context is belongs to. See auditon(2) for details.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.Sockets
This optional key is used to specify launch on demand sockets that can be used to let launchd know when to run the job. The job must check-in to get a copy of the file descriptors using APIs outlined in launch(3). The keys of the top level Sockets dictionary can be anything. They are meant for the application developer to use to differentiate which descriptors correspond to which application level protocols (e.g. http vs. ftp vs. DNS…). At check-in time, the value of each Sockets dictionary key will be an array of descriptors. Daemon/Agent writers should consider all descriptors of a given key to be to be effectively equivalent, even though each file descriptor likely represents a different networking protocol which conforms to the criteria specified in the job configuration file.

The parameters below are used as inputs to call getaddrinfo(3).

Type: null or (attribute set of (submodule))

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.Sockets.<name>.Bonjour
This optional key can be used to request that the service be registered with the mDNSResponder(8). If the value is boolean, the service name is inferred from the SockServiceName.

Type: null or boolean or list of string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.Sockets.<name>.MulticastGroup
This optional key can be used to request that the datagram socket join a multicast group. If the value is a hostname, then getaddrinfo(3) will be used to join the correct multicast address for a given socket family. If an explicit IPv4 or IPv6 address is given, it is required that the SockFamily family also be set, otherwise the results are undefined.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.Sockets.<name>.SecureSocketWithKey
This optional key is a variant of SockPathName. Instead of binding to a known path, a securely generated socket is created and the path is assigned to the environment variable that is inherited by all jobs spawned by launchd.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.Sockets.<name>.SockFamily
This optional key can be used to specifically request that “IPv4” or “IPv6” socket(s) be created.

Type: null or one of “IPv4”, “IPv6”

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.Sockets.<name>.SockNodeName
This optional key specifies the node to connect(2) or bind(2) to.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.Sockets.<name>.SockPassive
This optional key specifies whether listen(2) or connect(2) should be called on the created file descriptor. The default is true (“to listen”).

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.Sockets.<name>.SockPathMode
This optional key specifies the mode of the socket. Known bug: Property lists don’t support octal, so please convert the value to decimal.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.Sockets.<name>.SockPathName
This optional key implies SockFamily is set to “Unix”. It specifies the path to connect(2) or bind(2) to.

Type: null or absolute path

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.Sockets.<name>.SockProtocol
This optional key specifies the protocol to be passed to socket(2). The only value understood by this key at the moment is “TCP”.

Type: null or value “TCP” (singular enum)

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.Sockets.<name>.SockServiceName
This optional key specifies the service on the node to connect(2) or bind(2) to.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.Sockets.<name>.SockType
This optional key tells launchctl what type of socket to create. The default is “stream” and other valid values for this key are “dgram” and “seqpacket” respectively.

Type: null or one of “stream”, “dgram”, “seqpacket”

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.SoftResourceLimits
Resource limits to be imposed on the job. These adjust variables set with setrlimit(2). The following keys apply:

Type: null or (submodule)

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.SoftResourceLimits.CPU
The maximum amount of cpu time (in seconds) to be used by each process.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.SoftResourceLimits.Core
The largest size (in bytes) core file that may be created.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.SoftResourceLimits.Data
The maximum size (in bytes) of the data segment for a process; this defines how far a program may extend its break with the sbrk(2) system call.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.SoftResourceLimits.FileSize
The largest size (in bytes) file that may be created.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.SoftResourceLimits.MemoryLock
The maximum size (in bytes) which a process may lock into memory using the mlock(2) function.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.SoftResourceLimits.NumberOfFiles
The maximum number of open files for this process. Setting this value in a system wide daemon will set the sysctl(3) kern.maxfiles (SoftResourceLimits) or kern.maxfilesperproc (HardResourceLimits) value in addition to the setrlimit(2) values.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.SoftResourceLimits.NumberOfProcesses
The maximum number of simultaneous processes for this user id. Setting this value in a system wide daemon will set the sysctl(3) kern.maxproc (SoftResourceLimits) or kern.maxprocperuid (HardResourceLimits) value in addition to the setrlimit(2) values.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.SoftResourceLimits.ResidentSetSize
The maximum size (in bytes) to which a process’s resident set size may grow. This imposes a limit on the amount of physical memory to be given to a process; if memory is tight, the system will prefer to take memory from processes that are exceeding their declared resident set size.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.SoftResourceLimits.Stack
The maximum size (in bytes) of the stack segment for a process; this defines how far a program’s stack segment may be extended. Stack extension is performed automatically by the system.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.StandardErrorPath
This optional key specifies what file should be used for data being sent to stderr when using stdio(3).

Type: null or absolute path

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.StandardInPath
This optional key specifies what file should be used for data being supplied to stdin when using stdio(3).

Type: null or absolute path

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.StandardOutPath
This optional key specifies what file should be used for data being sent to stdout when using stdio(3).

Type: null or absolute path

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.StartCalendarInterval
This optional key causes the job to be started every calendar interval as specified. The semantics are much like crontab(5): Missing attributes are considered to be wildcard. Unlike cron which skips job invocations when the computer is asleep, launchd will start the job the next time the computer wakes up. If multiple intervals transpire before the computer is woken, those events will be coalesced into one event upon waking from sleep.

Important
The list must not be empty and must not contain duplicate entries (attrsets which compare equally).

Caution
Since missing attrs become wildcards, an empty attrset effectively means “every minute”.

Type: null or (submodule) or unique (non-empty (list of (submodule)))

Default: null

Example:

[
{
Hour = 2;
Minute = 30;
}
]
Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.StartInterval
This optional key causes the job to be started every N seconds. If the system is asleep, the job will be started the next time the computer wakes up. If multiple intervals transpire before the computer is woken, those events will be coalesced into one event upon wake from sleep.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.StartOnMount
This optional key causes the job to be started every time a filesystem is mounted.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.ThrottleInterval
This key lets one override the default throttling policy imposed on jobs by launchd. The value is in seconds, and by default, jobs will not be spawned more than once every 10 seconds. The principle behind this is that jobs should linger around just in case they are needed again in the near future. This not only reduces the latency of responses, but it encourages developers to amortize the cost of program invocation.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.TimeOut
The recommended idle time out (in seconds) to pass to the job. If no value is specified, a default time out will be supplied by launchd for use by the job at check in time.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.Umask
This optional key specifies what value should be passed to umask(2) before running the job. Known bug: Property lists don’t support octal, so please convert the value to decimal.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.UserName
This optional key specifies the user to run the job as. This key is only applicable when launchd is running as root.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.WaitForDebugger
This optional key specifies that launchd should instruct the kernel to have the job wait for a debugger to attach before any code in the job is executed.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.WatchPaths
This optional key causes the job to be started if any one of the listed paths are modified.

Type: null or (list of absolute path)

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.WorkingDirectory
This optional key is used to specify a directory to chdir(2) to before running the job.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.inetdCompatibility
The presence of this key specifies that the daemon expects to be run as if it were launched from inetd.

Type: null or (submodule)

Default: null

Example:

{
Wait = true;
}
Declared by:

<nix-darwin/modules/launchd>
launchd.user.agents.<name>.serviceConfig.inetdCompatibility.Wait
This flag corresponds to the “wait” or “nowait” option of inetd. If true, then the listening socket is passed via the standard in/out/error file descriptors. If false, then accept(2) is called on behalf of the job, and the result is passed via the standard in/out/error descriptors.

Type: null or boolean or string

Default: null

Declared by:

<nix-darwin/modules/launchd>
launchd.user.envVariables
A set of environment variables to be set on all future processes launched by launchd in the caller’s context. The value of each variable can be either a string or a list of strings. The latter is concatenated, interspersed with colon characters.

Type: attribute set of (string or list of string)

Default: { }

Example:

{
LANG = "nl_NL.UTF-8";
}
Declared by:

<nix-darwin/modules/launchd>
lib
This option allows modules to define helper functions, constants, etc.

Type: attribute set of (attribute set)

Default: { }

Declared by:

<nix-darwin/modules/misc/lib.nix>
networking.applicationFirewall.enable
Whether to enable application firewall.

Type: null or boolean

Default: null

Example: true

Declared by:

<nix-darwin/modules/networking/applicationFirewall.nix>
networking.applicationFirewall.enableStealthMode
Whether to enable stealth mode.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/networking/applicationFirewall.nix>
networking.applicationFirewall.allowSigned
Whether to enable built-in software to receive incoming connections.

Type: boolean

Default: true

Example: true

Declared by:

<nix-darwin/modules/networking/applicationFirewall.nix>
networking.applicationFirewall.allowSignedApp
Whether to enable downloaded signed software to receive incoming connections.

Type: boolean

Default: true

Example: true

Declared by:

<nix-darwin/modules/networking/applicationFirewall.nix>
networking.applicationFirewall.blockAllIncoming
Whether to enable blocking all incoming connections.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/networking/applicationFirewall.nix>
networking.computerName
The user-friendly name for the system, set in System Preferences > Sharing > Computer Name.

Setting this option is equivalent to running scutil --set ComputerName.

This name can contain spaces and Unicode characters.

Type: null or string

Default: null

Example: "John’s MacBook Pro"

Declared by:

<nix-darwin/modules/networking>
networking.dns
The list of dns servers used when resolving domain names.

Type: list of string

Default: [ ]

Example:

[
"8.8.8.8"
"8.8.4.4"
"2001:4860:4860::8888"
"2001:4860:4860::8844"
]
Declared by:

<nix-darwin/modules/networking>
networking.domain
The domain. It can be left empty if it is auto-detected through DHCP.

Type: null or string

Default: null

Example: "home.arpa"

Declared by:

<nix-darwin/modules/networking>
networking.fqdn
The fully qualified domain name (FQDN) of this host. By default, it is the result of combining networking.hostName and networking.domain.

Using this option will result in an evaluation error if the hostname is empty or no domain is specified.

Modules that accept a mere networking.hostName but prefer a fully qualified domain name may use networking.fqdnOrHostName instead.

Type: string

Default: "${networking.hostName}.${networking.domain}"

Declared by:

<nix-darwin/modules/networking>
networking.fqdnOrHostName
Either the fully qualified domain name (FQDN), or just the host name if it does not exists.

This is a convenience option for modules to read instead of fqdn when a mere hostName is also an acceptable value; this option does not throw an error when domain is unset.

Type: string (read only)

Default:

if cfg.domain == null then cfg.hostName else cfg.fqdn

Declared by:

<nix-darwin/modules/networking>
networking.hostName
The hostname of your system, as visible from the command line and used by local and remote networks when connecting through SSH and Remote Login.

Setting this option is equivalent to running the command scutil --set HostName.

(Note that networking.localHostName defaults to the value of this option.)

Type: null or string matching the pattern ^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]_[a-zA-Z0-9])\.)_([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]\*[A-Za-z0-9])$

Default: null

Example: "Johns-MacBook-Pro"

Declared by:

<nix-darwin/modules/networking>
networking.knownNetworkServices
List of networkservices that should be configured.

To display a list of all the network services on the server’s hardware ports, use networksetup -listallnetworkservices.

Type: list of string

Default: [ ]

Example:

[
"Wi-Fi"
"Ethernet Adaptor"
"Thunderbolt Ethernet"
]
Declared by:

<nix-darwin/modules/networking>
networking.localHostName
The local hostname, or local network name, is displayed beneath the computer’s name at the top of the Sharing preferences pane. It identifies your Mac to Bonjour-compatible services.

Setting this option is equivalent to running the command scutil --set LocalHostName, where running, e.g., scutil --set LocalHostName 'Johns-MacBook-Pro', would set the systems local hostname to “Johns-MacBook-Pro.local”. The value of this option defaults to the value of the networking.hostName option.

By default on macOS the local hostname is your computer’s name with “.local” appended, with any spaces replaced with hyphens, and invalid characters omitted.

Type: null or string matching the pattern ^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]_[a-zA-Z0-9])\.)_([A-Za-z0-9]|[A-Za-z0-9][A-Za-z0-9\-]\*[A-Za-z0-9])$

Default: null

Example: "Johns-MacBook-Pro"

Declared by:

<nix-darwin/modules/networking>
networking.search
The list of search paths used when resolving domain names.

Type: list of string

Default: [ ]

Declared by:

<nix-darwin/modules/networking>
networking.wakeOnLan.enable
Enable Wake-on-LAN for the device.

Battery powered devices may require being connected to power.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/networking>
networking.wg-quick.interfaces
Set of wg-quick interfaces.

Type: attribute set of (submodule)

Default: { }

Declared by:

<nix-darwin/modules/services/wg-quick.nix>
networking.wg-quick.interfaces.<name>.address
List of IP addresses for this interface.

Type: null or (list of string)

Default: [ ]

Declared by:

<nix-darwin/modules/services/wg-quick.nix>
networking.wg-quick.interfaces.<name>.autostart
Whether to bring up this interface automatically during boot.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/services/wg-quick.nix>
networking.wg-quick.interfaces.<name>.dns
List of DNS servers for this interface.

Type: list of string

Default: [ ]

Declared by:

<nix-darwin/modules/services/wg-quick.nix>
networking.wg-quick.interfaces.<name>.listenPort
Port to listen on, randomly selected if not specified.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/services/wg-quick.nix>
networking.wg-quick.interfaces.<name>.mtu
MTU to set for this interface, automatically set if not specified

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/services/wg-quick.nix>
networking.wg-quick.interfaces.<name>.peers
List of peers associated with this interface.

Type: list of (submodule)

Default: [ ]

Declared by:

<nix-darwin/modules/services/wg-quick.nix>
networking.wg-quick.interfaces.<name>.peers.\*.allowedIPs
List of IP addresses associated with this peer.

Type: list of string

Default: [ ]

Declared by:

<nix-darwin/modules/services/wg-quick.nix>
networking.wg-quick.interfaces.<name>.peers.\*.endpoint
IP and port to connect to this peer at.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/services/wg-quick.nix>
networking.wg-quick.interfaces.<name>.peers.\*.persistentKeepalive
Interval in seconds to send keepalive packets

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/services/wg-quick.nix>
networking.wg-quick.interfaces.<name>.peers.\*.presharedKeyFile
Optional, path to file containing the pre-shared key for this peer.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/services/wg-quick.nix>
networking.wg-quick.interfaces.<name>.peers.\*.publicKey
The public key for this peer.

Type: string

Default: null

Declared by:

<nix-darwin/modules/services/wg-quick.nix>
networking.wg-quick.interfaces.<name>.postDown
List of commands to run after interface shutdown

Type: strings concatenated with “\n” or (list of string) convertible to it

Default: ""

Declared by:

<nix-darwin/modules/services/wg-quick.nix>
networking.wg-quick.interfaces.<name>.postUp
List of commands to run after interface setup.

Type: strings concatenated with “\n” or (list of string) convertible to it

Default: ""

Declared by:

<nix-darwin/modules/services/wg-quick.nix>
networking.wg-quick.interfaces.<name>.preDown
List of commadns to run before interface shutdown.

Type: strings concatenated with “\n” or (list of string) convertible to it

Default: ""

Declared by:

<nix-darwin/modules/services/wg-quick.nix>
networking.wg-quick.interfaces.<name>.preUp
List of commands to run before interface setup.

Type: strings concatenated with “\n” or (list of string) convertible to it

Default: ""

Declared by:

<nix-darwin/modules/services/wg-quick.nix>
networking.wg-quick.interfaces.<name>.privateKeyFile
Path to file containing this interface’s private key.

Type: string

Default: null

Declared by:

<nix-darwin/modules/services/wg-quick.nix>
networking.wg-quick.interfaces.<name>.table
Controls the routing table to which routes are added. There are two special values: off disables the creation of routes altogether, and auto (the default) adds routes to the default table and enables special handling of default routes.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/services/wg-quick.nix>
networking.wg-quick.logDir
Directory to save wg-quick logs to.

Type: string

Default: "/var/log"

Declared by:

<nix-darwin/modules/services/wg-quick.nix>
nix.enable
Whether to enable Nix.

Disabling this will stop nix-darwin from managing the installed version of Nix, the nix-daemon launchd daemon, and the settings in /etc/nix/nix.conf.

This allows you to use nix-darwin without it taking over your system installation of Nix. Some nix-darwin functionality that relies on managing the Nix installation, like the nix.\* options to adjust Nix settings or configure a Linux builder, will be unavailable. You will also have to upgrade Nix yourself, as nix-darwin will no longer do so.

Warning
If you have already removed your global system installation of Nix, this will break nix-darwin and you will have to reinstall Nix to fix it.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/nix>
nix.package
This option specifies the Nix package instance to use throughout the system.

Type: package

Default: pkgs.nix

Declared by:

<nix-darwin/modules/nix>
nix.buildMachines
This option lists the machines to be used if distributed builds are enabled (see nix.distributedBuilds). Nix will perform derivations on those machines via SSH by copying the inputs to the Nix store on the remote machine, starting the build, then copying the output back to the local Nix store.

Type: list of (submodule)

Default: [ ]

Declared by:

<nix-darwin/modules/nix>
nix.buildMachines.\*.hostName
The hostname of the build machine.

Type: string

Example: "nixbuilder.example.org"

Declared by:

<nix-darwin/modules/nix>
nix.buildMachines.\*.mandatoryFeatures
A list of features mandatory for this builder. The builder will be ignored for derivations that don’t require all features in this list. All mandatory features are automatically included in supportedFeatures.

Type: list of string

Default: [ ]

Example:

[
"big-parallel"
]
Declared by:

<nix-darwin/modules/nix>
nix.buildMachines.\*.maxJobs
The number of concurrent jobs the build machine supports. The build machine will enforce its own limits, but this allows hydra to schedule better since there is no work-stealing between build machines.

Type: signed integer

Default: 1

Declared by:

<nix-darwin/modules/nix>
nix.buildMachines.\*.protocol
The protocol used for communicating with the build machine. Use ssh-ng if your remote builder and your local Nix version support that improved protocol.

Use null when trying to change the special localhost builder without a protocol which is for example used by hydra.

Type: one of <null>, “ssh”, “ssh-ng”

Default: "ssh"

Example: "ssh-ng"

Declared by:

<nix-darwin/modules/nix>
nix.buildMachines.\*.publicHostKey
The (base64-encoded) public host key of this builder. The field is calculated via base64 -w0 /etc/ssh/ssh_host_type_key.pub. If null, SSH will use its regular known-hosts file when connecting.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/nix>
nix.buildMachines.\*.speedFactor
The relative speed of this builder. This is an arbitrary integer that indicates the speed of this builder, relative to other builders. Higher is faster.

Type: signed integer

Default: 1

Declared by:

<nix-darwin/modules/nix>
nix.buildMachines.\*.sshKey
The path to the SSH private key with which to authenticate on the build machine. The private key must not have a passphrase. If null, the building user (root on NixOS machines) must have an appropriate ssh configuration to log in non-interactively.

Note that for security reasons, this path must point to a file in the local filesystem, not to the nix store.

Type: null or string

Default: null

Example: "/root/.ssh/id_buildhost_builduser"

Declared by:

<nix-darwin/modules/nix>
nix.buildMachines.\*.sshUser
The username to log in as on the remote host. This user must be able to log in and run nix commands non-interactively. It must also be privileged to build derivations, so must be included in nix.settings.trusted-users.

Type: null or string

Default: null

Example: "builder"

Declared by:

<nix-darwin/modules/nix>
nix.buildMachines.\*.supportedFeatures
A list of features supported by this builder. The builder will be ignored for derivations that require features not in this list.

Type: list of string

Default: [ ]

Example:

[
"kvm"
"big-parallel"
]
Declared by:

<nix-darwin/modules/nix>
nix.buildMachines.\*.system
The system type the build machine can execute derivations on. Either this attribute or systems must be present, where system takes precedence if both are set.

Type: null or string

Default: null

Example: "x86_64-linux"

Declared by:

<nix-darwin/modules/nix>
nix.buildMachines.\*.systems
The system types the build machine can execute derivations on. Either this attribute or system must be present, where system takes precedence if both are set.

Type: list of string

Default: [ ]

Example:

[
"x86_64-linux"
"aarch64-linux"
]
Declared by:

<nix-darwin/modules/nix>
nix.channel.enable
Whether the nix-channel command and state files are made available on the machine.

The following files are initialized when enabled:

/nix/var/nix/profiles/per-user/root/channels

$HOME/.nix-defexpr/channels (on login)

Disabling this option will not remove the state files from the system.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/nix>
nix.checkConfig
If enabled (the default), checks for data type mismatches and that Nix can parse the generated nix.conf.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/nix>
nix.daemonIOLowPriority
Whether the Nix daemon process should considered to be low priority when doing file system I/O.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/nix>
nix.daemonProcessType
Nix daemon process resource limits class. These limits propagate to build processes. Standard is the default process type and will apply light resource limits, throttling its CPU usage and I/O bandwidth.

See man launchd.plist for explanation of other process types.

Type: one of “Background”, “Standard”, “Adaptive”, “Interactive”

Default: "Standard"

Declared by:

<nix-darwin/modules/nix>
nix.distributedBuilds
Whether to distribute builds to the machines listed in nix.buildMachines.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/nix>
nix.extraOptions
Additional text appended to nix.conf.

Type: strings concatenated with “\n”

Default: ""

Example:

''
keep-outputs = true
keep-derivations = true
''
Declared by:

<nix-darwin/modules/nix>
nix.gc.automatic
Automatically run the garbage collector at a specific time.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/nix-gc>
nix.gc.interval
The calendar interval at which the garbage collector will run. See the serviceConfig.StartCalendarInterval option of the launchd module for more info.

Type: (submodule) or unique (non-empty (list of (submodule)))

Default:

[
{
Hour = 3;
Minute = 15;
Weekday = 7;
}
]
Declared by:

<nix-darwin/modules/services/nix-gc>
nix.gc.options
Options given to nix-collect-garbage when the garbage collector is run automatically.

Type: string

Default: ""

Example: "--max-freed $((64 \* 1024\*\*3))"

Declared by:

<nix-darwin/modules/services/nix-gc>
nix.linux-builder.enable
Whether to enable Linux builder.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/nix/linux-builder.nix>
nix.linux-builder.package
This option specifies the Linux builder to use.

Type: package

Default: "pkgs.darwin.linux-builder"

Declared by:

<nix-darwin/modules/nix/linux-builder.nix>
nix.linux-builder.config
This option specifies extra NixOS configuration for the builder. You should first use the Linux builder without changing the builder configuration otherwise you may not be able to build the Linux builder.

Type: module

Default: { }

Example:

({ pkgs, ... }:

{
environment.systemPackages = [ pkgs.neovim ];
})

Declared by:

<nix-darwin/modules/nix/linux-builder.nix>
nix.linux-builder.ephemeral
Whether to enable wipe the builder’s filesystem on every restart.

This is disabled by default as maintaining the builder’s Nix Store reduces rebuilds. You can enable this if you don’t want your builder to accumulate state. .

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/nix/linux-builder.nix>
nix.linux-builder.mandatoryFeatures
A list of features mandatory for the Linux builder. The builder will be ignored for derivations that don’t require all features in this list. All mandatory features are automatically included in supportedFeatures.

This sets the corresponding nix.buildMachines.\*.mandatoryFeatures option.

Type: list of string

Default: []

Example: [ "big-parallel" ]

Declared by:

<nix-darwin/modules/nix/linux-builder.nix>
nix.linux-builder.maxJobs
Instead of setting this directly, you should set nix.linux-builder.config.virtualisation.cores to configure the amount of cores the Linux builder should have.

The number of concurrent jobs the Linux builder machine supports. The build machine will enforce its own limits, but this allows hydra to schedule better since there is no work-stealing between build machines.

This sets the corresponding nix.buildMachines.\*.maxJobs option.

Type: positive integer, meaning >0

Default:

''
The `virtualisation.cores` of the build machine's final NixOS configuration.
''
Example: 2

Declared by:

<nix-darwin/modules/nix/linux-builder.nix>
nix.linux-builder.protocol
The protocol used for communicating with the build machine. Use ssh-ng if your remote builder and your local Nix version support that improved protocol.

Use null when trying to change the special localhost builder without a protocol which is for example used by hydra.

Type: string

Default: "ssh-ng"

Example: "ssh"

Declared by:

<nix-darwin/modules/nix/linux-builder.nix>
nix.linux-builder.speedFactor
The relative speed of the Linux builder. This is an arbitrary integer that indicates the speed of this builder, relative to other builders. Higher is faster.

This sets the corresponding nix.buildMachines.\*.speedFactor option.

Type: positive integer, meaning >0

Default: 1

Declared by:

<nix-darwin/modules/nix/linux-builder.nix>
nix.linux-builder.supportedFeatures
A list of features supported by the Linux builder. The builder will be ignored for derivations that require features not in this list.

This sets the corresponding nix.buildMachines.\*.supportedFeatures option.

Type: list of string

Default: [ "kvm" "benchmark" "big-parallel" ]

Example: [ "kvm" "big-parallel" ]

Declared by:

<nix-darwin/modules/nix/linux-builder.nix>
nix.linux-builder.systems
This option specifies system types the build machine can execute derivations on.

This sets the corresponding nix.buildMachines.\*.systems option.

Type: list of string

Default:

''
The `nixpkgs.hostPlatform.system` of the build machine's final NixOS configuration.
''
Example:

[
"x86_64-linux"
"aarch64-linux"
]

Declared by:

<nix-darwin/modules/nix/linux-builder.nix>
nix.linux-builder.workingDirectory
The working directory of the Linux builder daemon process.

Type: string

Default: "/var/lib/linux-builder"

Declared by:

<nix-darwin/modules/nix/linux-builder.nix>
nix.nixPath
The default Nix expression search path, used by the Nix evaluator to look up paths enclosed in angle brackets (e.g. <nixpkgs>).

Named entries can be specified using an attribute set, if an entry is configured multiple times the value with the lowest ordering will be used.

Type: nix path

Default:

lib.optionals cfg.channel.enable [

# Include default path <darwin-config>.

{ darwin-config = "${config.environment.darwinConfig}"; }
"/nix/var/nix/profiles/per-user/root/channels"
]

Declared by:

<nix-darwin/modules/nix>
nix.nrBuildUsers
Number of nixbld user accounts created to perform secure concurrent builds. If you receive an error message saying that “all build users are currently in use”, you should increase this value.

Type: signed integer

Default: 0

Declared by:

<nix-darwin/modules/nix>
nix.optimise.automatic
Automatically run the nix store optimiser at a specific time.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/nix-optimise>
nix.optimise.interval
The calendar interval at which the optimiser will run. See the serviceConfig.StartCalendarInterval option of the launchd module for more info.

Type: (submodule) or unique (non-empty (list of (submodule)))

Default:

[
{
Hour = 4;
Minute = 15;
Weekday = 7;
}
]
Declared by:

<nix-darwin/modules/services/nix-optimise>
nix.registry
A system-wide flake registry.

Type: attribute set of (submodule)

Default: { }

Declared by:

<nix-darwin/modules/nix>
nix.registry.<name>.exact
Whether the from reference needs to match exactly. If set, a from reference like nixpkgs does not match with a reference like nixpkgs/nixos-20.03.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/nix>
nix.registry.<name>.flake
The flake input from is rewritten to.

Type: null or (attribute set)

Default: null

Example: nixpkgs

Declared by:

<nix-darwin/modules/nix>
nix.registry.<name>.from
The flake reference to be rewritten.

Type: attribute set of (string or signed integer or boolean or package)

Example:

{
id = "nixpkgs";
type = "indirect";
}
Declared by:

<nix-darwin/modules/nix>
nix.registry.<name>.to
The flake reference from is rewritten to.

Type: attribute set of (string or signed integer or boolean or package)

Example:

{
owner = "my-org";
repo = "my-nixpkgs";
type = "github";
}
Declared by:

<nix-darwin/modules/nix>
nix.settings
Configuration for Nix, see https://nixos.org/manual/nix/stable/#sec-conf-file for avalaible options. The value declared here will be translated directly to the key-value pairs Nix expects.

Nix configurations defined under nix.\* will be translated and applied to this option. In addition, configuration specified in nix.extraOptions which will be appended verbatim to the resulting config file.

Type: attribute set of (Nix config atom (null, bool, int, float, str, path or package) or list of (Nix config atom (null, bool, int, float, str, path or package)))

Default: { }

Declared by:

<nix-darwin/modules/nix>
nix.settings.allowed-users
A list of names of users (separated by whitespace) that are allowed to connect to the Nix daemon. As with nix.settings.trusted-users, you can specify groups by prefixing them with @. Also, you can allow all users by specifying _. The default is _. Note that trusted users are always allowed to connect.

Type: list of string

Default:

[
"*"
]
Example:

[
"@admin"
"@builders"
"alice"
"bob"
]
Declared by:

<nix-darwin/modules/nix>
nix.settings.auto-optimise-store
If set to true, Nix automatically detects files in the store that have identical contents, and replaces them with hard links to a single copy. This saves disk space. If set to false (the default), you can enable nix.optimise.automatic to run nix-store --optimise periodically to get rid of duplicate files. You can also run nix-store --optimise manually.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/nix>
nix.settings.cores
This option defines the maximum number of concurrent tasks during one build. It affects, e.g., -j option for make. The special value 0 means that the builder should use all available CPU cores in the system. Some builds may become non-deterministic with this option; use with care! Packages will only be affected if enableParallelBuilding is set for them.

Type: signed integer

Default: 0

Example: 64

Declared by:

<nix-darwin/modules/nix>
nix.settings.extra-sandbox-paths
Directories from the host filesystem to be included in the sandbox.

Type: list of string

Default: [ ]

Example:

[
"/dev"
"/proc"
]
Declared by:

<nix-darwin/modules/nix>
nix.settings.max-jobs
This option defines the maximum number of jobs that Nix will try to build in parallel. The default is auto, which means it will use all available logical cores. It is recommend to set it to the total number of logical cores in your system (e.g., 16 for two CPUs with 4 cores each and hyper-threading).

Type: signed integer or value “auto” (singular enum)

Default: "auto"

Example: 64

Declared by:

<nix-darwin/modules/nix>
nix.settings.require-sigs
If enabled (the default), Nix will only download binaries from binary caches if they are cryptographically signed with any of the keys listed in nix.settings.trusted-public-keys. If disabled, signatures are neither required nor checked, so it’s strongly recommended that you use only trustworthy caches and https to prevent man-in-the-middle attacks.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/nix>
nix.settings.sandbox
If set, Nix will perform builds in a sandboxed environment that it will set up automatically for each build. This prevents impurities in builds by disallowing access to dependencies outside of the Nix store by using network and mount namespaces in a chroot environment. It doesn’t affect derivation hashes, so changing this option will not trigger a rebuild of packages.

Type: boolean or value “relaxed” (singular enum)

Default: false

Declared by:

<nix-darwin/modules/nix>
nix.settings.substituters
List of binary cache URLs used to obtain pre-built binaries of Nix packages.

By default https://cache.nixos.org/ is added.

Type: list of string

Declared by:

<nix-darwin/modules/nix>
nix.settings.trusted-public-keys
List of public keys used to sign binary caches. If nix.settings.trusted-public-keys is enabled, then Nix will use a binary from a binary cache if and only if it is signed by any of the keys listed here. By default, only the key for cache.nixos.org is included.

Type: list of string

Example:

[
"hydra.nixos.org-1:CNHJZBh9K4tP3EKF6FkkgeVYsS3ohTl+oS0Qa8bezVs="
]
Declared by:

<nix-darwin/modules/nix>
nix.settings.trusted-substituters
List of binary cache URLs that non-root users can use (in addition to those specified using nix.settings.substituters) by passing --option binary-caches to Nix commands.

Type: list of string

Default: [ ]

Example:

[
"https://hydra.nixos.org/"
]
Declared by:

<nix-darwin/modules/nix>
nix.settings.trusted-users
A list of names of users that have additional rights when connecting to the Nix daemon, such as the ability to specify additional binary caches, or to import unsigned NARs. You can also specify groups by prefixing them with @; for instance, @admin means all users in the wheel group.

Type: list of string

Example:

[
"root"
"alice"
"@admin"
]
Declared by:

<nix-darwin/modules/nix>
nixpkgs.buildPlatform
Specifies the platform on which nix-darwin should be built. By default, nix-darwin is built on the system where it runs, but you can change where it’s built. Setting this option will cause nix-darwin to be cross-compiled.

For instance, if you’re doing distributed multi-platform deployment, or if you’re building machines, you can set this to match your development system and/or build farm.

Ignored when nixpkgs.pkgs is set.

Type: string or (attribute set)

Default: config.nixpkgs.hostPlatform

Example:

{
system = "x86_64-darwin";
}
Declared by:

<nix-darwin/modules/nix/nixpkgs.nix>
nixpkgs.config
Global configuration for Nixpkgs. The complete list of Nixpkgs configuration options is in the Nixpkgs manual section on global configuration.

Ignored when nixpkgs.pkgs is set.

Type: nixpkgs config

Default: { }

Example:

{ allowBroken = true; allowUnfree = true; }

Declared by:

<nix-darwin/modules/nix/nixpkgs.nix>
nixpkgs.flake.setFlakeRegistry
Whether to pin nixpkgs in the system-wide flake registry (/etc/nix/registry.json) to the store path of the sources of nixpkgs used to build the nix-darwin system.

This is on by default for nix-darwin configurations built with flakes.

This option makes nix run nixpkgs#hello reuse dependencies from the system, avoid refetching nixpkgs, and have a consistent result every time.

Note that this option makes the nix-darwin closure depend on the nixpkgs sources, which may add undesired closure size if the system will not have any nix commands run on it.

Type: boolean

Default: config.nix.enable && config.nixpkgs.flake.source != null

Declared by:

<nix-darwin/modules/nix/nixpkgs-flake.nix>
nixpkgs.flake.setNixPath
Whether to set NIX_PATH to include nixpkgs=flake:nixpkgs such that <nixpkgs> lookups receive the version of nixpkgs that the system was built with, in concert with nixpkgs.flake.setFlakeRegistry.

This is on by default for nix-darwin configurations built with flakes.

This makes nix-build '<nixpkgs>' -A hello work out of the box on flake systems.

Note that this option makes the nix-darwin closure depend on the nixpkgs sources, which may add undesired closure size if the system will not have any nix commands run on it.

Type: boolean

Default: config.nix.enable && nixpkgs.flake.source != null

Declared by:

<nix-darwin/modules/nix/nixpkgs-flake.nix>
nixpkgs.flake.source
The path to the nixpkgs sources used to build the system. This is automatically set up to be the store path of the nixpkgs flake used to build the system if using nixpkgs.lib.darwinSystem, and is otherwise null by default.

This can also be optionally set if the nix-darwin system is not built with a flake but still uses pinned sources: set this to the store path for the nixpkgs sources used to build the system, as may be obtained by builtins.fetchTarball, for example.

Note: the name of the store path must be “source” due to https://github.com/NixOS/nix/issues/7075.

Type: null or string or absolute path

Default: "if (using nix-darwin.lib.darwinSystem) then nixpkgs.source else null"

Example: "builtins.fetchTarball { name = \"source\"; sha256 = \"sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\"; url = \"https://github.com/nixos/nixpkgs/archive/somecommit.tar.gz\"; }"

Declared by:

<nix-darwin/modules/nix/nixpkgs-flake.nix>
nixpkgs.hostPlatform
Specifies the platform where the nix-darwin configuration will run.

To cross-compile, set also nixpkgs.buildPlatform.

Ignored when nixpkgs.pkgs is set.

Type: string or (attribute set)

Example:

{
system = "aarch64-darwin";
}
Declared by:

<nix-darwin/modules/nix/nixpkgs.nix>
nixpkgs.overlays
List of overlays to apply to Nixpkgs. This option allows modifying the Nixpkgs package set accessed through the pkgs module argument.

For details, see the Overlays chapter in the Nixpkgs manual.

If the nixpkgs.pkgs option is set, overlays specified using nixpkgs.overlays will be applied after the overlays that were already included in nixpkgs.pkgs.

Type: list of (nixpkgs overlay)

Default: [ ]

Example:

[
(self: super: {
openssh = super.openssh.override {
hpnSupport = true;
kerberos = self.libkrb5;
};
})
]

Declared by:

<nix-darwin/modules/nix/nixpkgs.nix>
nixpkgs.pkgs
If set, the pkgs argument to all nix-darwin modules is the value of this option, extended with nixpkgs.overlays, if that is also set. The nix-darwin and Nixpkgs architectures must match. Any other options in nixpkgs.\*, notably config, will be ignored.

The default value imports the Nixpkgs from nixpkgs.source. The config, overlays, localSystem, and crossSystem are based on this option’s siblings.

This option can be used to increase the performance of evaluation, or to create packages that depend on a container that should be built with the exact same evaluation of Nixpkgs, for example. Applications like this should set their default value using lib.mkDefault, so user-provided configuration can override it without using lib.

Type: An evaluation of Nixpkgs; the top level attribute set of packages

Example: import <nixpkgs> {}

Declared by:

<nix-darwin/modules/nix/nixpkgs.nix>
nixpkgs.source
The path to import Nixpkgs from. If you’re setting a custom nixpkgs.pkgs or \_module.args.pkgs, setting this to something with rev and shortRev attributes (such as a flake input or builtins.fetchGit result) will also set system.nixpkgsRevision and related options. (nix-darwin only)

Type: absolute path

Default: <nixpkgs> or nix-darwin’s nixpkgs flake input

Declared by:

<nix-darwin/modules/nix/nixpkgs.nix>
nixpkgs.system
Specifies the Nix platform type on which nix-darwin should be built. It is better to specify nixpkgs.hostPlatform instead.

Ignored when nixpkgs.pkgs or nixpkgs.hostPlatform is set.

Type: string

Default: Traditionally builtins.currentSystem, but unset when invoking nix-darwin through lib.darwinSystem.

Example: "x86_64-darwin"

Declared by:

<nix-darwin/modules/nix/nixpkgs.nix>
power.restartAfterFreeze
Whether to restart the computer after a system freeze.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/power>
power.restartAfterPowerFailure
Whether to restart the computer after a power failure.

Option is not supported on all devices.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/power>
power.sleep.allowSleepByPowerButton
Whether the power button can sleep the computer.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/power/sleep.nix>
power.sleep.computer
Amount of idle time (in minutes) until the computer sleeps.

"never" disables computer sleeping.

The system might not be considered idle before connected displays sleep, as per the power.sleep.display option.

Type: null or positive integer, meaning >0, or value “never” (singular enum)

Default: null

Example: "never"

Declared by:

<nix-darwin/modules/power/sleep.nix>
power.sleep.display
Amount of idle time (in minutes) until displays sleep.

"never" disables display sleeping.

Type: null or positive integer, meaning >0, or value “never” (singular enum)

Default: null

Example: "never"

Declared by:

<nix-darwin/modules/power/sleep.nix>
power.sleep.harddisk
Amount of idle time (in minutes) until hard disks sleep.

"never" disables hard disk sleeping.

Type: null or positive integer, meaning >0, or value “never” (singular enum)

Default: null

Example: "never"

Declared by:

<nix-darwin/modules/power/sleep.nix>
programs.\_1password.enable
Whether to enable the 1Password CLI tool.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/programs/\_1password.nix>
programs.\_1password.package
The 1Password CLI package to use.

Type: package

Default: pkgs.\_1password-cli

Declared by:

<nix-darwin/modules/programs/\_1password.nix>
programs.\_1password-gui.enable
Whether to enable the 1Password GUI application.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/programs/\_1password-gui.nix>
programs.\_1password-gui.package
The 1Password GUI package to use.

Type: package

Default: pkgs.\_1password-gui

Declared by:

<nix-darwin/modules/programs/\_1password-gui.nix>
programs.arqbackup.enable
Whether to enable Arq backup.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/programs/arqbackup.nix>
programs.arqbackup.package
The arq package to use.

Type: package

Declared by:

<nix-darwin/modules/programs/arqbackup.nix>
programs.bash.enable
Whether to configure bash as an interactive shell.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/programs/bash>
programs.bash.completion.enable
Enable bash completion for all interactive bash shells.

NOTE: This doesn’t work with bash 3.2, which is installed by default on macOS by Apple.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/programs/bash>
programs.bash.completion.package
The bash-completion package to use.

Type: package

Default: pkgs.bash-completion

Declared by:

<nix-darwin/modules/programs/bash>
programs.bash.interactiveShellInit
Shell script code called during interactive bash shell initialisation.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/programs/bash>
programs.direnv.enable
Whether to enable direnv integration. Takes care of both installation and setting up the sourcing of the shell. Additionally enables nix-direnv integration. .

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/programs/direnv.nix>
programs.direnv.package
The direnv package to use.

Type: package

Default: pkgs.direnv

Declared by:

<nix-darwin/modules/programs/direnv.nix>
programs.direnv.direnvrcExtra
Extra lines to append to the sourced direnvrc

Type: strings concatenated with “\n”

Default: ""

Example:

''
export FOO="foo"
echo "loaded direnv!"
''
Declared by:

<nix-darwin/modules/programs/direnv.nix>
programs.direnv.finalPackage
The wrapped direnv package.

Type: package (read only)

Declared by:

<nix-darwin/modules/programs/direnv.nix>
programs.direnv.loadInNixShell
Whether to enable loading direnv in nix-shell nix shell or nix develop .

Type: boolean

Default: true

Example: true

Declared by:

<nix-darwin/modules/programs/direnv.nix>
programs.direnv.nix-direnv.enable
Whether to enable a faster, persistent implementation of use_nix and use_flake, to replace the built-in one .

Type: boolean

Default: true

Example: true

Declared by:

<nix-darwin/modules/programs/direnv.nix>
programs.direnv.nix-direnv.package
The nix-direnv package to use.

Type: package

Default: pkgs.nix-direnv

Declared by:

<nix-darwin/modules/programs/direnv.nix>
programs.direnv.settings
Direnv configuration. Refer to direnv.toml(1).

Type: TOML value

Default: { }

Example:

{
global = {
log_format = "-";
log_filter = "^$";
};
}

Declared by:

<nix-darwin/modules/programs/direnv.nix>
programs.direnv.silent
Whether to enable the hiding of direnv logging .

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/programs/direnv.nix>
programs.fish.enable
Whether to configure fish as an interactive shell.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/programs/fish.nix>
programs.fish.package
The fish package to use.

Type: package

Default: pkgs.fish

Declared by:

<nix-darwin/modules/programs/fish.nix>
programs.fish.babelfishPackage
The babelfish package to use when useBabelfish is set to true.

Type: package

Default: <derivation babelfish-1.2.1>

Declared by:

<nix-darwin/modules/programs/fish.nix>
programs.fish.interactiveShellInit
Shell script code called during interactive fish shell initialisation.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/programs/fish.nix>
programs.fish.loginShellInit
Shell script code called during fish login shell initialisation.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/programs/fish.nix>
programs.fish.promptInit
Shell script code used to initialise fish prompt.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/programs/fish.nix>
programs.fish.shellAliases
Set of aliases for fish shell. See environment.shellAliases for an option format description.

Type: attribute set

Default: { }

Declared by:

<nix-darwin/modules/programs/fish.nix>
programs.fish.shellInit
Shell script code called during fish shell initialisation.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/programs/fish.nix>
programs.fish.useBabelfish
If enabled, the configured environment will be translated to native fish using babelfish. Otherwise, foreign-env will be used.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/programs/fish.nix>
programs.fish.vendor.completions.enable
Whether fish should use completion files provided by other packages.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/programs/fish.nix>
programs.fish.vendor.config.enable
Whether fish should source configuration snippets provided by other packages.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/programs/fish.nix>
programs.fish.vendor.functions.enable
Whether fish should autoload fish functions provided by other packages.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/programs/fish.nix>
programs.gnupg.agent.enable
Enables GnuPG agent for every user session.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/programs/gnupg.nix>
programs.gnupg.agent.enableSSHSupport
Enable SSH agent support in GnuPG agent. Also sets SSH_AUTH_SOCK environment variable correctly.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/programs/gnupg.nix>
programs.info.enable
Whether to enable info pages and the info command.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/programs/info>
programs.man.enable
Whether to enable manual pages and the man command. This also includes “man” outputs of all systemPackages.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/programs/man.nix>
programs.nix-index.enable
Whether to enable nix-index and its command-not-found helper.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/programs/nix-index>
programs.nix-index.package
This option specifies the nix-index package to use.

Type: package

Default: "pkgs.nix-index"

Declared by:

<nix-darwin/modules/programs/nix-index>
programs.ssh.extraConfig
Extra configuration text loaded in ssh_config. See ssh_config(5) for help.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/programs/ssh.nix>
programs.ssh.knownHosts
The set of system-wide known SSH hosts. To make simple setups more convenient the name of an attribute in this set is used as a host name for the entry. This behaviour can be disabled by setting hostNames explicitly. You can use extraHostNames to add additional host names without disabling this default.

Type: attribute set of (submodule)

Default: { }

Example:

{
myhost = {
extraHostNames = [ "myhost.mydomain.com" "10.10.1.4" ];
publicKeyFile = ./pubkeys/myhost_ssh_host_dsa_key.pub;
};
"myhost2.net".publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILIRuJ8p1Fi+m6WkHV0KWnRfpM1WxoW8XAS+XvsSKsTK";
"myhost2.net/dsa" = {
hostNames = [ "myhost2.net" ];
publicKeyFile = ./pubkeys/myhost2_ssh_host_dsa_key.pub;
};
}

Declared by:

<nix-darwin/modules/programs/ssh.nix>
programs.ssh.knownHosts.<name>.certAuthority
This public key is an SSH certificate authority, rather than an individual host’s key.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/programs/ssh.nix>
programs.ssh.knownHosts.<name>.extraHostNames
A list of additional host names and/or IP numbers used for accessing the host’s ssh service. This list is ignored if hostNames is set explicitly.

Type: list of string

Default: [ ]

Declared by:

<nix-darwin/modules/programs/ssh.nix>
programs.ssh.knownHosts.<name>.hostNames
The set of system-wide known SSH hosts. To make simple setups more convenient the name of an attribute in this set is used as a host name for the entry. This behaviour can be disabled by setting hostNames explicitly. You can use extraHostNames to add additional host names without disabling this default.

Type: list of string

Default:

[
"‹name›"
]
Declared by:

<nix-darwin/modules/programs/ssh.nix>
programs.ssh.knownHosts.<name>.publicKey
The public key data for the host. You can fetch a public key from a running SSH server with the ssh-keyscan command. The public key should not include any host names, only the key type and the key itself.

Type: null or string

Default: null

Example: "ecdsa-sha2-nistp521 AAAAE2VjZHN...UEPg=="

Declared by:

<nix-darwin/modules/programs/ssh.nix>
programs.ssh.knownHosts.<name>.publicKeyFile
The path to the public key file for the host. The public key file is read at build time and saved in the Nix store. You can fetch a public key file from a running SSH server with the ssh-keyscan command. The content of the file should follow the same format as described for the publicKey option.

Type: null or absolute path

Default: null

Declared by:

<nix-darwin/modules/programs/ssh.nix>
programs.tmux.enable
Whether to configure tmux.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/programs/tmux.nix>
programs.tmux.enableFzf
Enable fzf keybindings for selecting tmux sessions and panes.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/programs/tmux.nix>
programs.tmux.enableMouse
Enable mouse support for tmux.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/programs/tmux.nix>
programs.tmux.enableSensible
Enable sensible configuration options for tmux.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/programs/tmux.nix>
programs.tmux.enableVim
Enable vim style keybindings for copy mode, and navigation of tmux panes.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/programs/tmux.nix>
programs.tmux.extraConfig
Extra configuration to add to tmux.conf.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/programs/tmux.nix>
programs.tmux.iTerm2
Cater to iTerm2 and its tmux integration, as appropriate.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/programs/tmux.nix>
programs.tmux.tmuxOptions.<name>.enable
Whether this file should be generated. This option allows specific files to be disabled.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/programs/tmux.nix>
programs.tmux.tmuxOptions.<name>.source
Path of the source file.

Type: absolute path

Declared by:

<nix-darwin/modules/programs/tmux.nix>
programs.tmux.tmuxOptions.<name>.target
Name of symlink. Defaults to the attribute name.

Type: string

Default: "‹name›"

Declared by:

<nix-darwin/modules/programs/tmux.nix>
programs.tmux.tmuxOptions.<name>.text
Text of the file.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/programs/tmux.nix>
programs.vim.enable
Whether to configure vim.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/programs/vim.nix>
programs.vim.enableSensible
Enable sensible configuration options for vim.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/programs/vim.nix>
programs.vim.extraKnownPlugins
Custom plugin declarations to add to VAM’s knownPlugins.

Type: attribute set of package

Default: { }

Example:

{
vim-jsx = pkgs.vimUtils.buildVimPluginFrom2Nix {
name = "vim-javascript-2016-07-29";
src = pkgs.fetchgit {
url = "git://github.com/mxw/vim-jsx";
rev = "261114c925ea81eeb4db1651cc1edced66d6b5d6";
sha256 = "17pffzwnvsimnnr4ql1qifdh4a0sqqsmcwfiqqzgglvsnzw5vpls";
};
dependencies = [];

};
}

Declared by:

<nix-darwin/modules/programs/vim.nix>
programs.vim.plugins
VAM plugin dictionaries to use for vim_configurable.

Type: list of (attribute set)

Default: [ ]

Example:

[
{
names = [
"surround"
"vim-nix"
];
}
]
Declared by:

<nix-darwin/modules/programs/vim.nix>
programs.vim.vimConfig
Extra vimrcConfig to use for vim_configurable.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/programs/vim.nix>
programs.vim.vimOptions.<name>.enable
Whether this file should be generated. This option allows specific files to be disabled.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/programs/vim.nix>
programs.vim.vimOptions.<name>.source
Path of the source file.

Type: absolute path

Declared by:

<nix-darwin/modules/programs/vim.nix>
programs.vim.vimOptions.<name>.target
Name of symlink. Defaults to the attribute name.

Type: string

Default: "‹name›"

Declared by:

<nix-darwin/modules/programs/vim.nix>
programs.vim.vimOptions.<name>.text
Text of the file.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/programs/vim.nix>
programs.zsh.enable
Whether to configure zsh as an interactive shell.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/programs/zsh>
programs.zsh.enableAutosuggestions
Enable zsh-autosuggestions.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/programs/zsh>
programs.zsh.enableBashCompletion
Enable bash completion for all interactive zsh shells.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/programs/zsh>
programs.zsh.enableCompletion
Enable zsh completion for all interactive zsh shells.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/programs/zsh>
programs.zsh.enableFastSyntaxHighlighting
Whether to enable zsh-fast-syntax-highlighting.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/programs/zsh>
programs.zsh.enableFzfCompletion
Enable fzf completion.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/programs/zsh>
programs.zsh.enableFzfGit
Enable fzf keybindings for C-g git browsing.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/programs/zsh>
programs.zsh.enableFzfHistory
Enable fzf keybinding for Ctrl-r history search.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/programs/zsh>
programs.zsh.enableGlobalCompInit
Enable execution of compinit call for all interactive zsh shells.

This option can be disabled if the user wants to extend its fpath and a custom compinit call in the local config is required.

Type: boolean

Default: config.programs.zsh.enableCompletion

Declared by:

<nix-darwin/modules/programs/zsh>
programs.zsh.enableSyntaxHighlighting
Enable zsh-syntax-highlighting.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/programs/zsh>
programs.zsh.interactiveShellInit
Shell script code called during interactive zsh shell initialisation.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/programs/zsh>
programs.zsh.loginShellInit
Shell script code called during zsh login shell initialisation.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/programs/zsh>
programs.zsh.promptInit
Shell script code used to initialise the zsh prompt.

Type: strings concatenated with “\n”

Default: "autoload -U promptinit && promptinit && prompt suse && setopt prompt_sp"

Declared by:

<nix-darwin/modules/programs/zsh>
programs.zsh.shellInit
Shell script code called during zsh shell initialisation.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/programs/zsh>
programs.zsh.variables
A set of environment variables used in the global environment. These variables will be set on shell initialisation. The value of each variable can be either a string or a list of strings. The latter is concatenated, interspersed with colon characters.

Type: attribute set of (string or list of string)

Default: { }

Declared by:

<nix-darwin/modules/programs/zsh>
security.pam.services.sudo_local.enable
Whether to enable managing /etc/pam.d/sudo_local with nix-darwin.

Type: boolean

Default: true

Example: false

Declared by:

<nix-darwin/modules/security/pam.nix>
security.pam.services.sudo_local.reattach
Whether to enable reattaching a program to the user’s bootstrap session.

This fixes Touch ID for sudo not working inside tmux and screen.

This allows programs like tmux and screen that run in the background to survive across user sessions to work with PAM services that are tied to the bootstrap session.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/security/pam.nix>
security.pam.services.sudo_local.text
Contents of /etc/pam.d/sudo_local

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/security/pam.nix>
security.pam.services.sudo_local.touchIdAuth
Whether to enable Touch ID with sudo.

This will also allow your Apple Watch to be used for sudo. If this doesn’t work, you can go into System Settings > Touch ID & Password and toggle the switch for your Apple Watch.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/security/pam.nix>
security.pam.services.sudo_local.watchIdAuth
Use Apple Watch for sudo authentication, for devices without Touch ID or laptops with lids closed, consider using this.

When enabled, you can use your Apple Watch to authenticate sudo commands. If this doesn’t work, you can go into System Settings > Touch ID & Password and toggle the switch for your Apple Watch.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/security/pam.nix>
security.pki.caCertificateBlacklist
A list of blacklisted CA certificate names that won’t be imported from the Mozilla Trust Store into /etc/ssl/certs/ca-certificates.crt. Use the names from that file.

Type: list of string

Default: [ ]

Example:

[
"WoSign"
"WoSign China"
"CA WoSign ECC Root"
"Certification Authority of WoSign G2"
]
Declared by:

<nix-darwin/modules/security/pki>
security.pki.certificateFiles
A list of files containing trusted root certificates in PEM format. These are concatenated to form /etc/ssl/certs/ca-certificates.crt, which is used by many programs that use OpenSSL, such as curl and git.

Type: list of absolute path

Default: [ ]

Example: [ "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt" ]

Declared by:

<nix-darwin/modules/security/pki>
security.pki.certificates
A list of trusted root certificates in PEM format.

Type: list of string

Default: [ ]

Example:

[ ''
NixOS.org
=========
-----BEGIN CERTIFICATE-----
MIIGUDCCBTigAwIBAgIDD8KWMA0GCSqGSIb3DQEBBQUAMIGMMQswCQYDVQQGEwJJ
TDEWMBQGA1UEChMNU3RhcnRDb20gTHRkLjErMCkGA1UECxMiU2VjdXJlIERpZ2l0
...
-----END CERTIFICATE-----
''
]

Declared by:

<nix-darwin/modules/security/pki>
security.pki.installCACerts
Whether to enable certificate management with nix-darwin.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/security/pki>
security.sandbox.profiles
Definition of sandbox profiles.

Type: attribute set of (submodule)

Default: { }

Declared by:

<nix-darwin/modules/security/sandbox>
security.sandbox.profiles.<name>.allowLocalNetworking
Whether to allow localhost network access inside the sandbox.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/security/sandbox>
security.sandbox.profiles.<name>.allowNetworking
Whether to allow network access inside the sandbox.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/security/sandbox>
security.sandbox.profiles.<name>.allowSystemPaths
Whether to allow read access to FHS paths like /etc and /var.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/security/sandbox>
security.sandbox.profiles.<name>.closure
List of store paths to make accessible.

Type: list of package

Default: [ ]

Declared by:

<nix-darwin/modules/security/sandbox>
security.sandbox.profiles.<name>.readablePaths
List of paths that should be read-only inside the sandbox.

Type: list of absolute path

Default: [ ]

Declared by:

<nix-darwin/modules/security/sandbox>
security.sandbox.profiles.<name>.writablePaths
List of paths that should be read/write inside the sandbox.

Type: list of absolute path

Default: [ ]

Declared by:

<nix-darwin/modules/security/sandbox>
security.sudo.extraConfig
Extra configuration text appended to sudoers.

Type: null or strings concatenated with “\n”

Default: null

Declared by:

<nix-darwin/modules/security/sudo.nix>
security.sudo.keepTerminfo
Whether to preserve the TERMINFO and TERMINFO_DIRS environment variables, for root and the admin group.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/config/terminfo.nix>
services.aerospace.enable
Whether to enable AeroSpace window manager.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/services/aerospace>
services.aerospace.package
The aerospace package to use.

Type: package

Default: pkgs.aerospace

Declared by:

<nix-darwin/modules/services/aerospace>
services.aerospace.settings
AeroSpace configuration, see <link xlink:href=“https://nikitabobko.github.io/AeroSpace/guide#configuring-aerospace”/> for supported values.

Type: TOML value

Default: { }

Example:

{
gaps = {
outer.left = 8;
outer.bottom = 8;
outer.top = 8;
outer.right = 8;
};
mode.main.binding = {
alt-h = "focus left";
alt-j = "focus down";
alt-k = "focus up";
alt-l = "focus right";
};
}

Declared by:

<nix-darwin/modules/services/aerospace>
services.aerospace.settings.enable-normalization-flatten-containers
Containers that have only one child are “flattened”.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/services/aerospace>
services.aerospace.settings.enable-normalization-opposite-orientation-for-nested-containers
Containers that nest into each other must have opposite orientations.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/services/aerospace>
services.aerospace.settings.accordion-padding
Padding between windows in an accordion container.

Type: signed integer

Default: 30

Declared by:

<nix-darwin/modules/services/aerospace>
services.aerospace.settings.after-login-command
Do not use AeroSpace to run commands after login. (Managed by launchd instead)

Type: list of string

Default: [ ]

Declared by:

<nix-darwin/modules/services/aerospace>
services.aerospace.settings.after-startup-command
Add commands that run after AeroSpace startup

Type: list of string

Default: [ ]

Example:

[
"layout tiles"
]
Declared by:

<nix-darwin/modules/services/aerospace>
services.aerospace.settings.default-root-container-layout
Default layout for the root container.

Type: one of “tiles”, “accordion”

Default: "tiles"

Declared by:

<nix-darwin/modules/services/aerospace>
services.aerospace.settings.default-root-container-orientation
Default orientation for the root container.

Type: one of “horizontal”, “vertical”, “auto”

Default: "auto"

Declared by:

<nix-darwin/modules/services/aerospace>
services.aerospace.settings.exec-on-workspace-change
Commands to run every time workspace changes.

Type: list of string

Default: [ ]

Example:

[
"/bin/bash"
"-c"
"sketchybar --trigger aerospace_workspace_change FOCUSED=$AEROSPACE_FOCUSED_WORKSPACE"
]
Declared by:

<nix-darwin/modules/services/aerospace>
services.aerospace.settings.key-mapping.preset
Keymapping preset.

Type: one of “qwerty”, “dvorak”

Default: "qwerty"

Declared by:

<nix-darwin/modules/services/aerospace>
services.aerospace.settings.on-focus-changed
Commands to run every time focused window or workspace changes.

Type: list of string

Default: [ ]

Declared by:

<nix-darwin/modules/services/aerospace>
services.aerospace.settings.on-focused-monitor-changed
Commands to run every time focused monitor changes.

Type: list of string

Default:

[
"move-mouse monitor-lazy-center"
]
Declared by:

<nix-darwin/modules/services/aerospace>
services.aerospace.settings.on-window-detected
Commands to run every time a new window is detected with optional conditions.

Type: list of (submodule)

Default: [ ]

Example:

[
{
check-further-callbacks = false;
if = {
app-id = "Another.Cool.App";
app-name-regex-substring = "CoolApp";
during-aerospace-startup = false;
window-title-regex-substring = "Title";
workspace = "cool-workspace";
};
run = [
"move-node-to-workspace m"
"resize-node"
];
}
]
Declared by:

<nix-darwin/modules/services/aerospace>
services.aerospace.settings.on-window-detected.\*.check-further-callbacks
Whether to check further callbacks after this rule (optional).

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/services/aerospace>
services.aerospace.settings.on-window-detected.\*.if
Conditions for detecting a window.

Type: submodule

Default: { }

Declared by:

<nix-darwin/modules/services/aerospace>
services.aerospace.settings.on-window-detected.\*.if.app-id
The application ID to match (optional).

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/services/aerospace>
services.aerospace.settings.on-window-detected.\*.if.app-name-regex-substring
Regex substring to match the app name (optional).

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/services/aerospace>
services.aerospace.settings.on-window-detected.\*.if.during-aerospace-startup
Whether to match during aerospace startup (optional).

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/services/aerospace>
services.aerospace.settings.on-window-detected.\*.if.window-title-regex-substring
Substring to match in the window title (optional).

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/services/aerospace>
services.aerospace.settings.on-window-detected.\*.if.workspace
The workspace name to match (optional).

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/services/aerospace>
services.aerospace.settings.on-window-detected.\*.run
Commands to execute when the conditions match (required).

Type: string or list of string

Example:

[
"move-node-to-workspace m"
"resize-node"
]
Declared by:

<nix-darwin/modules/services/aerospace>
services.aerospace.settings.start-at-login
Do not start AeroSpace at login. (Managed by launchd instead)

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/aerospace>
services.aerospace.settings.workspace-to-monitor-force-assignment
Map workspaces to specific monitors. Left-hand side is the workspace name, and right-hand side is the monitor pattern.

Type: attribute set of (signed integer or string or list of string)

Default: { }

Example:

{
"1" = 1;
"2" = "main";
"3" = "secondary";
"4" = "built-in";
"5" = "^built-in retina display$";
"6" = [
"secondary"
"dell"
];
}
Declared by:

<nix-darwin/modules/services/aerospace>
services.autossh.sessions
List of AutoSSH sessions to start as launchd daemon. Each daemon is named ‘autossh-{session.name}’.

Type: list of (submodule)

Default: [ ]

Example:

[
{
extraArguments = "-N -D4343 billremote@socks.host.net";
monitoringPort = 20000;
name = "socks-peer";
user = "bill";
}
]
Declared by:

<nix-darwin/modules/services/autossh.nix>
services.autossh.sessions.\*.extraArguments
Arguments to be passed to AutoSSH and retransmitted to SSH process. Some meaningful options include -N (don’t run remote command), -D (open SOCKS proxy on local port), -R (forward remote port), -L (forward local port), -v (Enable debug). Check ssh manual for the complete list.

Type: string

Example: "-N -D4343 bill@socks.example.net"

Declared by:

<nix-darwin/modules/services/autossh.nix>
services.autossh.sessions.\*.monitoringPort
Port to be used by AutoSSH for peer monitoring. Note, that AutoSSH also uses mport+1. Value of 0 disables the keep-alive style monitoring

Type: signed integer

Default: 0

Example: 20000

Declared by:

<nix-darwin/modules/services/autossh.nix>
services.autossh.sessions.\*.name
Name of the local AutoSSH session

Type: string

Example: "socks-peer"

Declared by:

<nix-darwin/modules/services/autossh.nix>
services.autossh.sessions.\*.user
Name of the user the AutoSSH session should run as

Type: string

Example: "bill"

Declared by:

<nix-darwin/modules/services/autossh.nix>
services.buildkite-agents
Attribute set of buildkite agents. The attribute key is combined with the hostname and a unique integer to create the final agent name. This can be overridden by setting the name attribute.

Type: attribute set of (submodule)

Default: { }

Declared by:

<nix-darwin/modules/services/buildkite-agents.nix>
services.buildkite-agents.<name>.enable
Whether to enable this buildkite agent

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/services/buildkite-agents.nix>
services.buildkite-agents.<name>.package
Which buildkite-agent derivation to use

Type: package

Default: pkgs.buildkite-agent

Declared by:

<nix-darwin/modules/services/buildkite-agents.nix>
services.buildkite-agents.<name>.dataDir
The workdir for the agent

Type: string

Default: "/var/lib/buildkite-agent-‹name›"

Declared by:

<nix-darwin/modules/services/buildkite-agents.nix>
services.buildkite-agents.<name>.extraConfig
Extra lines to be added verbatim to the configuration file.

Type: strings concatenated with “\n”

Default: ""

Example: "debug=true"

Declared by:

<nix-darwin/modules/services/buildkite-agents.nix>
services.buildkite-agents.<name>.hooks.checkout
The checkout hook script will replace the default checkout routine of the bootstrap.sh script. You can use this hook to do your own SCM checkout behaviour

Type: null or strings concatenated with “\n”

Default: null

Declared by:

<nix-darwin/modules/services/buildkite-agents.nix>
services.buildkite-agents.<name>.hooks.command
The command hook script will replace the default implementation of running the build command.

Type: null or strings concatenated with “\n”

Default: null

Declared by:

<nix-darwin/modules/services/buildkite-agents.nix>
services.buildkite-agents.<name>.hooks.environment
The environment hook will run before all other commands, and can be used to set up secrets, data, etc. Anything exported in hooks will be available to the build script.

Note: the contents of this file will be copied to the world-readable Nix store.

Type: null or strings concatenated with “\n”

Default: null

Example:

''
export SECRET_VAR=`head -1 /run/keys/secret`
''
Declared by:

<nix-darwin/modules/services/buildkite-agents.nix>
services.buildkite-agents.<name>.hooks.post-artifact
The post-artifact hook will run just after artifacts are uploaded

Type: null or strings concatenated with “\n”

Default: null

Declared by:

<nix-darwin/modules/services/buildkite-agents.nix>
services.buildkite-agents.<name>.hooks.post-checkout
The post-checkout hook will run after the bootstrap script has checked out your projects source code.

Type: null or strings concatenated with “\n”

Default: null

Declared by:

<nix-darwin/modules/services/buildkite-agents.nix>
services.buildkite-agents.<name>.hooks.post-command
The post-command hook will run after the bootstrap script has run your build commands

Type: null or strings concatenated with “\n”

Default: null

Declared by:

<nix-darwin/modules/services/buildkite-agents.nix>
services.buildkite-agents.<name>.hooks.pre-artifact
The pre-artifact hook will run just before artifacts are uploaded

Type: null or strings concatenated with “\n”

Default: null

Declared by:

<nix-darwin/modules/services/buildkite-agents.nix>
services.buildkite-agents.<name>.hooks.pre-checkout
The pre-checkout hook will run just before your projects source code is checked out from your SCM provider

Type: null or strings concatenated with “\n”

Default: null

Declared by:

<nix-darwin/modules/services/buildkite-agents.nix>
services.buildkite-agents.<name>.hooks.pre-command
The pre-command hook will run just before your build command runs

Type: null or strings concatenated with “\n”

Default: null

Declared by:

<nix-darwin/modules/services/buildkite-agents.nix>
services.buildkite-agents.<name>.hooks.pre-exit
The pre-exit hook will run just before your build job finishes

Type: null or strings concatenated with “\n”

Default: null

Declared by:

<nix-darwin/modules/services/buildkite-agents.nix>
services.buildkite-agents.<name>.hooksPath
Path to the directory storing the hooks. Consider using services.buildkite-agents.<name>.hooks.<name> instead.

Type: absolute path

Default: generated from services.buildkite-agents.<name>.hooks

Declared by:

<nix-darwin/modules/services/buildkite-agents.nix>
services.buildkite-agents.<name>.name
The name of the agent as seen in the buildkite dashboard.

Type: string

Default: "%hostname-‹name›-%n"

Declared by:

<nix-darwin/modules/services/buildkite-agents.nix>
services.buildkite-agents.<name>.preCommands
Extra commands to run before starting buildkite.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/services/buildkite-agents.nix>
services.buildkite-agents.<name>.privateSshKeyPath
OpenSSH private key

A run-time path to the key file, which is supposed to be provisioned outside of Nix store.

Type: null or absolute path

Default: null

Declared by:

<nix-darwin/modules/services/buildkite-agents.nix>
services.buildkite-agents.<name>.runtimePackages
Add programs to the buildkite-agent environment

Type: list of (package or absolute path)

Default: [ pkgs.bash pkgs.gnutar pkgs.gzip pkgs.git pkgs.nix ]

Declared by:

<nix-darwin/modules/services/buildkite-agents.nix>
services.buildkite-agents.<name>.shell
Command that buildkite-agent 3 will execute when it spawns a shell.

Type: string

Default: "${pkgs.bash}/bin/bash -e -c"

Declared by:

<nix-darwin/modules/services/buildkite-agents.nix>
services.buildkite-agents.<name>.tags
Tags for the agent.

Type: attribute set of (string or list of string)

Default: { }

Example:

{
docker = "true";
queue = "default";
ruby2 = "true";
}
Declared by:

<nix-darwin/modules/services/buildkite-agents.nix>
services.buildkite-agents.<name>.tokenPath
The token from your Buildkite “Agents” page.

A run-time path to the token file, which is supposed to be provisioned outside of Nix store.

Type: absolute path

Declared by:

<nix-darwin/modules/services/buildkite-agents.nix>
services.cachix-agent.enable
Enable to run Cachix Agent as a system service.

Read Cachix Deploy documentation for more information.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/cachix-agent.nix>
services.cachix-agent.package
Package containing cachix executable.

Type: package

Default: pkgs.cachix

Declared by:

<nix-darwin/modules/services/cachix-agent.nix>
services.cachix-agent.credentialsFile
Required file that needs to contain:

export CACHIX_AGENT_TOKEN=…

Type: absolute path

Default: "/etc/cachix-agent.token"

Declared by:

<nix-darwin/modules/services/cachix-agent.nix>
services.cachix-agent.logFile
Absolute path to log all stderr and stdout

Type: null or absolute path

Default: "/var/log/cachix-agent.log"

Declared by:

<nix-darwin/modules/services/cachix-agent.nix>
services.cachix-agent.name
Agent name, usually the same as the hostname.

Type: string

Default: null

Declared by:

<nix-darwin/modules/services/cachix-agent.nix>
services.chunkwm.enable
Whether to enable the chunkwm window manager.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/chunkwm.nix>
services.chunkwm.package
This option specifies the chunkwm package to use.

Type: package

Example: pkgs.chunkwm

Declared by:

<nix-darwin/modules/services/chunkwm.nix>
services.chunkwm.extraConfig
Additional commands for chunkwmrc.

Type: strings concatenated with “\n”

Default: ""

Example: "chunkc tiling::rule --owner Emacs --state tile"

Declared by:

<nix-darwin/modules/services/chunkwm.nix>
services.chunkwm.hotload
Whether to enable hotload.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/services/chunkwm.nix>
services.chunkwm.plugins.border.config
Optional border plugin configuration.

Type: strings concatenated with “\n”

Default: "chunkc set focused_border_color 0xffc0b18b"

Declared by:

<nix-darwin/modules/services/chunkwm.nix>
services.chunkwm.plugins.dir
Chunkwm Plugins directory.

Type: absolute path

Default: "/run/current-system/sw/lib/chunkwm/plugins"

Declared by:

<nix-darwin/modules/services/chunkwm.nix>
services.chunkwm.plugins.list
Chunkwm Plugins to enable.

Type: list of (one of “border”, “ffm”, “tiling”)

Default:

[
"border"
"ffm"
"tiling"
]
Example:

[
"tiling"
]
Declared by:

<nix-darwin/modules/services/chunkwm.nix>
services.chunkwm.plugins.tiling.config
Optional tiling plugin configuration.

Type: strings concatenated with “\n”

Example: "chunkc set global_desktop_mode bsp"

Declared by:

<nix-darwin/modules/services/chunkwm.nix>
services.dnscrypt-proxy.enable
Whether to enable the dnscrypt-proxy service…

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/services/dnscrypt-proxy.nix>
services.dnscrypt-proxy.package
The dnscrypt-proxy package to use.

Type: package

Default: pkgs.dnscrypt-proxy

Declared by:

<nix-darwin/modules/services/dnscrypt-proxy.nix>
services.dnscrypt-proxy.settings
Attrset that is converted and passed as TOML config file. For available params, see: https://github.com/DNSCrypt/dnscrypt-proxy/blob/2.1.8/dnscrypt-proxy/example-dnscrypt-proxy.toml

Type: TOML value

Default: { }

Example:

{
sources.public-resolvers = {
urls = [ "https://download.dnscrypt.info/resolvers-list/v2/public-resolvers.md" ];
cache_file = "public-resolvers.md";
minisign_key = "RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3";
refresh_delay = 72;
};
}

Declared by:

<nix-darwin/modules/services/dnscrypt-proxy.nix>
services.dnsmasq.enable
Whether to enable DNSmasq.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/dnsmasq.nix>
services.dnsmasq.package
This option specifies the dnsmasq package to use.

Type: absolute path

Default: "pkgs.dnsmasq"

Declared by:

<nix-darwin/modules/services/dnsmasq.nix>
services.dnsmasq.addresses
List of domains that will be redirected by the DNSmasq.

Type: attribute set

Default: { }

Example:

{ localhost = "127.0.0.1"; }

Declared by:

<nix-darwin/modules/services/dnsmasq.nix>
services.dnsmasq.bind
This option specifies the interface on which DNSmasq will listen.

Type: string

Default: "127.0.0.1"

Declared by:

<nix-darwin/modules/services/dnsmasq.nix>
services.dnsmasq.port
This option specifies port on which DNSmasq will listen.

Type: signed integer

Default: 53

Declared by:

<nix-darwin/modules/services/dnsmasq.nix>
services.emacs.enable
Whether to enable the Emacs Daemon.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/emacs.nix>
services.emacs.package
This option specifies the emacs package to use.

Type: absolute path

Default: <derivation emacs-30.1>

Declared by:

<nix-darwin/modules/services/emacs.nix>
services.emacs.additionalPath
This option specifies additional PATH that the emacs daemon would have. Typically if you have binaries in your home directory that is what you would add your home path here. One caveat is that there won’t be shell variable expansion, so you can’t use $HOME for example

Type: list of string

Default: [ ]

Example:

[
"/Users/my_user_name"
]
Declared by:

<nix-darwin/modules/services/emacs.nix>
services.emacs.exec
Emacs command/binary to execute.

Type: string

Default: "emacs"

Declared by:

<nix-darwin/modules/services/emacs.nix>
services.eternal-terminal.enable
Whether to enable Eternal Terminal server.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/services/eternal-terminal.nix>
services.eternal-terminal.package
This option specifies the eternal-terminal package to use.

Type: absolute path

Default: "pkgs.eternal-terminal"

Declared by:

<nix-darwin/modules/services/eternal-terminal.nix>
services.eternal-terminal.logSize
The maximum log size.

Type: signed integer

Default: 20971520

Declared by:

<nix-darwin/modules/services/eternal-terminal.nix>
services.eternal-terminal.port
The port the server should listen on. Will use the server’s default (2022) if not specified.

Make sure to open this port in the firewall if necessary.

Type: 16 bit unsigned integer; between 0 and 65535 (both inclusive)

Default: 2022

Declared by:

<nix-darwin/modules/services/eternal-terminal.nix>
services.eternal-terminal.silent
If enabled, disables all logging.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/eternal-terminal.nix>
services.eternal-terminal.verbosity
The verbosity level (0-9).

Type: one of 0, 1, 2, 3, 4, 5, 6, 7, 8, 9

Default: 0

Declared by:

<nix-darwin/modules/services/eternal-terminal.nix>
services.github-runners
Multiple GitHub Runners.

If user and group are set to null, the module will configure nix-darwin to manage the \_github-runner user and group. Note that multiple runner configurations share the same user/group, which means they can access resources from other runners. Make each runner use its own user and group if this is not what you want. In this case, you will have to do the user and group creation yourself. If only user is set, while group is set to null, the service will infer the primary group of the user.

For each GitHub runner, the system activation script creates the following directories:

/var/lib/github-runners/<name>: State directory to store the runner registration credentials

/var/lib/github-runners/\_work/<name>: Working directory for workflow files. The runner only uses this directory if workDir is null (see the workDir option for details).

/var/log/github-runners/<name>: The launchd service writes the stdout and stderr streams to this directory.

Type: attribute set of (submodule)

Default: { }

Example:

{
runner1 = {
enable = true;
name = "runner1";
tokenFile = "/secrets/token1";
url = "https://github.com/owner/repo";
};
runner2 = {
enable = true;
name = "runner2";
tokenFile = "/secrets/token2";
url = "https://github.com/owner/repo";
};
}
Declared by:

<nix-darwin/modules/services/github-runner/options.nix>
services.github-runners.<name>.enable
Whether to enable GitHub Actions runner.

Note: GitHub recommends using self-hosted runners with private repositories only. Learn more here: About self-hosted runners.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/services/github-runner/options.nix>
services.github-runners.<name>.package
The github-runner package to use.

Type: package

Default: pkgs.github-runner

Declared by:

<nix-darwin/modules/services/github-runner/options.nix>
services.github-runners.<name>.ephemeral
If enabled, causes the following behavior:

Passes the --ephemeral flag to the runner configuration script

De-registers and stops the runner with GitHub after it has processed one job

Restarts the service after its successful exit

On start, wipes the state directory and configures a new runner

You should only enable this option if tokenFile points to a file which contains a personal access token (PAT). If you’re using the option with a registration token, restarting the service will fail as soon as the registration token expired.

Changing this option triggers a new runner registration.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/github-runner/options.nix>
services.github-runners.<name>.extraEnvironment
Extra environment variables to set for the runner, as an attrset.

Type: attribute set

Default: { }

Example:

{
GIT_CONFIG = "/path/to/git/config";
}
Declared by:

<nix-darwin/modules/services/github-runner/options.nix>
services.github-runners.<name>.extraLabels
Extra labels in addition to the default (unless disabled through the noDefaultLabels option).

Changing this option triggers a new runner registration.

Type: list of string

Default: [ ]

Example: [ "nixos" ]

Declared by:

<nix-darwin/modules/services/github-runner/options.nix>
services.github-runners.<name>.extraPackages
Extra packages to add to PATH of the service to make them available to workflows.

Type: list of package

Default: [ ]

Declared by:

<nix-darwin/modules/services/github-runner/options.nix>
services.github-runners.<name>.group
Group under which to run the service.

If this option and the user option is set to null, nix-darwin creates the github-runner user and group.

Type: null or string

Default: groupname

Declared by:

<nix-darwin/modules/services/github-runner/options.nix>
services.github-runners.<name>.name
Name of the runner to configure. If null, defaults to the hostname.

Changing this option triggers a new runner registration.

Type: null or string

Default: "‹name›"

Example: "nixos"

Declared by:

<nix-darwin/modules/services/github-runner/options.nix>
services.github-runners.<name>.noDefaultLabels
Disables adding the default labels. Also see the extraLabels option.

Changing this option triggers a new runner registration.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/github-runner/options.nix>
services.github-runners.<name>.nodeRuntimes
List of Node.js runtimes the runner should support.

Type: non-empty (list of value “node20” (singular enum))

Default:

[
"node20"
]
Declared by:

<nix-darwin/modules/services/github-runner/options.nix>
services.github-runners.<name>.replace
Replace any existing runner with the same name.

Without this flag, registering a new runner with the same name fails.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/github-runner/options.nix>
services.github-runners.<name>.runnerGroup
Name of the runner group to add this runner to (defaults to the default runner group).

Changing this option triggers a new runner registration.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/services/github-runner/options.nix>
services.github-runners.<name>.serviceOverrides
Modify the service. Can be used to, e.g., adjust the sandboxing options.

Type: attribute set

Default: { }

Declared by:

<nix-darwin/modules/services/github-runner/options.nix>
services.github-runners.<name>.tokenFile
The full path to a file which contains either

a fine-grained personal access token (PAT),

a classic PAT

or a runner registration token

Changing this option or the tokenFile’s content triggers a new runner registration.

You can also manually trigger a new runner registration by deleting /var/lib/github-runners/<name>/.runner and restarting the service.

We suggest using the fine-grained PATs. A runner registration token is valid only for 1 hour after creation, so the next time the runner configuration changes this will give you hard-to-debug HTTP 404 errors in the configure step.

The file should contain exactly one line with the token without any newline. (Use echo -n '…token…' > …token file… to make sure no newlines sneak in.)

If the file contains a PAT, the service creates a new registration token on startup as needed. If a registration token is given, it can be used to re-register a runner of the same name but is time-limited as noted above.

For fine-grained PATs:

Give it “Read and Write access to organization/repository self hosted runners”, depending on whether it is organization wide or per-repository. You might have to experiment a little, fine-grained PATs are a beta Github feature and still subject to change; nonetheless they are the best option at the moment.

For classic PATs:

Make sure the PAT has a scope of admin:org for organization-wide registrations or a scope of repo for a single repository.

For runner registration tokens:

Nothing special needs to be done, but updating will break after one hour, so these are not recommended.

Type: absolute path

Example: "/run/secrets/github-runner/nixos.token"

Declared by:

<nix-darwin/modules/services/github-runner/options.nix>
services.github-runners.<name>.url
Repository to add the runner to.

Changing this option triggers a new runner registration.

IMPORTANT: If your token is org-wide (not per repository), you need to provide a github org link, not a single repository, so do it like this https://github.com/nixos, not like this https://github.com/nixos/nixpkgs. Otherwise, you are going to get a 404 NotFound from POST https://api.github.com/actions/runner-registration in the configure script.

Type: string

Example: "https://github.com/nixos/nixpkgs"

Declared by:

<nix-darwin/modules/services/github-runner/options.nix>
services.github-runners.<name>.user
User under which to run the service.

If this option and the group option is set to null, nix-darwin creates the github-runner user and group.

Type: null or string

Default: username

Declared by:

<nix-darwin/modules/services/github-runner/options.nix>
services.github-runners.<name>.workDir
Working directory, available as $GITHUB_WORKSPACE during workflow runs and used as a default for repository checkouts. The service cleans this directory on every service start.

Changing this option triggers a new runner registration.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/services/github-runner/options.nix>
services.gitlab-runner.enable
Whether to enable Gitlab Runner.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.package
Gitlab Runner package to use.

Type: package

Default: "pkgs.gitlab-runner"

Example: pkgs.gitlab-runner_1_11

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.checkInterval
Defines the interval length, in seconds, between new jobs check. The default value is 3; if set to 0 or lower, the default value will be used. See runner documentation for more information.

Type: signed integer

Default: 0

Example: with lib; (length (attrNames config.services.gitlab-runner.services)) \* 3

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.concurrent
Limits how many jobs globally can be run concurrently. The most upper limit of jobs using all defined runners. 0 does not mean unlimited.

Type: signed integer

Default: 1

Example: config.nix.maxJobs

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.configFile
Configuration file for gitlab-runner.

configFile takes precedence over services. checkInterval and concurrent will be ignored too.

This option is deprecated, please use services instead. You can use registrationConfigFile and registrationFlags for settings not covered by this module.

Type: null or absolute path

Default: null

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.extraPackages
Extra packages to add to PATH for the gitlab-runner process.

Type: list of package

Default: [ ]

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.gracefulTermination
Finish all remaining jobs before stopping. If not set gitlab-runner will stop immediatly without waiting for jobs to finish, which will lead to failed builds.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.gracefulTimeout
Time to wait until a graceful shutdown is turned into a forceful one.

Type: string

Default: "infinity"

Example: "5min 20s"

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.prometheusListenAddress
Address (<host>:<port>) on which the Prometheus metrics HTTP server should be listening.

Type: null or string

Default: null

Example: "localhost:8080"

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.sentryDSN
Data Source Name for tracking of all system level errors to Sentry.

Type: null or string

Default: null

Example: "https://public:private@host:port/1"

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.services
GitLab Runner services.

Type: attribute set of (submodule)

Default: { }

Example:

{

# runner for building in docker via host's nix-daemon

# nix store will be readable in runner, might be insecure

nix = { # File should contain at least these two variables: # `CI_SERVER_URL` # `REGISTRATION_TOKEN`
registrationConfigFile = "/run/secrets/gitlab-runner-registration";
dockerImage = "alpine";
dockerVolumes = [
"/nix/store:/nix/store:ro"
"/nix/var/nix/db:/nix/var/nix/db:ro"
"/nix/var/nix/daemon-socket:/nix/var/nix/daemon-socket:ro"
];
dockerDisableCache = true;
preBuildScript = pkgs.writeScript "setup-container" ''
mkdir -p -m 0755 /nix/var/log/nix/drvs
mkdir -p -m 0755 /nix/var/nix/gcroots
mkdir -p -m 0755 /nix/var/nix/profiles
mkdir -p -m 0755 /nix/var/nix/temproots
mkdir -p -m 0755 /nix/var/nix/userpool
mkdir -p -m 1777 /nix/var/nix/gcroots/per-user
mkdir -p -m 1777 /nix/var/nix/profiles/per-user
mkdir -p -m 0755 /nix/var/nix/profiles/per-user/root
mkdir -p -m 0700 "$HOME/.nix-defexpr"

      . ${pkgs.nix}/etc/profile.d/nix.sh

      ${pkgs.nix}/bin/nix-env -i ${concatStringsSep " " (with pkgs; [ nix cacert git openssh ])}

      ${pkgs.nix}/bin/nix-channel --add https://nixos.org/channels/nixpkgs-unstable
      ${pkgs.nix}/bin/nix-channel --update nixpkgs
    '';
    environmentVariables = {
      ENV = "/etc/profile";
      USER = "root";
      NIX_REMOTE = "daemon";
      PATH = "/nix/var/nix/profiles/default/bin:/nix/var/nix/profiles/default/sbin:/bin:/sbin:/usr/bin:/usr/sbin";
      NIX_SSL_CERT_FILE = "/nix/var/nix/profiles/default/etc/ssl/certs/ca-bundle.crt";
    };
    tagList = [ "nix" ];

};

# runner for building docker images

docker-images = { # File should contain at least these two variables: # `CI_SERVER_URL` # `REGISTRATION_TOKEN`
registrationConfigFile = "/run/secrets/gitlab-runner-registration";
dockerImage = "docker:stable";
dockerVolumes = [
"/var/run/docker.sock:/var/run/docker.sock"
];
tagList = [ "docker-images" ];
};

# runner for executing stuff on host system (very insecure!)

# make sure to add required packages (including git!)

# to `environment.systemPackages`

shell = { # File should contain at least these two variables: # `CI_SERVER_URL` # `REGISTRATION_TOKEN`
registrationConfigFile = "/run/secrets/gitlab-runner-registration";
executor = "shell";
tagList = [ "shell" ];
};

# runner for everything else

default = { # File should contain at least these two variables: # `CI_SERVER_URL` # `REGISTRATION_TOKEN`
registrationConfigFile = "/run/secrets/gitlab-runner-registration";
dockerImage = "debian:stable";
};
}

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.services.<name>.buildsDir
Absolute path to a directory where builds will be stored in context of selected executor (Locally, Docker, SSH).

Type: null or absolute path

Default: null

Example: "/var/lib/gitlab-runner/builds"

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.services.<name>.cloneUrl
Overwrite the URL for the GitLab instance. Used if the Runner can’t connect to GitLab on the URL GitLab exposes itself.

Type: null or string

Default: null

Example: "http://gitlab.example.local"

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.services.<name>.debugTraceDisabled
When set to true Runner will disable the possibility of using the CI_DEBUG_TRACE feature.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.services.<name>.dockerAllowedImages
Whitelist allowed images.

Type: list of string

Default: [ ]

Example:

[
"ruby:*"
"python:*"
"php:*"
"my.registry.tld:5000/*:*"
]
Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.services.<name>.dockerAllowedServices
Whitelist allowed services.

Type: list of string

Default: [ ]

Example:

[
"postgres:9"
"redis:*"
"mysql:*"
]
Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.services.<name>.dockerDisableCache
Disable all container caching.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.services.<name>.dockerExtraHosts
Add a custom host-to-IP mapping.

Type: list of string

Default: [ ]

Example:

[
"other-host:127.0.0.1"
]
Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.services.<name>.dockerImage
Docker image to be used.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.services.<name>.dockerPrivileged
Give extended privileges to container.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.services.<name>.dockerVolumes
Bind-mount a volume and create it if it doesn’t exist prior to mounting.

Type: list of string

Default: [ ]

Example:

[
"/var/run/docker.sock:/var/run/docker.sock"
]
Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.services.<name>.environmentVariables
Custom environment variables injected to build environment. For secrets you can use registrationConfigFile with RUNNER_ENV variable set.

Type: attribute set of string

Default: { }

Example:

{
NAME = "value";
}
Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.services.<name>.executor
Select executor, eg. shell, docker, etc. See runner documentation for more information.

Type: string

Default: "docker"

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.services.<name>.limit
Limit how many jobs can be handled concurrently by this service. 0 (default) simply means don’t limit.

Type: signed integer

Default: 0

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.services.<name>.maximumTimeout
What is the maximum timeout (in seconds) that will be set for job when using this Runner. 0 (default) simply means don’t limit.

Type: signed integer

Default: 0

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.services.<name>.postBuildScript
Runner-specific command script executed after code is pulled and just after build executes.

Type: null or absolute path

Default: null

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.services.<name>.preBuildScript
Runner-specific command script executed after code is pulled, just before build executes.

Type: null or absolute path

Default: null

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.services.<name>.preCloneScript
Runner-specific command script executed before code is pulled.

Type: null or absolute path

Default: null

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.services.<name>.protected
When set to true Runner will only run on pipelines triggered on protected branches.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.services.<name>.registrationConfigFile
Absolute path to a file with environment variables used for gitlab-runner registration. A list of all supported environment variables can be found in gitlab-runner register --help.

Ones that you probably want to set is

CI_SERVER_URL=<CI server URL>

REGISTRATION_TOKEN=<registration secret>

Type: absolute path

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.services.<name>.registrationFlags
Extra command-line flags passed to gitlab-runner register. Execute gitlab-runner register --help for a list of supported flags.

Type: list of string

Default: [ ]

Example:

[
"--docker-helper-image my/gitlab-runner-helper"
]
Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.services.<name>.requestConcurrency
Limit number of concurrent requests for new jobs from GitLab.

Type: signed integer

Default: 0

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.services.<name>.runUntagged
Register to run untagged builds; defaults to true when tagList is empty.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.services.<name>.tagList
Tag list.

Type: list of string

Default: [ ]

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.sessionServer
The session server allows the user to interact with jobs that the Runner is responsible for. A good example of this is the interactive web terminal.

Type: submodule

Default: { }

Example:

{
listenAddress = "0.0.0.0:8093";
}

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.sessionServer.advertiseAddress
The URL that the Runner will expose to GitLab to be used to access the session server. Fallbacks to listenAddress if not defined.

Type: null or string

Default: null

Example: "runner-host-name.tld:8093"

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.sessionServer.listenAddress
An internal URL to be used for the session server.

Type: null or string

Default: null

Example: "0.0.0.0:8093"

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.gitlab-runner.sessionServer.sessionTimeout
How long in seconds the session can stay active after the job completes (which will block the job from finishing).

Type: signed integer

Default: 1800

Declared by:

<nix-darwin/modules/services/gitlab-runner.nix>
services.hercules-ci-agent.enable
Enable to run Hercules CI Agent as a system service.

Hercules CI is a continuous integation service that is centered around Nix.

Support is available at help@hercules-ci.com.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/hercules-ci-agent/common.nix>
services.hercules-ci-agent.package
Package containing the bin/hercules-ci-agent executable.

Type: package

Default: pkgs.hercules-ci-agent

Declared by:

<nix-darwin/modules/services/hercules-ci-agent/common.nix>
services.hercules-ci-agent.logFile
Stdout and sterr of hercules-ci-agent process.

Type: absolute path

Default: "/var/log/hercules-ci-agent.log"

Declared by:

<nix-darwin/modules/services/hercules-ci-agent>
services.hercules-ci-agent.settings
These settings are written to the agent.toml file.

Not all settings are listed as options, can be set nonetheless.

For the exhaustive list of settings, see https://docs.hercules-ci.com/hercules-ci/reference/agent-config/.

Type: TOML value

Declared by:

<nix-darwin/modules/services/hercules-ci-agent/common.nix>
services.hercules-ci-agent.settings.apiBaseUrl
API base URL that the agent will connect to.

When using Hercules CI Enterprise, set this to the URL where your Hercules CI server is reachable.

Type: string

Default: "https://hercules-ci.com"

Declared by:

<nix-darwin/modules/services/hercules-ci-agent/common.nix>
services.hercules-ci-agent.settings.baseDirectory
State directory (secrets, work directory, etc) for agent

Type: absolute path

Default: "/var/lib/hercules-ci-agent"

Declared by:

<nix-darwin/modules/services/hercules-ci-agent/common.nix>
services.hercules-ci-agent.settings.binaryCachesPath
Path to a JSON file containing binary cache secret keys.

As these values are confidential, they should not be in the store, but copied over using other means, such as agenix, NixOps deployment.keys, or manual installation.

The format is described on https://docs.hercules-ci.com/hercules-ci-agent/binary-caches-json/.

Type: absolute path

Default: staticSecretsDirectory + "/binary-caches.json"

Declared by:

<nix-darwin/modules/services/hercules-ci-agent/common.nix>
services.hercules-ci-agent.settings.clusterJoinTokenPath
Location of the cluster-join-token.key file.

You can retrieve the contents of the file when creating a new agent via https://hercules-ci.com/dashboard.

As this value is confidential, it should not be in the store, but installed using other means, such as agenix, NixOps deployment.keys, or manual installation.

The contents of the file are used for authentication between the agent and the API.

Type: absolute path

Default: staticSecretsDirectory + "/cluster-join-token.key"

Declared by:

<nix-darwin/modules/services/hercules-ci-agent/common.nix>
services.hercules-ci-agent.settings.concurrentTasks
Number of tasks to perform simultaneously.

A task is a single derivation build, an evaluation or an effect run. At minimum, you need 2 concurrent tasks for x86_64-linux in your cluster, to allow for import from derivation.

concurrentTasks can be around the CPU core count or lower if memory is the bottleneck.

The optimal value depends on the resource consumption characteristics of your workload, including memory usage and in-task parallelism. This is typically determined empirically.

When scaling, it is generally better to have a double-size machine than two machines, because each split of resources causes inefficiencies; particularly with regards to build latency because of extra downloads.

Type: positive integer, meaning >0, or value “auto” (singular enum)

Default: "auto", meaning equal to the number of CPU cores.

Declared by:

<nix-darwin/modules/services/hercules-ci-agent/common.nix>
services.hercules-ci-agent.settings.labels
A key-value map of user data.

This data will be available to organization members in the dashboard and API.

The values can be of any TOML type that corresponds to a JSON type, but arrays can not contain tables/objects due to limitations of the TOML library. Values involving arrays of non-primitive types may not be representable currently.

Type: TOML value

Default:

{
agent.source = "..."; # One of "nixpkgs", "flake", "override"
lib.version = "...";
pkgs.version = "...";
}

Declared by:

<nix-darwin/modules/services/hercules-ci-agent/common.nix>
services.hercules-ci-agent.settings.secretsJsonPath
Path to a JSON file containing secrets for effects.

As these values are confidential, they should not be in the store, but copied over using other means, such as agenix, NixOps deployment.keys, or manual installation.

The format is described on https://docs.hercules-ci.com/hercules-ci-agent/secrets-json/.

Type: absolute path

Default: staticSecretsDirectory + "/secrets.json"

Declared by:

<nix-darwin/modules/services/hercules-ci-agent/common.nix>
services.hercules-ci-agent.settings.staticSecretsDirectory
This is the default directory to look for statically configured secrets like cluster-join-token.key.

See also clusterJoinTokenPath and binaryCachesPath for fine-grained configuration.

Type: absolute path

Default: baseDirectory + "/secrets"

Declared by:

<nix-darwin/modules/services/hercules-ci-agent/common.nix>
services.hercules-ci-agent.settings.workDirectory
The directory in which temporary subdirectories are created for task state. This includes sources for Nix evaluation.

Type: absolute path

Default: baseDirectory + "/work"

Declared by:

<nix-darwin/modules/services/hercules-ci-agent/common.nix>
services.ipfs.enable
Whether to enable the ipfs daemon.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/ipfs.nix>
services.ipfs.enableGarbageCollection
Passes --enable-gc flag to ipfs daemon.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/ipfs.nix>
services.ipfs.package
The ipfs package to use.

Type: package

Default: <derivation kubo-0.34.1>

Declared by:

<nix-darwin/modules/services/ipfs.nix>
services.ipfs.ipfsPath
Set the IPFS_PATH environment variable.

Type: null or absolute path

Default: null

Declared by:

<nix-darwin/modules/services/ipfs.nix>
services.ipfs.logFile
The logfile to use for the ipfs service. Alternatively sudo launchctl debug system/org.nixos.ipfs --stderr can be used to stream the logs to a shell after restarting the service with sudo launchctl kickstart -k system/org.nixos.ipfs.

Type: null or absolute path

Default: null

Example: "/var/tmp/ipfs.log"

Declared by:

<nix-darwin/modules/services/ipfs.nix>
services.jankyborders.enable
Whether to enable Enable the jankyborders service…

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/services/jankyborders>
services.jankyborders.package
The jankyborders package to use.

Type: package

Default: pkgs.jankyborders

Declared by:

<nix-darwin/modules/services/jankyborders>
services.jankyborders.active_color
Sets the border color for the focused window (format: 0xAARRGGBB). For instance, active_color=“0xff00ff00” creates a green border. For Gradient Border : active_color=“gradient(top_right=0x9992B3F5,bottom_left=0x9992B3F5)”

Type: string

Default: "0xFFFFFFFF"

Example: "0xFFFFFFFF"

Declared by:

<nix-darwin/modules/services/jankyborders>
services.jankyborders.ax_focus
If set to true, the (slower) accessibility API is used to resolve the focused window.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/jankyborders>
services.jankyborders.background_color
Sets the background fill color for all windows (only 0xAARRGGBB arguments supported).

Type: string

Default: ""

Example: "0xFFFFFFFF"

Declared by:

<nix-darwin/modules/services/jankyborders>
services.jankyborders.blacklist
The applications specified here are excluded from being bordered. For example, blacklist = [ “Safari” “kitty” ] excludes Safari and kitty from being bordered.

Type: list of string

Default: [ ]

Example:

[
"Safari"
"kitty"
]
Declared by:

<nix-darwin/modules/services/jankyborders>
services.jankyborders.blur_radius
Sets the blur radius applied to the borders or backgrounds with transparency.

Type: floating point number

Default: 0.0

Example: 5.0

Declared by:

<nix-darwin/modules/services/jankyborders>
services.jankyborders.hidpi
If set to on, the border will be drawn with retina resolution.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/jankyborders>
services.jankyborders.inactive_color
Sets the border color for all windows not in focus (format: 0xAARRGGBB). For Gradient Border : inactive_color=“gradient(top_right=0x9992B3F5,bottom_left=0x9992B3F5)”

Type: string

Default: "0xFFFFFFFF"

Example: "0xFFFFFFFF"

Declared by:

<nix-darwin/modules/services/jankyborders>
services.jankyborders.order
Specifies whether borders should be drawn above or below windows.

Type: one of “above”, “below”

Default: "below"

Example: "above"

Declared by:

<nix-darwin/modules/services/jankyborders>
services.jankyborders.style
Specifies the style of the border (either round or square).

Type: string

Default: "round"

Example: "square/round"

Declared by:

<nix-darwin/modules/services/jankyborders>
services.jankyborders.whitelist
Once this list is populated, only applications listed here are considered for receiving a border. If the whitelist is empty (default) it is inactive.

Type: list of string

Default: [ ]

Example:

[
"Arc"
"USB Overdrive"
]
Declared by:

<nix-darwin/modules/services/jankyborders>
services.jankyborders.width
Determines the width of the border. For example, width=5.0 creates a border 5.0 points wide.

Type: floating point number

Default: 5.0

Declared by:

<nix-darwin/modules/services/jankyborders>
services.karabiner-elements.enable
Whether to enable Karabiner-Elements.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/services/karabiner-elements>
services.karabiner-elements.package
The karabiner-elements package to use.

Type: package

Default: pkgs.karabiner-elements

Declared by:

<nix-darwin/modules/services/karabiner-elements>
services.khd.enable
Whether to enable the khd hotkey daemon.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/khd>
services.khd.package
This option specifies the khd package to use.

Type: package

Default: "pkgs.khd"

Declared by:

<nix-darwin/modules/services/khd>
services.khd.i3Keybindings
Wether to configure i3 style keybindings for kwm.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/khd>
services.khd.khdConfig
Config to use for khdrc.

Type: strings concatenated with “\n”

Default: ""

Example: "alt + shift - r : kwmc quit"

Declared by:

<nix-darwin/modules/services/khd>
services.kwm.enable
Whether to enable the khd window manager.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/kwm>
services.kwm.package
This option specifies the kwm package to use.

Type: absolute path

Default: "pkgs.kwm"

Declared by:

<nix-darwin/modules/services/kwm>
services.kwm.kwmConfig
Config to use for kwmrc.

Type: strings concatenated with “\n”

Default: ""

Example: "kwmc rule owner=\"iTerm2\" properties={role=\"AXDialog\"}"

Declared by:

<nix-darwin/modules/services/kwm>
services.lorri.enable
Whether to enable the lorri service.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/lorri.nix>
services.lorri.logFile
The logfile to use for the lorri service. Alternatively sudo launchctl debug system/org.nixos.lorri --stderr can be used to stream the logs to a shell after restarting the service with sudo launchctl kickstart -k system/org.nixos.lorri.

Type: null or absolute path

Default: null

Example: "/var/tmp/lorri.log"

Declared by:

<nix-darwin/modules/services/lorri.nix>
services.mopidy.enable
Whether to enable the Mopidy Daemon.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/mopidy.nix>
services.mopidy.package
This option specifies the mopidy package to use.

Type: absolute path

Default: "pkgs.mopidy"

Declared by:

<nix-darwin/modules/services/mopidy.nix>
services.mopidy.mediakeys.enable
Whether to enable the Mopidy OSX Media Keys support daemon.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/mopidy.nix>
services.mopidy.mediakeys.package
This option specifies the mediakeys package to use.

Type: absolute path

Default: "pkgs.pythonPackages.osxmpdkeys"

Declared by:

<nix-darwin/modules/services/mopidy.nix>
services.netbird.enable
Whether to enable Netbird daemon.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/services/netbird.nix>
services.netbird.package
The package to use for netbird

Type: package

Default: pkgs.netbird

Declared by:

<nix-darwin/modules/services/netbird.nix>
services.netdata.enable
Whether to enable Netdata daemon.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/services/monitoring/netdata.nix>
services.netdata.package
The netdata package to use.

Type: package

Default: pkgs.netdata

Declared by:

<nix-darwin/modules/services/monitoring/netdata.nix>
services.netdata.cacheDir
Cache directory for Netdata

Type: absolute path

Default: "/var/cache/netdata"

Declared by:

<nix-darwin/modules/services/monitoring/netdata.nix>
services.netdata.config
Custom configuration for Netdata

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/services/monitoring/netdata.nix>
services.netdata.logDir
Log directory for Netdata

Type: absolute path

Default: "/var/log/netdata"

Declared by:

<nix-darwin/modules/services/monitoring/netdata.nix>
services.netdata.workDir
Working directory for Netdata

Type: absolute path

Default: "/var/lib/netdata"

Declared by:

<nix-darwin/modules/services/monitoring/netdata.nix>
services.nextdns.enable
Whether to enable the NextDNS DNS/53 to DoH Proxy service.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/nextdns>
services.nextdns.arguments
Additional arguments to be passed to nextdns run.

Type: list of string

Default: [ ]

Example:

[
"-config"
"10.0.3.0/24=abcdef"
]
Declared by:

<nix-darwin/modules/services/nextdns>
services.nix-daemon.enableSocketListener
Whether to make the nix-daemon service socket activated.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/nix-daemon.nix>
services.nix-daemon.logFile
The logfile to use for the nix-daemon service. Alternatively sudo launchctl debug system/org.nixos.nix-daemon --stderr can be used to stream the logs to a shell after restarting the service with sudo launchctl kickstart -k system/org.nixos.nix-daemon.

Type: null or absolute path

Default: null

Example: "/var/log/nix-daemon.log"

Declared by:

<nix-darwin/modules/services/nix-daemon.nix>
services.nix-daemon.tempDir
The TMPDIR to use for nix-daemon.

Type: null or absolute path

Default: null

Declared by:

<nix-darwin/modules/services/nix-daemon.nix>
services.ofborg.enable
Whether to enable the ofborg builder service.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/ofborg>
services.ofborg.package
This option specifies the ofborg package to use. eg.

(import <ofborg> {}).ofborg.rs

$ nix-channel --add https://github.com/NixOS/ofborg/archive/released.tar.gz ofborg $ nix-channel --update

Type: package

Example: pkgs.ofborg

Declared by:

<nix-darwin/modules/services/ofborg>
services.ofborg.configFile
Configuration file to use for ofborg.

WARNING Don’t use a path literal or derivation for this, that would expose credentials in the store making them world readable.

Type: absolute path

Declared by:

<nix-darwin/modules/services/ofborg>
services.ofborg.logFile
The logfile to use for the ofborg service.

Type: absolute path

Default: "/var/log/ofborg.log"

Declared by:

<nix-darwin/modules/services/ofborg>
services.offlineimap.enable
Whether to enable Offlineimap, a software to dispose your mailbox(es) as a local Maildir(s).

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/services/mail/offlineimap.nix>
services.offlineimap.package
Offlineimap derivation to use.

Type: package

Default: "pkgs.offlineimap"

Declared by:

<nix-darwin/modules/services/mail/offlineimap.nix>
services.offlineimap.extraConfig
Additional text to be appended to offlineimaprc.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/services/mail/offlineimap.nix>
services.offlineimap.path
List of derivations to put in Offlineimap’s path.

Type: list of absolute path

Default: [ ]

Example: [ pkgs.pass pkgs.bash pkgs.notmuch ]

Declared by:

<nix-darwin/modules/services/mail/offlineimap.nix>
services.offlineimap.runQuick
Run only quick synchronizations. Ignore any flag updates on IMAP servers. If a flag on the remote IMAP changes, and we have the message locally, it will be left untouched in a quick run.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/mail/offlineimap.nix>
services.offlineimap.startInterval
Optional key to start offlineimap services each N seconds

Type: null or signed integer

Default: 300

Declared by:

<nix-darwin/modules/services/mail/offlineimap.nix>
services.openssh.enable
Whether to enable Apple’s built-in OpenSSH server.

The default is null which means let macOS manage the OpenSSH server.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/services/openssh.nix>
services.openssh.extraConfig
Extra configuration text loaded in sshd_config. See sshd_config(5) for help.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/services/openssh.nix>
services.postgresql.enable
Whether to enable PostgreSQL Server.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/services/postgresql>
services.postgresql.enableTCPIP
Whether PostgreSQL should listen on all network interfaces. If disabled, the database can only be accessed via its Unix domain socket or via TCP connections to localhost.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/postgresql>
services.postgresql.package
PostgreSQL package to use.

Type: package

Example: pkgs.postgresql_11

Declared by:

<nix-darwin/modules/services/postgresql>
services.postgresql.authentication
Defines how users authenticate themselves to the server. See the PostgreSQL documentation for pg_hba.conf for details on the expected format of this option. By default, peer based authentication will be used for users connecting via the Unix socket, and md5 password authentication will be used for users connecting via TCP. Any added rules will be inserted above the default rules. If you’d like to replace the default rules entirely, you can use lib.mkForce in your module.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/services/postgresql>
services.postgresql.checkConfig
Check the syntax of the configuration file at compile time

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/services/postgresql>
services.postgresql.dataDir
The data directory for PostgreSQL. If left as the default value this directory will automatically be created before the PostgreSQL server starts, otherwise the sysadmin is responsible for ensuring the directory exists with appropriate ownership and permissions.

Type: absolute path

Default: "/var/lib/postgresql/${config.services.postgresql.package.psqlSchema}"

Example: "/var/lib/postgresql/11"

Declared by:

<nix-darwin/modules/services/postgresql>
services.postgresql.ensureDatabases
Ensures that the specified databases exist. This option will never delete existing databases, especially not when the value of this option is changed. This means that databases created once through this option or otherwise have to be removed manually.

Type: list of string

Default: [ ]

Example:

[
"gitea"
"nextcloud"
]
Declared by:

<nix-darwin/modules/services/postgresql>
services.postgresql.ensureUsers
Ensures that the specified users exist and have at least the ensured permissions. The PostgreSQL users will be identified using peer authentication. This authenticates the Unix user with the same name only, and that without the need for a password. This option will never delete existing users or remove permissions, especially not when the value of this option is changed. This means that users created and permissions assigned once through this option or otherwise have to be removed manually.

Type: list of (submodule)

Default: [ ]

Example:

[
{
name = "nextcloud";
ensurePermissions = {
"DATABASE nextcloud" = "ALL PRIVILEGES";
};
}
{
name = "superuser";
ensurePermissions = {
"ALL TABLES IN SCHEMA public" = "ALL PRIVILEGES";
};
}
]

Declared by:

<nix-darwin/modules/services/postgresql>
services.postgresql.ensureUsers.\*.ensurePermissions
Permissions to ensure for the user, specified as an attribute set. The attribute names specify the database and tables to grant the permissions for. The attribute values specify the permissions to grant. You may specify one or multiple comma-separated SQL privileges here.

For more information on how to specify the target and on which privileges exist, see the GRANT syntax. The attributes are used as GRANT ${attrValue} ON ${attrName}.

Type: attribute set of string

Default: { }

Example:

{
"DATABASE \"nextcloud\"" = "ALL PRIVILEGES";
"ALL TABLES IN SCHEMA public" = "ALL PRIVILEGES";
}

Declared by:

<nix-darwin/modules/services/postgresql>
services.postgresql.ensureUsers.\*.name
Name of the user to ensure.

Type: string

Declared by:

<nix-darwin/modules/services/postgresql>
services.postgresql.extraPlugins
List of PostgreSQL plugins. PostgreSQL version for each plugin should match version for services.postgresql.package value.

Type: list of absolute path

Default: [ ]

Example: with pkgs.postgresql_11.pkgs; [ postgis pg_repack ]

Declared by:

<nix-darwin/modules/services/postgresql>
services.postgresql.identMap
Defines the mapping from system users to database users.

The general form is:

map-name system-username database-username

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/services/postgresql>
services.postgresql.initdbArgs
Additional arguments passed to initdb during data dir initialisation.

Type: list of string

Default: [ ]

Example:

[
"--data-checksums"
"--allow-group-access"
]
Declared by:

<nix-darwin/modules/services/postgresql>
services.postgresql.initialScript
A file containing SQL statements to execute on first startup.

Type: null or absolute path

Default: null

Declared by:

<nix-darwin/modules/services/postgresql>
services.postgresql.logLinePrefix
A printf-style string that is output at the beginning of each log line. Upstream default is '%m [%p] ', i.e. it includes the timestamp. We do not include the timestamp, because journal has it anyway.

Type: string

Default: "[%p] "

Example: "%m [%p] "

Declared by:

<nix-darwin/modules/services/postgresql>
services.postgresql.port
The port on which PostgreSQL listens.

Type: signed integer

Default: 5432

Declared by:

<nix-darwin/modules/services/postgresql>
services.postgresql.recoveryConfig
Contents of the recovery.conf file.

Type: null or strings concatenated with “\n”

Default: null

Declared by:

<nix-darwin/modules/services/postgresql>
services.postgresql.settings
PostgreSQL configuration. Refer to https://www.postgresql.org/docs/11/config-setting.html#CONFIG-SETTING-CONFIGURATION-FILE for an overview of postgresql.conf.

Note
String values will automatically be enclosed in single quotes. Single quotes will be escaped with two single quotes as described by the upstream documentation linked above.

Type: attribute set of (boolean or floating point number or signed integer or string)

Default: { }

Example:

{
log_connections = true;
log_statement = "all";
logging_collector = true
log_disconnections = true
log_destination = lib.mkForce "syslog";
}

Declared by:

<nix-darwin/modules/services/postgresql>
services.privoxy.enable
Whether to enable the privoxy proxy service.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/privoxy>
services.privoxy.package
This option specifies the privoxy package to use.

Type: package

Default: <derivation privoxy-3.0.34>

Example: pkgs.privoxy

Declared by:

<nix-darwin/modules/services/privoxy>
services.privoxy.confdir
Directory for privoxy files such as .action and .filter.

Type: null or absolute path

Default: null

Declared by:

<nix-darwin/modules/services/privoxy>
services.privoxy.config
Config to use for privoxy

Type: strings concatenated with “\n”

Default: ""

Example: "forward / upstream.proxy:8080"

Declared by:

<nix-darwin/modules/services/privoxy>
services.privoxy.listenAddress
The address and TCP port on which privoxy will listen.

Type: string

Default: "127.0.0.1:8118"

Declared by:

<nix-darwin/modules/services/privoxy>
services.privoxy.templdir
Directory for privoxy template files.

Type: absolute path

Default: "\${pkgs.privoxy}/etc/templates"

Declared by:

<nix-darwin/modules/services/privoxy>
services.prometheus.exporters.node.enable
Whether to enable Prometheus Node exporter.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/services/monitoring/prometheus-node-exporter.nix>
services.prometheus.exporters.node.enabledCollectors
Collectors to enable in addition to the ones that are enabled by default.

Type: list of string

Default: [ ]

Declared by:

<nix-darwin/modules/services/monitoring/prometheus-node-exporter.nix>
services.prometheus.exporters.node.package
The prometheus-node-exporter package to use.

Type: package

Default: pkgs.prometheus-node-exporter

Declared by:

<nix-darwin/modules/services/monitoring/prometheus-node-exporter.nix>
services.prometheus.exporters.node.disabledCollectors
Collectors to disable from the list of collectors that are enabled by default.

Type: list of string

Default: [ ]

Example:

[
"boottime"
]
Declared by:

<nix-darwin/modules/services/monitoring/prometheus-node-exporter.nix>
services.prometheus.exporters.node.extraFlags
Extra commandline options to pass to the Node exporter executable.

Type: list of string

Default: [ ]

Example:

[
"--log.level=debug"
]
Declared by:

<nix-darwin/modules/services/monitoring/prometheus-node-exporter.nix>
services.prometheus.exporters.node.listenAddress
Address where Node exporter exposes its HTTP interface. Leave empty to bind to all addresses.

Type: string

Default: ""

Example: "0.0.0.0"

Declared by:

<nix-darwin/modules/services/monitoring/prometheus-node-exporter.nix>
services.prometheus.exporters.node.port
Port where the Node exporter exposes its HTTP interface.

Type: 16 bit unsigned integer; between 0 and 65535 (both inclusive)

Default: 9100

Declared by:

<nix-darwin/modules/services/monitoring/prometheus-node-exporter.nix>
services.redis.enable
Whether to enable the redis database service.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/redis>
services.redis.package
This option specifies the redis package to use

Type: absolute path

Default: "pkgs.redis"

Declared by:

<nix-darwin/modules/services/redis>
services.redis.appendOnly
By default data is only periodically persisted to disk, enable this option to use an append-only file for improved persistence.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/redis>
services.redis.bind
The IP interface to bind to.

Type: null or string

Default: null

Example: "127.0.0.1"

Declared by:

<nix-darwin/modules/services/redis>
services.redis.dataDir
Data directory for the redis database.

Type: null or absolute path

Default: "/var/lib/redis"

Declared by:

<nix-darwin/modules/services/redis>
services.redis.extraConfig
Additional text to be appended to redis.conf.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/services/redis>
services.redis.port
The port for Redis to listen to.

Type: signed integer

Default: 6379

Declared by:

<nix-darwin/modules/services/redis>
services.redis.unixSocket
The path to the socket to bind to.

Type: null or absolute path

Default: null

Example: "/var/run/redis.sock"

Declared by:

<nix-darwin/modules/services/redis>
services.sketchybar.enable
Whether to enable sketchybar.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/services/sketchybar>
services.sketchybar.package
The sketchybar package to use.

Type: package

Default: pkgs.sketchybar

Declared by:

<nix-darwin/modules/services/sketchybar>
services.sketchybar.config
Contents of sketchybar’s configuration file. If empty (the default), the configuration file won’t be managed.

See documentation and example.

Type: strings concatenated with “\n”

Default: ""

Example:

''
sketchybar --bar height=24
sketchybar --update
echo "sketchybar configuration loaded.."
''
Declared by:

<nix-darwin/modules/services/sketchybar>
services.sketchybar.extraPackages
Extra packages to add to PATH.

Type: list of package

Default: [ ]

Example: [ pkgs.jq ]

Declared by:

<nix-darwin/modules/services/sketchybar>
services.skhd.enable
Whether to enable the skhd hotkey daemon.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/skhd>
services.skhd.package
This option specifies the skhd package to use.

Type: package

Default: <derivation skhd-0.3.9>

Declared by:

<nix-darwin/modules/services/skhd>
services.skhd.skhdConfig
Config to use for skhdrc.

Type: strings concatenated with “\n”

Default: ""

Example: "alt + shift - r : chunkc quit"

Declared by:

<nix-darwin/modules/services/skhd>
services.spacebar.enable
Whether to enable the spacebar spacebar.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/spacebar>
services.spacebar.package
The spacebar package to use.

Type: absolute path

Declared by:

<nix-darwin/modules/services/spacebar>
services.spacebar.config
Key/Value pairs to pass to spacebar’s ‘config’ domain, via the configuration file.

Type: attribute set

Default: { }

Example:

{
clock_format = "%R";
background_color = "0xff202020";
foreground_color = "0xffa8a8a8";
}

Declared by:

<nix-darwin/modules/services/spacebar>
services.spacebar.extraConfig
Extra arbitrary configuration to append to the configuration file.

Type: string

Default: ""

Example:

echo "spacebar config loaded..."

Declared by:

<nix-darwin/modules/services/spacebar>
services.spotifyd.enable
Whether to enable the spotifyd service.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/spotifyd.nix>
services.spotifyd.package
The spotifyd package to use.

Type: absolute path

Default: "pkgs.spotifyd"

Declared by:

<nix-darwin/modules/services/spotifyd.nix>
services.spotifyd.settings
Configuration for spotifyd, see https://spotifyd.github.io/spotifyd/config/File.html for supported values.

Type: null or TOML value

Default: null

Example:

{
bitrate = 160;
volume_normalisation = true;
}
Declared by:

<nix-darwin/modules/services/spotifyd.nix>
services.synapse-bt.enable
Whether to run Synapse BitTorrent Daemon.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/synapse-bt.nix>
services.synapse-bt.package
Synapse BitTorrent package to use.

Type: package

Default: "pkgs.synapse-bt"

Declared by:

<nix-darwin/modules/services/synapse-bt.nix>
services.synapse-bt.downloadDir
Download directory for Synapse BitTorrent.

Type: absolute path

Default: "/var/lib/synapse-bt"

Example: "/var/lib/synapse-bt/downloads"

Declared by:

<nix-darwin/modules/services/synapse-bt.nix>
services.synapse-bt.extraConfig
Extra configuration options for Synapse BitTorrent.

Type: attribute set

Default: { }

Declared by:

<nix-darwin/modules/services/synapse-bt.nix>
services.synapse-bt.port
The port on which Synapse BitTorrent listens.

Type: signed integer

Default: 16384

Declared by:

<nix-darwin/modules/services/synapse-bt.nix>
services.synergy.package
The package used for the synergy client and server.

Type: package

Default: "pkgs.synergy"

Declared by:

<nix-darwin/modules/services/synergy>
services.synergy.client.enable
Whether to enable the Synergy client (receive keyboard and mouse events from a Synergy server).

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/synergy>
services.synergy.client.autoStart
Whether the Synergy client should be started automatically.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/services/synergy>
services.synergy.client.screenName
Use the given name instead of the hostname to identify ourselves to the server.

Type: string

Default: ""

Declared by:

<nix-darwin/modules/services/synergy>
services.synergy.client.serverAddress
The server address is of the form: [hostname][:port]. The hostname must be the address or hostname of the server. The port overrides the default port, 24800.

Type: string

Declared by:

<nix-darwin/modules/services/synergy>
services.synergy.client.tls.enable
Whether to enable Whether TLS encryption should be used.

Using this requires a TLS certificate that can be generated by starting the Synergy GUI once and entering a valid product key.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/services/synergy>
services.synergy.client.tls.cert
The TLS certificate to use for encryption.

Type: null or string

Default: null

Example: "~/.synergy/SSL/Synergy.pem"

Declared by:

<nix-darwin/modules/services/synergy>
services.synergy.server.enable
Whether to enable the Synergy server (send keyboard and mouse events).

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/synergy>
services.synergy.server.address
Address on which to listen for clients.

Type: string

Default: ""

Declared by:

<nix-darwin/modules/services/synergy>
services.synergy.server.autoStart
Whether the Synergy server should be started automatically.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/services/synergy>
services.synergy.server.configFile
The Synergy server configuration file.

Type: string

Default: "/etc/synergy-server.conf"

Declared by:

<nix-darwin/modules/services/synergy>
services.synergy.server.screenName
Use the given name instead of the hostname to identify this screen in the configuration.

Type: string

Default: ""

Declared by:

<nix-darwin/modules/services/synergy>
services.synergy.server.tls.enable
Whether to enable Whether TLS encryption should be used.

Using this requires a TLS certificate that can be generated by starting the Synergy GUI once and entering a valid product key.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/services/synergy>
services.synergy.server.tls.cert
The TLS certificate to use for encryption.

Type: null or string

Default: null

Example: "~/.synergy/SSL/Synergy.pem"

Declared by:

<nix-darwin/modules/services/synergy>
services.tailscale.enable
Whether to enable Tailscale client daemon.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/services/tailscale.nix>
services.tailscale.package
The package to use for tailscale

Type: package

Default: pkgs.tailscale

Declared by:

<nix-darwin/modules/services/tailscale.nix>
services.tailscale.overrideLocalDns
This option implements Override local DNS as it is not yet implemented in Tailscaled-on-macOS.

To use this option, in the Tailscale control panel:

at least one DNS server is added

Override local DNS is enabled

As this option sets 100.100.100.100 as your sole DNS server, if the requirements above are not met, all non-MagicDNS queries WILL fail.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/services/tailscale.nix>
services.telegraf.enable
Whether to enable telegraf agent.

Type: boolean

Default: false

Example: true

Declared by:

<nix-darwin/modules/services/monitoring/telegraf.nix>
services.telegraf.package
Which telegraf derivation to use

Type: package

Default: pkgs.telegraf

Declared by:

<nix-darwin/modules/services/monitoring/telegraf.nix>
services.telegraf.configUrl
Url to fetch config from

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/services/monitoring/telegraf.nix>
services.telegraf.environmentFiles
File to load as environment file. This is useful to avoid putting secrets into the nix store.

Type: list of absolute path

Default: [ ]

Example:

[
"/run/keys/telegraf.env"
]
Declared by:

<nix-darwin/modules/services/monitoring/telegraf.nix>
services.telegraf.extraConfig
Extra configuration options for telegraf

Type: TOML value

Default: { }

Example:

{
inputs = {
statsd = {
delete_timings = true;
service_address = ":8125";
};
};
outputs = {
influxdb = {
database = "telegraf";
urls = [
"http://localhost:8086"
];
};
};
}
Declared by:

<nix-darwin/modules/services/monitoring/telegraf.nix>
services.trezord.enable
Enable Trezor bridge daemon, for use with Trezor hardware wallets.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/trezord.nix>
services.trezord.emulator.enable
Enable Trezor emulator support.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/trezord.nix>
services.trezord.emulator.port
Listening port for the Trezor emulator.

Type: 16 bit unsigned integer; between 0 and 65535 (both inclusive)

Default: 21324

Declared by:

<nix-darwin/modules/services/trezord.nix>
services.yabai.enable
Whether to enable the yabai window manager.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/yabai>
services.yabai.enableScriptingAddition
Whether to enable yabai’s scripting-addition. SIP must be disabled for this to work.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/services/yabai>
services.yabai.package
The yabai package to use.

Type: absolute path

Default: <derivation yabai-7.1.15>

Declared by:

<nix-darwin/modules/services/yabai>
services.yabai.config
Key/Value pairs to pass to yabai’s ‘config’ domain, via the configuration file.

Type: attribute set

Default: { }

Example:

{
focus_follows_mouse = "autoraise";
mouse_follows_focus = "off";
window_placement = "second_child";
window_opacity = "off";
top_padding = 36;
bottom_padding = 10;
left_padding = 10;
right_padding = 10;
window_gap = 10;
}

Declared by:

<nix-darwin/modules/services/yabai>
services.yabai.extraConfig
Extra arbitrary configuration to append to the configuration file

Type: strings concatenated with “\n”

Default: ""

Example:

yabai -m rule --add app='System Preferences' manage=off

Declared by:

<nix-darwin/modules/services/yabai>
system.activationScripts.<name>.enable
Whether this file should be generated. This option allows specific files to be disabled.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/system/activation-scripts.nix>
system.activationScripts.<name>.source
Path of the source file.

Type: absolute path

Declared by:

<nix-darwin/modules/system/activation-scripts.nix>
system.activationScripts.<name>.target
Name of symlink. Defaults to the attribute name.

Type: string

Default: "‹name›"

Declared by:

<nix-darwin/modules/system/activation-scripts.nix>
system.activationScripts.<name>.text
Text of the file.

Type: strings concatenated with “\n”

Default: ""

Declared by:

<nix-darwin/modules/system/activation-scripts.nix>
system.checks.verifyBuildUsers
Whether to run the Nix build users validation checks.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/system/checks.nix>
system.checks.verifyMacOSVersion
Whether to run the macOS version check.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/system/checks.nix>
system.checks.verifyNixPath
Whether to run the NIX_PATH validation checks.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/system/checks.nix>
system.configurationRevision
The Git revision of the top-level flake from which this configuration was built.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/system/version.nix>
system.darwinLabel
Label to be used in the names of generated outputs.

Type: string

Declared by:

<nix-darwin/modules/system/version.nix>
system.darwinRelease
The nix-darwin release (e.g. 24.11).

Type: string (read only)

Default: "25.11"

Declared by:

<nix-darwin/modules/system/version.nix>
system.defaults.".GlobalPreferences"."com.apple.mouse.scaling"
Sets the mouse tracking speed. Found in the “Mouse” section of “System Preferences”. Set to -1.0 to disable mouse acceleration.

Type: null or floating point number

Default: null

Example: -1.0

Declared by:

<nix-darwin/modules/system/defaults/GlobalPreferences.nix>
system.defaults.".GlobalPreferences"."com.apple.sound.beep.sound"
Sets the system-wide alert sound. Found under “Sound Effects” in the “Sound” section of “System Preferences”. Look in “/System/Library/Sounds” for possible candidates.

Type: null or absolute path

Default: null

Declared by:

<nix-darwin/modules/system/defaults/GlobalPreferences.nix>
system.defaults.ActivityMonitor.IconType
Change the icon in the dock when running.

0: Application Icon

2: Network Usage

3: Disk Activity

5: CPU Usage

6: CPU History Default is null.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/system/defaults/ActivityMonitor.nix>
system.defaults.ActivityMonitor.OpenMainWindow
Open the main window when opening Activity Monitor. Default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/ActivityMonitor.nix>
system.defaults.ActivityMonitor.ShowCategory
Change which processes to show.

100: All Processes

101: All Processes, Hierarchally

102: My Processes

103: System Processes

104: Other User Processes

105: Active Processes

106: Inactive Processes

107: Windowed Processes Default is 100.

Type: null or one of 100, 101, 102, 103, 104, 105, 106, 107

Default: null

Declared by:

<nix-darwin/modules/system/defaults/ActivityMonitor.nix>
system.defaults.ActivityMonitor.SortColumn
Which column to sort the main activity page (such as “CPUUsage”). Default is null.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/system/defaults/ActivityMonitor.nix>
system.defaults.ActivityMonitor.SortDirection
The sort direction of the sort column (0 is decending). Default is null.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/system/defaults/ActivityMonitor.nix>
system.defaults.CustomSystemPreferences
Sets custom system preferences

Type: plist value

Default: { }

Example:

{
NSGlobalDomain = {
TISRomanSwitchState = 1;
};
"com.apple.Safari" = {
"com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled" = true;
};
}
Declared by:

<nix-darwin/modules/system/defaults/CustomPreferences.nix>
system.defaults.CustomUserPreferences
Sets custom user preferences

Type: plist value

Default: { }

Example:

{
NSGlobalDomain = {
TISRomanSwitchState = 1;
};
"com.apple.Safari" = {
"com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled" = true;
};
}
Declared by:

<nix-darwin/modules/system/defaults/CustomPreferences.nix>
system.defaults.LaunchServices.LSQuarantine
Whether to enable quarantine for downloaded applications. The default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/LaunchServices.nix>
system.defaults.NSGlobalDomain.AppleEnableMouseSwipeNavigateWithScrolls
Enables swiping left or right with two fingers to navigate backward or forward. The default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.AppleEnableSwipeNavigateWithScrolls
Enables swiping left or right with two fingers to navigate backward or forward. The default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.AppleFontSmoothing
Sets the level of font smoothing (sub-pixel font rendering).

Type: null or one of 0, 1, 2

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.AppleICUForce24HourTime
Whether to use 24-hour or 12-hour time. The default is based on region settings.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.AppleInterfaceStyle
Set to ‘Dark’ to enable dark mode.

To set to light mode, set this to null and you’ll need to manually run defaults delete -g AppleInterfaceStyle.

This option requires logging out and logging back in to apply.

Type: null or value “Dark” (singular enum)

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.AppleInterfaceStyleSwitchesAutomatically
Whether to automatically switch between light and dark mode. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.AppleKeyboardUIMode
Configures the keyboard control behavior. The default is 0.

0 = Disabled 2 = Enabled on Sonoma or later 3 = Enabled on older macOS versions

Type: null or one of 0, 2, 3

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.AppleMeasurementUnits
Whether to use centimeters (metric) or inches (US, UK) as the measurement unit. The default is based on region settings.

Type: null or one of “Centimeters”, “Inches”

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.AppleMetricUnits
Whether to use the metric system. The default is based on region settings.

Type: null or one of 0, 1

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.ApplePressAndHoldEnabled
Whether to enable the press-and-hold feature. The default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.AppleScrollerPagingBehavior
Jump to the spot that’s clicked on the scroll bar. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.AppleShowAllExtensions
Whether to show all file extensions in Finder. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.AppleShowAllFiles
Whether to always show hidden files. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.AppleShowScrollBars
When to show the scrollbars. Options are ‘WhenScrolling’, ‘Automatic’ and ‘Always’.

Type: null or one of “WhenScrolling”, “Automatic”, “Always”

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.AppleSpacesSwitchOnActivate
Whether or not to switch to a workspace that has a window of the application open, that is switched to. The default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.AppleTemperatureUnit
Whether to use Celsius or Fahrenheit. The default is based on region settings.

Type: null or one of “Celsius”, “Fahrenheit”

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.AppleWindowTabbingMode
Sets the window tabbing when opening a new document: ‘manual’, ‘always’, or ‘fullscreen’. The default is ‘fullscreen’.

Type: null or one of “manual”, “always”, “fullscreen”

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.InitialKeyRepeat
Apple menu > System Preferences > Keyboard

If you press and hold certain keyboard keys when in a text area, the key’s character begins to repeat. For example, the Delete key continues to remove text for as long as you hold it down.

This sets how long you must hold down the key before it starts repeating.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.KeyRepeat
Apple menu > System Preferences > Keyboard

If you press and hold certain keyboard keys when in a text area, the key’s character begins to repeat. For example, the Delete key continues to remove text for as long as you hold it down.

This sets how fast it repeats once it starts.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.NSAutomaticCapitalizationEnabled
Whether to enable automatic capitalization. The default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.NSAutomaticDashSubstitutionEnabled
Whether to enable smart dash substitution. The default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.NSAutomaticInlinePredictionEnabled
Whether to enable inline predictive text. The default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.NSAutomaticPeriodSubstitutionEnabled
Whether to enable smart period substitution. The default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.NSAutomaticQuoteSubstitutionEnabled
Whether to enable smart quote substitution. The default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.NSAutomaticSpellingCorrectionEnabled
Whether to enable automatic spelling correction. The default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.NSAutomaticWindowAnimationsEnabled
Whether to animate opening and closing of windows and popovers. The default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.NSDisableAutomaticTermination
Whether to disable the automatic termination of inactive apps.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.NSDocumentSaveNewDocumentsToCloud
Whether to save new documents to iCloud by default. The default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.NSNavPanelExpandedStateForSaveMode
Whether to use expanded save panel by default. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.NSNavPanelExpandedStateForSaveMode2
Whether to use expanded save panel by default. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.NSScrollAnimationEnabled
Whether to enable smooth scrolling. The default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.NSTableViewDefaultSizeMode
Sets the size of the finder sidebar icons: 1 (small), 2 (medium) or 3 (large). The default is 3.

Type: null or one of 1, 2, 3

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.NSTextShowsControlCharacters
Whether to display ASCII control characters using caret notation in standard text views. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.NSUseAnimatedFocusRing
Whether to enable the focus ring animation. The default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.NSWindowResizeTime
Sets the speed speed of window resizing. The default is given in the example.

Type: null or floating point number

Default: null

Example: 0.2

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.NSWindowShouldDragOnGesture
Whether to enable moving window by holding anywhere on it like on Linux. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.PMPrintingExpandedStateForPrint
Whether to use the expanded print panel by default. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.PMPrintingExpandedStateForPrint2
Whether to use the expanded print panel by default. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain.\_HIHideMenuBar
Whether to autohide the menu bar. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain."com.apple.keyboard.fnState"
Use F1, F2, etc. keys as standard function keys.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain."com.apple.mouse.tapBehavior"
Configures the trackpad tap behavior. Mode 1 enables tap to click.

Type: null or value 1 (singular enum)

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain."com.apple.sound.beep.feedback"
Apple menu > System Preferences > Sound

Make a feedback sound when the system volume changed. This setting accepts the integers 0 or 1. Defaults to 1.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain."com.apple.sound.beep.volume"
Apple menu > System Preferences > Sound

Sets the beep/alert volume level from 0.000 (muted) to 1.000 (100% volume).

75% = 0.7788008

50% = 0.6065307

25% = 0.4723665

Type: null or floating point number

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain."com.apple.springing.delay"
Set the spring loading delay for directories. The default is given in the example.

Type: null or floating point number

Default: null

Example: 1.0

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain."com.apple.springing.enabled"
Whether to enable spring loading (expose) for directories.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain."com.apple.swipescrolldirection"
Whether to enable “Natural” scrolling direction. The default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain."com.apple.trackpad.enableSecondaryClick"
Whether to enable trackpad secondary click. The default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain."com.apple.trackpad.forceClick"
Whether to enable trackpad force click.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain."com.apple.trackpad.scaling"
Configures the trackpad tracking speed (0 to 3). The default is “1”.

Type: null or floating point number

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.NSGlobalDomain."com.apple.trackpad.trackpadCornerClickBehavior"
Configures the trackpad corner click behavior. Mode 1 enables right click.

Type: null or value 1 (singular enum)

Default: null

Declared by:

<nix-darwin/modules/system/defaults/NSGlobalDomain.nix>
system.defaults.SoftwareUpdate.AutomaticallyInstallMacOSUpdates
Automatically install Mac OS software updates. Defaults to false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/SoftwareUpdate.nix>
system.defaults.WindowManager.AppWindowGroupingBehavior
Grouping strategy when showing windows from an application. false means “One at a time” true means “All at once”

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/WindowManager.nix>
system.defaults.WindowManager.AutoHide
Auto hide stage strip showing recent apps. Default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/WindowManager.nix>
system.defaults.WindowManager.EnableStandardClickToShowDesktop
Click wallpaper to reveal desktop Clicking your wallpaper will move all windows out of the way to allow access to your desktop items and widgets. Default is true. false means “Only in Stage Manager” true means “Always”

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/WindowManager.nix>
system.defaults.WindowManager.EnableTiledWindowMargins
Enable window margins when tiling windows. The default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/WindowManager.nix>
system.defaults.WindowManager.EnableTilingByEdgeDrag
Enable dragging windows to screen edges to tile them. The default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/WindowManager.nix>
system.defaults.WindowManager.EnableTilingOptionAccelerator
Enable holding alt to tile windows. The default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/WindowManager.nix>
system.defaults.WindowManager.EnableTopTilingByEdgeDrag
Enable dragging windows to the menu bar to fill the screen. The default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/WindowManager.nix>
system.defaults.WindowManager.GloballyEnabled
Enable Stage Manager Stage Manager arranges your recent windows into a single strip for reduced clutter and quick access. Default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/WindowManager.nix>
system.defaults.WindowManager.HideDesktop
Hide items in Stage Manager.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/WindowManager.nix>
system.defaults.WindowManager.StageManagerHideWidgets
Hide widgets in Stage Manager.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/WindowManager.nix>
system.defaults.WindowManager.StandardHideDesktopIcons
Hide items on desktop.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/WindowManager.nix>
system.defaults.WindowManager.StandardHideWidgets
Hide widgets on desktop.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/WindowManager.nix>
system.defaults.controlcenter.AirDrop
Apple menu > System Preferences > Control Center > AirDrop

Show a AirDrop control in menu bar. Default is null.

18 = Display icon in menu bar 24 = Hide icon in menu bar

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/controlcenter.nix>
system.defaults.controlcenter.BatteryShowPercentage
Apple menu > System Preferences > Control Center > Battery

Show a battery percentage in menu bar. Default is null.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/controlcenter.nix>
system.defaults.controlcenter.Bluetooth
Apple menu > System Preferences > Control Center > Bluetooth

Show a bluetooth control in menu bar. Default is null.

18 = Display icon in menu bar 24 = Hide icon in menu bar

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/controlcenter.nix>
system.defaults.controlcenter.Display
Apple menu > System Preferences > Control Center > Display

Show a Screen Brightness control in menu bar. Default is null.

18 = Display icon in menu bar 24 = Hide icon in menu bar

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/controlcenter.nix>
system.defaults.controlcenter.FocusModes
Apple menu > System Preferences > Control Center > Focus

Show a Focus control in menu bar. Default is null.

18 = Display icon in menu bar 24 = Hide icon in menu bar

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/controlcenter.nix>
system.defaults.controlcenter.NowPlaying
Apple menu > System Preferences > Control Center > Now Playing

Show a Now Playing control in menu bar. Default is null.

18 = Display icon in menu bar 24 = Hide icon in menu bar

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/controlcenter.nix>
system.defaults.controlcenter.Sound
Apple menu > System Preferences > Control Center > Sound

Show a sound control in menu bar . Default is null.

18 = Display icon in menu bar 24 = Hide icon in menu bar

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/controlcenter.nix>
system.defaults.dock.enable-spring-load-actions-on-all-items
Enable spring loading for all Dock items. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.appswitcher-all-displays
Whether to display the appswitcher on all displays or only the main one. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.autohide
Whether to automatically hide and show the dock. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.autohide-delay
Sets the speed of the autohide delay. The default is given in the example.

Type: null or floating point number

Default: null

Example: 0.24

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.autohide-time-modifier
Sets the speed of the animation when hiding/showing the Dock. The default is given in the example.

Type: null or floating point number

Default: null

Example: 1.0

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.dashboard-in-overlay
Whether to hide Dashboard as a Space. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.expose-animation-duration
Sets the speed of the Mission Control animations. The default is given in the example.

Type: null or floating point number

Default: null

Example: 1.0

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.expose-group-apps
Whether to group windows by application in Mission Control’s Exposé. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.largesize
Magnified icon size on hover. The default is 16.

Type: null or integer between 16 and 128 (both inclusive)

Default: null

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.launchanim
Animate opening applications from the Dock. The default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.magnification
Magnify icon on hover. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.mineffect
Set the minimize/maximize window effect. The default is genie.

Type: null or one of “genie”, “suck”, “scale”

Default: null

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.minimize-to-application
Whether to minimize windows into their application icon. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.mouse-over-hilite-stack
Enable highlight hover effect for the grid view of a stack in the Dock.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.mru-spaces
Whether to automatically rearrange spaces based on most recent use. The default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.orientation
Position of the dock on screen. The default is “bottom”.

Type: null or one of “bottom”, “left”, “right”

Default: null

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.persistent-apps
Persistent applications, spacers, files, and folders in the dock.

Type: null or (list of (attribute-tagged union or (string or absolute path) convertible to it))

Default: null

Example:

[
{
app = "/Applications/Safari.app";
}
{
spacer = {
small = false;
};
}
{
spacer = {
small = true;
};
}
{
folder = "/System/Applications/Utilities";
}
{
file = "/User/example/Downloads/test.csv";
}
]
Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.persistent-apps.\*.app
An application to be added to the dock.

Type: string

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.persistent-apps.\*.file
A file to be added to the dock.

Type: string

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.persistent-apps.\*.folder
A folder to be added to the dock.

Type: string

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.persistent-apps.\*.spacer
A spacer to be added to the dock. Can be small or regular size.

Type: submodule

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.persistent-apps.\*.spacer.small
Whether the spacer is small.

Type: boolean

Default: false

system.defaults.dock.persistent-others
Persistent folders in the dock.

Type: null or (list of (absolute path or string))

Default: null

Example:

[
"~/Documents"
"~/Downloads"
]
Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.scroll-to-open
Scroll up on a Dock icon to show all Space’s opened windows for an app, or open stack. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.show-process-indicators
Show indicator lights for open applications in the Dock. The default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.show-recents
Show recent applications in the dock. The default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.showhidden
Whether to make icons of hidden applications tranclucent. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.slow-motion-allowed
Allow for slow-motion minimize effect while holding Shift key. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.static-only
Show only open applications in the Dock. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.tilesize
Size of the icons in the dock. The default is 64.

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.wvous-bl-corner
Hot corner action for bottom left corner. Valid values include:

1: Disabled

2: Mission Control

3: Application Windows

4: Desktop

5: Start Screen Saver

6: Disable Screen Saver

7: Dashboard

10: Put Display to Sleep

11: Launchpad

12: Notification Center

13: Lock Screen

14: Quick Note

Type: null or (positive integer, meaning >0)

Default: null

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.wvous-br-corner
Hot corner action for bottom right corner. Valid values include:

1: Disabled

2: Mission Control

3: Application Windows

4: Desktop

5: Start Screen Saver

6: Disable Screen Saver

7: Dashboard

10: Put Display to Sleep

11: Launchpad

12: Notification Center

13: Lock Screen

14: Quick Note

Type: null or (positive integer, meaning >0)

Default: null

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.wvous-tl-corner
Hot corner action for top left corner. Valid values include:

1: Disabled

2: Mission Control

3: Application Windows

4: Desktop

5: Start Screen Saver

6: Disable Screen Saver

7: Dashboard

10: Put Display to Sleep

11: Launchpad

12: Notification Center

13: Lock Screen

14: Quick Note

Type: null or (positive integer, meaning >0)

Default: null

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.dock.wvous-tr-corner
Hot corner action for top right corner. Valid values include:

1: Disabled

2: Mission Control

3: Application Windows

4: Desktop

5: Start Screen Saver

6: Disable Screen Saver

7: Dashboard

10: Put Display to Sleep

11: Launchpad

12: Notification Center

13: Lock Screen

14: Quick Note

Type: null or (positive integer, meaning >0)

Default: null

Declared by:

<nix-darwin/modules/system/defaults/dock.nix>
system.defaults.finder.AppleShowAllExtensions
Whether to always show file extensions. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/finder.nix>
system.defaults.finder.AppleShowAllFiles
Whether to always show hidden files. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/finder.nix>
system.defaults.finder.CreateDesktop
Whether to show icons on the desktop or not. The default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/finder.nix>
system.defaults.finder.FXDefaultSearchScope
Change the default search scope. Use “SCcf” to default to current folder. The default is unset (“This Mac”).

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/system/defaults/finder.nix>
system.defaults.finder.FXEnableExtensionChangeWarning
Whether to show warnings when change the file extension of files. The default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/finder.nix>
system.defaults.finder.FXPreferredViewStyle
Change the default finder view. “icnv” = Icon view, “Nlsv” = List view, “clmv” = Column View, “Flwv” = Gallery View The default is icnv.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/system/defaults/finder.nix>
system.defaults.finder.FXRemoveOldTrashItems
Remove items in the trash after 30 days. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/finder.nix>
system.defaults.finder.NewWindowTarget
Change the default folder shown in Finder windows. “Other” corresponds to the value of NewWindowTargetPath. The default is unset (“Recents”).

Type: null or one of “Computer”, “OS volume”, “Home”, “Desktop”, “Documents”, “Recents”, “iCloud Drive”, “Other”

Default: null

Declared by:

<nix-darwin/modules/system/defaults/finder.nix>
system.defaults.finder.NewWindowTargetPath
Sets the URI to open when NewWindowTarget is “Other”. Spaces and similar characters must be escaped. If the value is invalid, Finder will open your home directory. Example: “file:///Users/foo/long%20cat%20pics”. The default is unset.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/system/defaults/finder.nix>
system.defaults.finder.QuitMenuItem
Whether to allow quitting of the Finder. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/finder.nix>
system.defaults.finder.ShowExternalHardDrivesOnDesktop
Whether to show external disks on desktop. The default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/finder.nix>
system.defaults.finder.ShowHardDrivesOnDesktop
Whether to show hard disks on desktop. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/finder.nix>
system.defaults.finder.ShowMountedServersOnDesktop
Whether to show connected servers on desktop. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/finder.nix>
system.defaults.finder.ShowPathbar
Show path breadcrumbs in finder windows. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/finder.nix>
system.defaults.finder.ShowRemovableMediaOnDesktop
Whether to show removable media (CDs, DVDs and iPods) on desktop. The default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/finder.nix>
system.defaults.finder.ShowStatusBar
Show status bar at bottom of finder windows with item/disk space stats. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/finder.nix>
system.defaults.finder.\_FXShowPosixPathInTitle
Whether to show the full POSIX filepath in the window title. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/finder.nix>
system.defaults.finder.\_FXSortFoldersFirst
Keep folders on top when sorting by name. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/finder.nix>
system.defaults.finder.\_FXSortFoldersFirstOnDesktop
Keep folders on top when sorting by name on the desktop. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/finder.nix>
system.defaults.hitoolbox.AppleFnUsageType
Chooses what happens when you press the Fn key on the keyboard. A restart is required for this setting to take effect.

The default is unset (“Show Emoji & Symbols”).

Type: null or one of “Do Nothing”, “Change Input Source”, “Show Emoji & Symbols”, “Start Dictation”

Default: null

Declared by:

<nix-darwin/modules/system/defaults/hitoolbox.nix>
system.defaults.iCal.CalendarSidebarShown
Show calendar list. The default is false.

This requires restarting Calendar.app to show.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/iCal.nix>
system.defaults.iCal."TimeZone support enabled"
Turn on time zone support. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/iCal.nix>
system.defaults.iCal."first day of week"
Set the day to start week on in the Calendar. The default is “System Setting”.

System Setting means inherit the value from Language & Region.

Type: null or one of “System Setting”, “Sunday”, “Monday”, “Tuesday”, “Wednesday”, “Thursday”, “Friday”, “Saturday”

Default: null

Declared by:

<nix-darwin/modules/system/defaults/iCal.nix>
system.defaults.loginwindow.DisableConsoleAccess
Disables the ability for a user to access the console by typing “>console” for a username at the login window. Default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/loginwindow.nix>
system.defaults.loginwindow.GuestEnabled
Apple menu > System Preferences > Users and Groups > Login Options

Allow users to login to the machine as guests using the Guest account. Default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/loginwindow.nix>
system.defaults.loginwindow.LoginwindowText
Text to be shown on the login window. Default is “\\U03bb”.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/system/defaults/loginwindow.nix>
system.defaults.loginwindow.PowerOffDisabledWhileLoggedIn
Apple menu > System Preferences > Users and Groups > Login Options

If set to true, the Power Off menu item will be disabled when the user is logged in. Default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/loginwindow.nix>
system.defaults.loginwindow.RestartDisabled
Apple menu > System Preferences > Users and Groups > Login Options

Hides the Restart button on the login screen. Default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/loginwindow.nix>
system.defaults.loginwindow.RestartDisabledWhileLoggedIn
Apple menu > System Preferences > Users and Groups > Login Options

Disables the “Restart” option when users are logged in. Default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/loginwindow.nix>
system.defaults.loginwindow.SHOWFULLNAME
Apple menu > System Preferences > Users and Groups > Login Options

Displays login window as a name and password field instead of a list of users. Default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/loginwindow.nix>
system.defaults.loginwindow.ShutDownDisabled
Apple menu > System Preferences > Users and Groups > Login Options

Hides the Shut Down button on the login screen. Default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/loginwindow.nix>
system.defaults.loginwindow.ShutDownDisabledWhileLoggedIn
Apple menu > System Preferences > Users and Groups > Login Options

Disables the “Shutdown” option when users are logged in. Default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/loginwindow.nix>
system.defaults.loginwindow.SleepDisabled
Apple menu > System Preferences > Users and Groups > Login Options

Hides the Sleep button on the login screen. Default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/loginwindow.nix>
system.defaults.loginwindow.autoLoginUser
Apple menu > System Preferences > Users and Groups > Login Options

Auto login the supplied user on boot. Default is Off.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/system/defaults/loginwindow.nix>
system.defaults.magicmouse.MouseButtonMode
“OneButton”: any tap is a left click. “TwoButton”: allow left- and right-clicking.

Type: null or one of “OneButton”, “TwoButton”

Default: null

Declared by:

<nix-darwin/modules/system/defaults/magicmouse.nix>
system.defaults.menuExtraClock.FlashDateSeparators
When enabled, the clock indicator (which by default is the colon) will flash on and off each second. Default is null.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/clock.nix>
system.defaults.menuExtraClock.IsAnalog
Show an analog clock instead of a digital one. Default is null.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/clock.nix>
system.defaults.menuExtraClock.Show24Hour
Show a 24-hour clock, instead of a 12-hour clock. Default is null.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/clock.nix>
system.defaults.menuExtraClock.ShowAMPM
Show the AM/PM label. Useful if Show24Hour is false. Default is null.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/clock.nix>
system.defaults.menuExtraClock.ShowDate
Show the full date. Default is null.

0 = When space allows 1 = Always 2 = Never

Type: null or one of 0, 1, 2

Default: null

Declared by:

<nix-darwin/modules/system/defaults/clock.nix>
system.defaults.menuExtraClock.ShowDayOfMonth
Show the day of the month. Default is null.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/clock.nix>
system.defaults.menuExtraClock.ShowDayOfWeek
Show the day of the week. Default is null.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/clock.nix>
system.defaults.menuExtraClock.ShowSeconds
Show the clock with second precision, instead of minutes. Default is null.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/clock.nix>
system.defaults.screencapture.disable-shadow
Disable drop shadow border around screencaptures. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/screencapture.nix>
system.defaults.screencapture.include-date
Include date and time in screenshot filenames. The default is true. Screenshot 2024-01-09 at 13.27.20.png would be an example for true.

Screenshot.png Screenshot 1.png would be an example for false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/screencapture.nix>
system.defaults.screencapture.location
The filesystem path to which screencaptures should be written.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/system/defaults/screencapture.nix>
system.defaults.screencapture.show-thumbnail
Show thumbnail after screencapture before writing to file. The default is true.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/screencapture.nix>
system.defaults.screencapture.target
Target to which screencapture should save screenshot to. The default is “file”. Valid values include:

file: Saves as a file in location specified by system.defaults.screencapture.location

clipboard: Saves screenshot to clipboard

preview: Opens screenshot in Preview app

mail

messages

Type: null or one of “file”, “clipboard”, “preview”, “mail”, “messages”

Default: null

Declared by:

<nix-darwin/modules/system/defaults/screencapture.nix>
system.defaults.screencapture.type
The image format to use, such as “jpg”.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/system/defaults/screencapture.nix>
system.defaults.screensaver.askForPassword
If true, the user is prompted for a password when the screen saver is unlocked or stopped. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/screensaver.nix>
system.defaults.screensaver.askForPasswordDelay
The number of seconds to delay before the password will be required to unlock or stop the screen saver (the grace period).

Type: null or signed integer

Default: null

Declared by:

<nix-darwin/modules/system/defaults/screensaver.nix>
system.defaults.smb.NetBIOSName
Hostname to use for NetBIOS.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/system/defaults/smb.nix>
system.defaults.smb.ServerDescription
Hostname to use for sharing services.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/system/defaults/smb.nix>
system.defaults.spaces.spans-displays
Apple menu > System Preferences > Mission Control

Displays have separate Spaces (note a logout is required before this setting will take effect).

false = each physical display has a separate space (Mac default) true = one space spans across all physical displays

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/spaces.nix>
system.defaults.trackpad.ActuationStrength
0 to enable Silent Clicking, 1 to disable. The default is 1.

Type: null or one of 0, 1

Default: null

Declared by:

<nix-darwin/modules/system/defaults/trackpad.nix>
system.defaults.trackpad.Clicking
Whether to enable trackpad tap to click. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/trackpad.nix>
system.defaults.trackpad.Dragging
Whether to enable tap-to-drag. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/trackpad.nix>
system.defaults.trackpad.FirstClickThreshold
For normal click: 0 for light clicking, 1 for medium, 2 for firm. The default is 1.

Type: null or one of 0, 1, 2

Default: null

Declared by:

<nix-darwin/modules/system/defaults/trackpad.nix>
system.defaults.trackpad.SecondClickThreshold
For force touch: 0 for light clicking, 1 for medium, 2 for firm. The default is 1.

Type: null or one of 0, 1, 2

Default: null

Declared by:

<nix-darwin/modules/system/defaults/trackpad.nix>
system.defaults.trackpad.TrackpadRightClick
Whether to enable trackpad right click. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/trackpad.nix>
system.defaults.trackpad.TrackpadThreeFingerDrag
Whether to enable three finger drag. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/trackpad.nix>
system.defaults.trackpad.TrackpadThreeFingerTapGesture
0 to disable three finger tap, 2 to trigger Look up & data detectors. The default is 2.

Type: null or one of 0, 2

Default: null

Declared by:

<nix-darwin/modules/system/defaults/trackpad.nix>
system.defaults.universalaccess.closeViewScrollWheelToggle
Use scroll gesture with the Ctrl (^) modifier key to zoom. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/universalaccess.nix>
system.defaults.universalaccess.closeViewZoomFollowsFocus
Follow the keyboard focus while zoomed in. Without setting closeViewScrollWheelToggle this has no effect. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/universalaccess.nix>
system.defaults.universalaccess.mouseDriverCursorSize
Set the size of cursor. 1 for normal, 4 for maximum. The default is 1.

Type: null or floating point number

Default: null

Example: 1.5

Declared by:

<nix-darwin/modules/system/defaults/universalaccess.nix>
system.defaults.universalaccess.reduceMotion
Disable animation when switching screens or opening apps

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/universalaccess.nix>
system.defaults.universalaccess.reduceTransparency
Disable transparency in the menu bar and elsewhere. The default is false.

Type: null or boolean

Default: null

Declared by:

<nix-darwin/modules/system/defaults/universalaccess.nix>
system.keyboard.enableKeyMapping
Whether to enable keyboard mappings.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/system/keyboard.nix>
system.keyboard.nonUS.remapTilde
Whether to remap the Tilde key on non-us keyboards.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/system/keyboard.nix>
system.keyboard.remapCapsLockToControl
Whether to remap the Caps Lock key to Control.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/system/keyboard.nix>
system.keyboard.remapCapsLockToEscape
Whether to remap the Caps Lock key to Escape.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/system/keyboard.nix>
system.keyboard.swapLeftCommandAndLeftAlt
Whether to swap the left Command key and left Alt key.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/system/keyboard.nix>
system.keyboard.swapLeftCtrlAndFn
Whether to swap the left Control key and Fn (Globe) key.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/system/keyboard.nix>
system.nixpkgsRelease
The nixpkgs release (e.g. 24.11).

Type: string (read only)

Default: "25.11"

Declared by:

<nix-darwin/modules/system/version.nix>
system.patches
Set of patches to apply to /.

Warning
This can modify everything so use with caution.

Useful for safely changing system files. Unlike the etc module this won’t remove or modify files with unexpected content.

Type: list of absolute path

Default: [ ]

Example:

[
(pkgs.writeText "bashrc.patch" '''
--- a/etc/bashrc
+++ b/etc/bashrc
@@ -8,3 +8,5 @@
shopt -s checkwinsize

     [ -r "/etc/bashrc_$TERM_PROGRAM" ] && . "/etc/bashrc_$TERM_PROGRAM"
    +
    +if test -e /etc/static/bashrc; then . /etc/static/bashrc; fi

''')
]

Declared by:

<nix-darwin/modules/system/patches.nix>
system.primaryUser
The user used for options that previously applied to the user running darwin-rebuild.

This is a transition mechanism as nix-darwin reorganizes its options and will eventually be unnecessary and removed.

Type: null or string

Default: null

Declared by:

<nix-darwin/modules/system/primary-user.nix>
system.profile
Profile to use for the system.

Type: absolute path

Default: "/nix/var/nix/profiles/system"

Declared by:

<nix-darwin/modules/system>
system.startup.chime
Whether to enable the startup chime.

By default, this option does not affect your system configuration in any way. However, this means that after it has been set once, unsetting it will not return to the old behavior. It will allow the setting to be controlled in System Settings, though.

Type: null or boolean

Default: null

Example: false

Declared by:

<nix-darwin/modules/system/startup.nix>
system.stateVersion
Every once in a while, a new nix-darwin release may change configuration defaults in a way incompatible with stateful data. For instance, if the default version of PostgreSQL changes, the new version will probably be unable to read your existing databases. To prevent such breakage, you can set the value of this option to the nix-darwin release with which you want to be compatible. The effect is that nix-darwin will option defaults corresponding to the specified release (such as using an older version of PostgreSQL).

Type: integer between 1 and 6 (both inclusive)

Default: 6

Declared by:

<nix-darwin/modules/system/version.nix>
system.tools.darwin-option.enable
Whether to enable darwin-option script.

Type: boolean

Default: true

Example: true

Declared by:

<nix-darwin/modules/nix/nix-darwin.nix>
system.tools.darwin-rebuild.enable
Whether to enable darwin-rebuild script.

Type: boolean

Default: true

Example: true

Declared by:

<nix-darwin/modules/nix/nix-darwin.nix>
system.tools.darwin-uninstaller.enable
Whether to enable darwin-uninstaller script.

Type: boolean

Default: true

Example: true

Declared by:

<nix-darwin/modules/nix/nix-darwin.nix>
system.tools.darwin-version.enable
Whether to enable darwin-version script.

Type: boolean

Default: true

Example: true

Declared by:

<nix-darwin/modules/nix/nix-darwin.nix>
time.timeZone
The time zone used when displaying times and dates. See https://en.wikipedia.org/wiki/List_of_tz_database_time_zones or run sudo systemsetup -listtimezones for a comprehensive list of possible values for this setting.

Type: null or string

Default: null

Example: "America/New_York"

Declared by:

<nix-darwin/modules/time>
users.groups
Configuration for groups.

Type: attribute set of (submodule)

Default: { }

Declared by:

<nix-darwin/modules/users>
users.groups.<name>.description
The group’s description.

Type: string

Default: ""

Declared by:

<nix-darwin/modules/users>
users.groups.<name>.gid
The group’s GID.

Type: signed integer

Declared by:

<nix-darwin/modules/users>
users.groups.<name>.members
The group’s members.

Type: list of string

Default: [ ]

Declared by:

<nix-darwin/modules/users>
users.groups.<name>.name
The group’s name. If undefined, the name of the attribute set will be used.

Type: string

Default: "‹name›"

Declared by:

<nix-darwin/modules/users>
users.knownGroups
List of groups owned and managed by nix-darwin. Used to indicate what users are safe to create/delete based on the configuration. Don’t add system groups to this.

Type: list of string

Default: [ ]

Declared by:

<nix-darwin/modules/users>
users.knownUsers
List of users owned and managed by nix-darwin. Used to indicate what users are safe to create/delete based on the configuration. Don’t add the admin user or other system users to this.

Type: list of string

Default: [ ]

Declared by:

<nix-darwin/modules/users>
users.users
Configuration for users.

Type: attribute set of (submodule)

Default: { }

Declared by:

<nix-darwin/modules/users>
<nix-darwin/modules/programs/ssh.nix>
users.users.<name>.packages
The set of packages that should be made availabe to the user. This is in contrast to environment.systemPackages, which adds packages to all users.

Type: list of package

Default: [ ]

Example: [ pkgs.firefox pkgs.thunderbird ]

Declared by:

<nix-darwin/modules/users>
users.users.<name>.createHome
Create the home directory when creating the user.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/users>
users.users.<name>.description
A short description of the user account, typically the user’s full name.

This defaults to null which means, on creation, sysadminctl will pick the description which is usually always name.

Using an empty name is not supported and breaks macOS like making the user not appear in Directory Utility.

Type: null or non-empty string

Default: null

Example: "Alice Q. User"

Declared by:

<nix-darwin/modules/users>
users.users.<name>.gid
The user’s primary group.

Type: signed integer

Default: 20

Declared by:

<nix-darwin/modules/users>
users.users.<name>.home
The user’s home directory. This defaults to null.

When this is set to null, if the user has not been created yet, they will be created with the home directory /var/empty to match the old default.

Type: null or absolute path

Default: null

Declared by:

<nix-darwin/modules/users>
users.users.<name>.ignoreShellProgramCheck
By default, nix-darwin will check that programs.SHELL.enable is set to true if the user has a custom shell specified. If that behavior isn’t required and there are custom overrides in place to make sure that the shell is functional, set this to true.

Type: boolean

Default: false

Declared by:

<nix-darwin/modules/users>
users.users.<name>.isHidden
Whether to make the user account hidden.

Type: boolean

Default: true

Declared by:

<nix-darwin/modules/users>
users.users.<name>.name
The name of the user account. If undefined, the name of the attribute set will be used.

Type: non-empty string

Default: "‹name›"

Declared by:

<nix-darwin/modules/users>
users.users.<name>.openssh.authorizedKeys.keyFiles
A list of files each containing one OpenSSH public key that should be added to the user’s authorized keys. The contents of the files are read at build time and added to a file that the SSH daemon reads in addition to the the user’s authorized_keys file. You can combine the keyFiles and keys options.

Type: list of absolute path

Default: [ ]

Declared by:

<nix-darwin/modules/programs/ssh.nix>
users.users.<name>.openssh.authorizedKeys.keys
A list of verbatim OpenSSH public keys that should be added to the user’s authorized keys. The keys are added to a file that the SSH daemon reads in addition to the the user’s authorized_keys file. You can combine the keys and keyFiles options. Warning: If you are using NixOps then don’t use this option since it will replace the key required for deployment via ssh.

Type: list of string

Default: [ ]

Declared by:

<nix-darwin/modules/programs/ssh.nix>
users.users.<name>.shell
The user’s shell. This defaults to null.

When this is set to null, if the user has not been created yet, they will be created with the shell /usr/bin/false to prevent interactive login. If the user already exists, the value is considered managed by macOS and nix-darwin will not change it.

Type: null or package or absolute path

Default: null

Example: pkgs.bashInteractive

Declared by:

<nix-darwin/modules/users>
users.users.<name>.uid
The user’s UID.

Type: signed integer

Declared by:

<nix-darwin/modules/users>
