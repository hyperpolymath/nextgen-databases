// SPDX-License-Identifier: MPL-2.0
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
