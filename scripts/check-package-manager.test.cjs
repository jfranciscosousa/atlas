const assert = require("node:assert/strict");
const { spawnSync } = require("node:child_process");
const { join } = require("node:path");
const { test } = require("node:test");

for (const [userAgent, allowed] of [
  ["pnpm/12.14.0 npm/? node/v26.12.1 linux x64", true],
  ["npm/11.0.0 node/v26.12.1 linux x64", false],
  ["yarn/1.22.22 npm/? node/v26.12.1 linux x64", false],
  ["bun/1.3.0", false],
  ["", false],
]) {
  test(`package manager ${userAgent || "(missing)"} is ${allowed ? "allowed" : "rejected"}`, () => {
    const result = spawnSync(process.execPath, [join(__dirname, "check-package-manager.cjs")], {
      env: { ...process.env, npm_config_user_agent: userAgent },
      encoding: "utf8",
    });
    assert.ifError(result.error);
    assert.equal(result.status, allowed ? 0 : 1);
    if (!allowed) assert.match(result.stderr, /Use pnpm install/);
  });
}
