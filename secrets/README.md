# Secrets Management

## First-time setup

1. Generate age key:
   ```bash
   mkdir -p ~/.config/age
   age-keygen -o ~/.config/age/keys.txt
   ```

2. Copy public key to .sops.yaml (replace PLACEHOLDER)

3. Create encrypted secrets file:
   ```bash
   sops secrets/secrets.yaml
   ```

4. Uncomment sops config in modules/secrets.nix

## Usage

Edit secrets:
```bash
sops secrets/secrets.yaml
```

Add to flake.nix imports:
```nix
./modules/secrets.nix
```
