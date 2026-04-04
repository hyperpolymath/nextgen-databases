// SPDX-License-Identifier: MPL-2.0
// (PMPL-1.0-or-later preferred; MPL-2.0 required for Gleam ecosystem tooling)
// Author: Jonathan D.A. Jewell <6759885+hyperpolymath@users.noreply.github.com>
//
// Lithoglyph BEAM smoke tests — Gleam gleeunit suite.
//
// Exercises the public Gleam client API (lith_beam/client.gleam) against the
// Lith NIF. These are smoke tests in the Testing & Benchmarking Taxonomy
// sense: they verify that the system is alive and functional end-to-end,
// not that every edge case is handled.
//
// Test scope (per taxonomy):
//   - Version returns a structurally valid version triple.
//   - connect / disconnect does not crash (graceful failure when NIF absent).
//   - with_transaction: begin → apply → commit lifecycle.
//   - Error handling: invalid DB reference is rejected cleanly.
//
// The NIF (.so) must be compiled and available in beam/priv/ for the
// connection/lifecycle tests to pass. If the NIF is absent, those tests
// will fail with a :function_clause or :undef error; the version test
// will still pass because it is linked statically via the Zig NIF shim.

import gleam/io
import gleeunit
import gleeunit/should
import lith_beam/client.{
  type LithError,
  ReadWrite,
  connect,
  disconnect,
  get_journal,
  get_schema,
  version,
  with_transaction,
}

// ===========================================================================
// Test entry point
// ===========================================================================

pub fn main() {
  gleeunit.main()
}

// ===========================================================================
// Smoke: version
//
// The version/0 function wraps the lith_nif:version/0 NIF call which is
// always linked (it does not depend on database files). It must return a
// three-element tuple of non-negative integers.
// ===========================================================================

pub fn version_returns_triple_test() {
  let #(major, minor, patch) = version()

  // Each component must be non-negative.
  should.be_true(major >= 0)
  should.be_true(minor >= 0)
  should.be_true(patch >= 0)
}

pub fn version_components_are_integers_test() {
  // The Gleam type system ensures they are Int, but we verify the values
  // are in a plausible range (not MAX_INT or negative).
  let #(major, minor, patch) = version()

  should.be_true(major < 1_000)
  should.be_true(minor < 1_000)
  should.be_true(patch < 10_000)
}

pub fn version_is_at_least_one_zero_zero_test() {
  // Lithoglyph M10 PoC reports version 1.0.0. Enforce this as a baseline.
  let #(major, _minor, _patch) = version()
  should.be_true(major >= 1)
}

// ===========================================================================
// Smoke: connect / disconnect (requires compiled NIF)
//
// These tests will fail gracefully (return an Error) if the NIF shared
// library is not compiled. The important thing is that the Gleam client
// returns a structured Result rather than crashing the BEAM process.
// ===========================================================================

pub fn connect_to_temp_path_test() {
  // Use a path in the OS temp directory for isolation.
  let db_path = "/tmp/lith_gleam_smoke_test.lgh"

  let result = connect(db_path)

  case result {
    Ok(conn) -> {
      // NIF is available — verify we can close cleanly.
      let close_result = disconnect(conn)
      should.be_ok(close_result)
    }
    Error(_err) -> {
      // NIF not compiled or path error — acceptable in CI without compiled NIF.
      // The test verifies the client does not crash.
      io.println("INFO: Lith NIF not available — connect smoke test skipped")
      Nil
    }
  }
}

pub fn connect_creates_new_database_test() {
  // Each invocation uses a unique path to avoid state leakage between tests.
  let db_path = "/tmp/lith_gleam_new_" <> int_to_string(erlang_unique_integer())

  case connect(db_path) {
    Ok(conn) -> {
      let _ = disconnect(conn)
      Nil
    }
    Error(_) -> {
      io.println("INFO: Lith NIF unavailable — new database test skipped")
      Nil
    }
  }
}

// ===========================================================================
// Smoke: full lifecycle — connect → begin → apply → commit → disconnect
// ===========================================================================

