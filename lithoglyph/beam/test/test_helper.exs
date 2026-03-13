# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <jonathan.jewell@open.ac.uk>
#
# ExUnit test helper for Lithoglyph BEAM integration tests.
# Starts ExUnit and configures the test environment for Lith NIF testing.
#
# The NIF shared library (lith_nif.so) must be compiled and placed in
# the priv/ directory before running tests. See beam/BUILD-STATUS.md
# for build instructions.

ExUnit.start(
  capture_log: true,
  exclude: [:skip, :wip],
  formatters: [ExUnit.CLIFormatter]
)
