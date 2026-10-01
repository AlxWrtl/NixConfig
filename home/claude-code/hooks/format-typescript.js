#!/usr/bin/env node
// prettier runs as an argv array through spawnSync: no shell, so a
// file_path holding $(...) or backticks stays a file name (run 57: the
// old shell-string call ran a $(touch X) path from a Write). A leading dash
// is skipped so a path cannot be read as a prettier option, and so is
// anything but a regular file: prettier reads a missing path as a GLOB
// and formats whatever it matches. ENOENT, the timeout or a non-zero exit
// are ignored: this hook formats, it gates nothing.
let input = "";
process.stdin.on("data", c => input += c);
process.stdin.on("end", () => {
  const fs = require("fs");
  const { spawnSync } = require("child_process");
  const exts = [".ts", ".tsx", ".js", ".jsx", ".css", ".json"];
  try {
    const data = JSON.parse(input);
    const file = (data.tool_input && data.tool_input.file_path) || "";
    if (typeof file === "string" && file && file[0] !== "-" && exts.some(ext => file.endsWith(ext)) && fs.lstatSync(file).isFile()) {
      spawnSync("prettier", ["--write", file], { stdio: "ignore", timeout: 8000, killSignal: "SIGKILL" });
    }
  } catch (e) { process.exit(0); }
  process.exit(0);
});
