// SPDX-License-Identifier: PMPL-1.0-or-later
// Build script — bundles ReScript output for production PWA deployment.
import * as esbuild from "esbuild";

await esbuild.build({
  entryPoints: ["src/App.res.mjs"],
  bundle: true,
  minify: true,
  outfile: "public/app.js",
  format: "esm",
  target: "es2022",
  sourcemap: true,
});

console.log("Build complete: public/app.js");
