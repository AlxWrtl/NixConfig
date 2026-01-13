# ============================================================================
# LAUNCHD DAEMON HELPER FUNCTIONS
# ============================================================================
# Reusable patterns for consistent daemon configuration

{
  name,
  script,
  schedule ? null,
  runAtLoad ? false,
  user ? "root",
}:

{
  serviceConfig = {
    ProgramArguments = [
      "/bin/sh"
      "-c"
      script
    ];
    StartCalendarInterval = schedule;
    StandardOutPath = "/var/log/${name}.log";
    StandardErrorPath = "/var/log/${name}-error.log";
    RunAtLoad = runAtLoad;
    UserName = user;
  };
}
