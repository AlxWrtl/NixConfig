# ============================================================================
# SYSTEM CONSTANTS & MAGIC NUMBERS DOCUMENTATION
# ============================================================================
# Centralized constants with rationale for all system values

{
  # === Keyboard Settings ===
  # macOS uses 15ms intervals for key repeat timing
  keyRepeat = 8; # 8 * 15ms = 120ms between repeats (fastest comfortable typing)
  initialKeyRepeat = 10; # 10 * 15ms = 150ms before repeat starts (standard delay)

  # === Dock Configuration ===
  dockTileSize = 25; # 25px icons: optimal density for 27" display at native resolution
  dockLargeSize = 48; # 48px magnified: 1.92x zoom (comfortable hover target)

  # === Performance Timings ===
  windowResizeTime = 0.001; # Instant window resize (disable animation)
  exposeAnimationDuration = 0.1; # 100ms Mission Control (balance speed/smoothness)

  # === Storage Management ===
  gcRetentionDays = 60; # 60 days: balance disk space vs rollback safety
  gcMaxFreed = "10G"; # 10GB: prevent aggressive cleanup during single GC run

  # === Cache & Cleanup ===
  logRetentionDays = 30; # 30 days: compliance with standard log rotation policies
  tempFileRetentionDays = 7; # 7 days: safe for macOS temp file recreation
  cacheFileRetentionDays = 7; # 7 days: preserve critical app data while cleaning space

  # === Network Tuning ===
  tcpSlowStartFlightSize = 16; # 16 packets: aggressive for high-speed networks (optimize for good connections)
  maxOpenFiles = 65536; # 64K: support high-concurrency development servers
  maxFilesPerProc = 32768; # 32K per process: prevent single app exhaustion

  # === Power Management ===
  displaySleepMinutes = 25; # 25min: balance energy vs interruption for active work
  systemSleepMinutes = 45; # 45min: longer than display to prevent premature sleep
}
