# Preprod accounts the `preprod-curl` wrapper can sign in as (`--as <account>`).
# One file per account: ~/.config/secrets/preprod-account-<account> (email,
# then password). settings.nix and checks/preprod-curl.nix derive the exact
# sandbox allowRead paths from this list: slugs match the script's ACCOUNT_RE.
[ "agent" ]
