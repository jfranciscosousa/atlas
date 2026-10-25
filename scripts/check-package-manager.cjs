const userAgent = process.env.npm_config_user_agent ?? "";

if (!userAgent.startsWith("pnpm/")) {
  console.error("Use pnpm install. This repository requires pnpm, not npm, Yarn, or Bun.");
  process.exit(1);
}
