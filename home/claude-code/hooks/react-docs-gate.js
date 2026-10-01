#!/usr/bin/env node
let input = "";
process.stdin.on("data", c => input += c);
process.stdin.on("end", () => {
  const fs = require("fs");
  const os = require("os");
  const path = require("path");
  try {
    const data = JSON.parse(input);
    const filePath = data.tool_input && data.tool_input.file_path;
    if (!filePath || !/\.(tsx|jsx)$/i.test(filePath)) process.exit(0);

    const sid = String(data.session_id || "nosession").replace(/[^A-Za-z0-9_-]/g, "");
    const stamp = path.join(os.tmpdir(), "claude-react-docs-gate-" + sid);
    if (fs.existsSync(stamp)) process.exit(0);
    try { fs.writeFileSync(stamp, ""); } catch {}

    const ctx = [
      "Stack: React 19 + React Router 7 + TypeScript.",
      "Before writing any React or React Router API, signature or version detail, look it up:",
      "`libdocs react \"<question>\"` or `libdocs rr \"<question>\"`.",
      "The ids are pinned because a raw doc search ranks React Router v5 above v7.",
      "Do not write `useFormState` (v18 name) and do not import from",
      "`react-router-dom` (v7 ships `react-router`).",
      "After writing: pnpm typecheck && pnpm lint --max-warnings 0."
    ].join(" ");

    // Only the nested form carrying hookEventName is documented.
    process.stdout.write(JSON.stringify({
      hookSpecificOutput: { hookEventName: "PreToolUse", additionalContext: ctx }
    }));
  } catch (e) {}
  process.exit(0);
});
