import { defineConfig } from "vite";
import { fileURLToPath } from "node:url";
import react from "@vitejs/plugin-react";
import { tanstackStart } from "@tanstack/react-start/plugin/vite";
import tailwindcss from "@tailwindcss/vite";

const api = {
  target: process.env.API_URL ?? "http://127.0.0.1:4000",
  changeOrigin: false,
};

export default defineConfig({
  resolve: { alias: { "@": fileURLToPath(new URL("./src", import.meta.url)) } },
  plugins: [
    tanstackStart({
      spa: { enabled: true, prerender: { outputPath: "/index" } },
    }),
    react(),
    tailwindcss(),
  ],
  server: {
    host: "127.0.0.1",
    port: 3000,
    strictPort: true,
    proxy: {
      "/api": api,
      "/auth": api,
      "/rpc": api,
      "/socket": { ...api, ws: true },
    },
  },
});
