# Roadmap to S Tier (100/100)

## Current Status: A++ (98/100)

Configuration nix-darwin optimisée avec toutes les best practices 2026.

## Prochaines étapes pour S Tier (+2pts)

### 1. CI/CD Automation (+0.5pt)

**Objectif**: Automatiser validation avant merge/push

**GitHub Actions workflow** (`.github/workflows/nix-check.yml`):
```yaml
name: Nix Configuration Check
on: [push, pull_request]
jobs:
  check:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v24
      - name: Nix flake check
        run: nix flake check
      - name: Build configuration
        run: nix build .#darwinConfigurations.alex-mbp.system
```

**Bénéfices**:
- Détection erreurs avant merge
- Validation automatique format
- Build preview sur PRs

---

### 2. Integration Tests (+0.75pt)

**Objectif**: Tests réels sur VM/container

**VM Testing avec Tart** (macOS native):
```nix
# tests/integration.nix
{ pkgs, ... }:
{
  testScript = ''
    machine.wait_for_unit("nix-daemon")
    machine.succeed("nix --version")
    machine.succeed("darwin-rebuild --version")

    # Test services
    machine.succeed("launchctl list | grep org.nixos.security-vulnerability-scan")
    machine.succeed("launchctl list | grep org.nixos.pre-gc-rollback-test")

    # Test aliases
    machine.succeed("zsh -i -c 'which eza'")
    machine.succeed("zsh -i -c 'alias ls | grep eza'")
  '';
}
```

**Tests à implémenter**:
- ✓ Services launchd démarrent
- ✓ Aliases Zsh fonctionnels
- ✓ Vulnix scan s'exécute
- ✓ Rollback test passe
- ✓ Home Manager activation réussit

---

### 3. Monitoring Dashboard (+0.75pt)

**Objectif**: Visibilité metrics système en temps réel

**Stack Grafana + Prometheus**:
```nix
# modules/monitoring.nix
{ config, pkgs, ... }:
{
  services.prometheus = {
    enable = true;
    exporters = {
      node = { enable = true; };  # System metrics
      nginx = { enable = true; }; # Services health
    };
  };

  services.grafana = {
    enable = true;
    settings = {
      server.http_port = 3000;
      analytics.reporting_enabled = false;
    };
  };
}
```

**Dashboards**:
- **System Health**: CPU, RAM, Disk usage
- **Nix Store**: Garbage collection trends, store size
- **Security**: CVE count over time, critical packages
- **Services**: Launchd daemon uptime, error rates
- **Updates**: Flake update frequency, rebuild success rate

**Alerting**:
- CVE count > 50 → Slack/Email
- Disk usage > 90% → Notification
- Service fails > 3x → Alert

---

## Implémentation Recommandée

### Phase 1: CI/CD (1-2h)
1. Créer `.github/workflows/nix-check.yml`
2. Tester sur branch de test
3. Ajouter badge README

### Phase 2: Integration Tests (3-4h)
1. Setup Tart VM macOS
2. Écrire tests basiques
3. Intégrer dans CI

### Phase 3: Monitoring (4-6h)
1. Ajouter Prometheus exporters
2. Setup Grafana + dashboards
3. Configurer alerting

---

## Estimation Totale

- **Temps**: 8-12 heures
- **Complexité**: Moyenne
- **Impact**: Production-ready config

---

## Notes

- CI/CD bloqué par: besoin repo GitHub public/privé avec Actions enabled
- Integration tests: nécessite license Tart (VM macOS native) ou UTM
- Monitoring: peut tourner en local, expose :3000

---

## Métriques Finales (S Tier)

| Aspect | Score | Notes |
|--------|-------|-------|
| Sécurité | 20/20 | SOPS + CVE monitoring + tests |
| Architecture | 20/20 | Modulaire + tested + monitored |
| Maintenabilité | 20/20 | Doc + CI + helpers |
| Tests | 20/20 | Unit + integration + E2E |
| Documentation | 20/20 | Complète + diagrammes |
| **TOTAL** | **100/100** | **S TIER** |

---

**Dernière mise à jour**: 2026-01-13
**Grade actuel**: A++ (98/100)
