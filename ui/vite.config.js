// SPDX-License-Identifier: PMPL-1.0-or-later

import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  resolve: {
    // Follow symlinks to resolve Deno's node_modules structure
    preserveSymlinks: false,
  },
  optimizeDeps: {
    // Pre-bundle core dependencies, but exclude @rescript packages
    // which use subpath exports only
    include: [
      "react",
      "react-dom",
      "jotai",
    ],
    exclude: ["@rescript/runtime", "@rescript/core"],
  },
  server: {
    port: 5173,
  },
});
