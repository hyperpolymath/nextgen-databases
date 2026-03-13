// SPDX-License-Identifier: PMPL-1.0-or-later
// Lith Studio - Entry Point

import React from "react";
import { createRoot } from "react-dom/client";
// @ts-ignore - ReScript compiled module
import { make as App } from "../lib/bs/src/App.res.js";

const container = document.getElementById("root");
if (container) {
  const root = createRoot(container);
  root.render(React.createElement(App, {}));
}
