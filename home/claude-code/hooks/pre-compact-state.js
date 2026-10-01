#!/usr/bin/env node
const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");
const stateFile = path.join(process.env.HOME, ".claude/compact-state.json");
try {
  const state = { ts: new Date().toISOString() };
  // Capture modified files
  try {
    state.modifiedFiles = execSync("git diff --name-only 2>/dev/null || true", { encoding: "utf8" }).trim().split("\n").filter(Boolean);
    state.stagedFiles = execSync("git diff --cached --name-only 2>/dev/null || true", { encoding: "utf8" }).trim().split("\n").filter(Boolean);
    state.branch = execSync("git branch --show-current 2>/dev/null || true", { encoding: "utf8" }).trim();
  } catch { state.modifiedFiles = []; state.stagedFiles = []; state.branch = ""; }
  // Capture active plan/context if exists
  try {
    const planDir = ".claude/output";
    if (fs.existsSync(planDir)) {
      const plans = fs.readdirSync(planDir).filter(f => f.endsWith(".md")).slice(-3);
      state.activePlans = plans;
    }
  } catch {}
  // Capture circuit breaker state
  const cbFile = path.join(process.env.HOME, ".claude/circuit-breaker-state.json");
  try { state.circuitBreaker = JSON.parse(fs.readFileSync(cbFile, "utf8")); } catch {}
  fs.writeFileSync(stateFile, JSON.stringify(state, null, 2));
} catch {}
process.exit(0);