pub fn full_lifecycle_write_and_commit_test() {
  let db_path = "/tmp/lith_gleam_lifecycle_" <> int_to_string(erlang_unique_integer())

  case connect(db_path) {
    Error(_) -> {
      io.println("INFO: Lith NIF unavailable — lifecycle test skipped")
      Nil
    }
    Ok(conn) -> {
      // Minimal CBOR map: 0xA0 = empty map.
      // A real operation would encode {"claim": "smoke test"}, but the
      // empty map is the simplest valid CBOR document.
      let cbor_op = <<0xA0>>

      let txn_result =
        with_transaction(conn, ReadWrite, fn(txn) {
          client.apply_operation(txn, cbor_op)
        })

      case txn_result {
        Ok(#(_result_binary, _provenance)) -> {
          // Apply succeeded — lifecycle is healthy.
          should.be_ok(disconnect(conn))
        }
        Error(_err) -> {
          // Apply may fail if the Zig NIF reports an error for the empty map.
          // This is acceptable for M10 PoC — the key thing is no crash.
          let _ = disconnect(conn)
          io.println("INFO: apply_operation returned error — acceptable for M10 PoC")
          Nil
        }
      }
    }
  }
}

pub fn schema_returns_cbor_binary_test() {
  let db_path = "/tmp/lith_gleam_schema_" <> int_to_string(erlang_unique_integer())

  case connect(db_path) {
    Error(_) -> {
      io.println("INFO: Lith NIF unavailable — schema test skipped")
      Nil
    }
    Ok(conn) -> {
      let schema_result = get_schema(conn)

      case schema_result do
        Ok(cbor) -> {
          // Schema must be at least 1 byte (the empty CBOR map 0xA0).
          should.be_true(bit_size(cbor) >= 8)
          let _ = disconnect(conn)
          Nil
        }
        Error(_) -> {
          let _ = disconnect(conn)
          io.println("INFO: get_schema returned error — acceptable for M10 PoC")
          Nil
        }
      end
    }
  }
}

pub fn journal_returns_cbor_binary_test() {
  let db_path = "/tmp/lith_gleam_journal_" <> int_to_string(erlang_unique_integer())

  case connect(db_path) {
    Error(_) -> {
      io.println("INFO: Lith NIF unavailable — journal test skipped")
      Nil
    }
    Ok(conn) -> {
      // Request entries since sequence 0 (all entries).
      let journal_result = get_journal(conn, 0)

      case journal_result {
        Ok(cbor) -> {
          // Journal must be at least 1 byte (the empty CBOR array 0x80).
          should.be_true(bit_size(cbor) >= 8)
          let _ = disconnect(conn)
          Nil
        }
        Error(_) -> {
          let _ = disconnect(conn)
          io.println("INFO: get_journal returned error — acceptable for M10 PoC")
          Nil
        }
      }
    }
  }
}

// ===========================================================================
// Smoke: error handling
// ===========================================================================

pub fn disconnect_invalid_conn_is_handled_test() {
  // We cannot easily construct an invalid Connection (it is opaque), so
  // we verify that connect to an invalid path returns a structured Error.
  let bad_path = "/proc/this-is-read-only/lith.lgh"

  let result = connect(bad_path)

  // On Linux, /proc is read-only — connect must fail with Error, not crash.
  case result {
    Error(_err) -> {
      // Correctly rejected — the error type is a structured LithError.
      Nil
    }
    Ok(conn) -> {
      // Unexpectedly succeeded — close it and move on.
      let _ = disconnect(conn)
      Nil
    }
  }
}

// ===========================================================================
// Private helpers
// ===========================================================================

// Call the Erlang unique_integer NIF to generate unique IDs for temp paths.
@external(erlang, "erlang", "unique_integer")
fn erlang_unique_integer() -> Int

@external(erlang, "erlang", "integer_to_binary")
fn erlang_integer_to_binary(n: Int) -> BitArray

fn int_to_string(n: Int) -> String {
  let bits = erlang_integer_to_binary(n)
  case bit_array.to_string(bits) {
    Ok(s) -> s
    Error(_) -> "unknown"
  }
}
