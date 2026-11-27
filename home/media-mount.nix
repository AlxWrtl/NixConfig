# Mounts the ROG Z13 Samba share `media` at login and keeps it mounted.
# Through the ROG's Tailscale address: the same address works at home and
# away (its ufw admits tailscale0). The password comes from the login
# Keychain: mount once by hand in Finder (Cmd-K, smb://alx@100.114.53.64/media,
# "Remember this password"); until then each tick shows the login dialog.
# Never mounts unless the route to the ROG goes through Tailscale.
# Pause: launchctl bootout gui/$UID/org.nix-community.home.mount-rog-media
{
  config,
  pkgs,
  ...
}:
let
  rogIp = "100.114.53.64";
  share = "smb://alx@${rogIp}/media";
  mountMedia = pkgs.writeShellScript "mount-rog-media" ''
    /sbin/mount | /usr/bin/grep -qE '@${rogIp}/media on /Volumes/media(-[0-9]+)? \(smbfs' && exit 0
    iface=$(/sbin/route -n get ${rogIp} 2>/dev/null | /usr/bin/awk '/interface:/{print $2}')
    case $iface in utun*) ;; *) exit 0 ;; esac
    if ! /sbin/ifconfig "$iface" 2>/dev/null | /usr/bin/grep -q 'inet 100\.'; then
      exit 0
    fi
    /usr/bin/nc -z -G 3 ${rogIp} 445 || exit 0
    /usr/bin/osascript -e 'mount volume "${share}"'
  '';
in
{
  launchd.agents.mount-rog-media = {
    enable = true;
    config = {
      ProgramArguments = [ "${mountMedia}" ];
      RunAtLoad = true;
      # remount after sleep or a network change
      StartInterval = 300;
      StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/mount-rog-media.log";
    };
  };
}
