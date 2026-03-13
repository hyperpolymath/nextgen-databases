// SPDX-License-Identifier: PMPL-1.0-or-later
// Lithoglyph Client Integration Test - M10 PoC

import lithoglyph/client
import gleam/io
import gleam/string
import gleeunit

pub fn main() {
  gleeunit.main()
}

pub fn version_test() {
  io.println("\n=== Lithoglyph Client NIF Test ===\n")

  // Test 1: Version
  io.println("Test 1: Getting version...")
  let version = client.version()
  io.println("  ✓ Version: " <> string.inspect(version))

  // Verify version is (1, 0, 0)
  case version {
    #(1, 0, 0) -> io.println("  ✓ Version matches expected v1.0.0\n")
    _ -> panic as "Unexpected version"
  }
}

pub fn connection_test() {
  // Test 2: Open connection
  io.println("Test 2: Opening database connection...")
  case client.connect("/tmp/lithoglyph_test") {
    Ok(conn) -> {
      io.println("  ✓ Connection opened\n")

      // Test 3: Get schema
      io.println("Test 3: Getting schema...")
      case client.get_schema(conn) {
        Ok(schema) -> {
          io.println("  ✓ Schema retrieved: " <> string.inspect(schema))
          io.println("  (CBOR empty map: <<160>>)\n")
        }
        Error(e) -> {
          io.println("  ✗ Schema failed: " <> string.inspect(e))
          panic as "Schema retrieval failed"
        }
      }

      // Test 4: Get journal
      io.println("Test 4: Getting journal...")
      case client.get_journal(conn, 0) {
        Ok(journal) -> {
          io.println("  ✓ Journal retrieved: " <> string.inspect(journal))
          io.println("  (CBOR empty array: <<128>>)\n")
        }
        Error(e) -> {
          io.println("  ✗ Journal failed: " <> string.inspect(e))
          panic as "Journal retrieval failed"
        }
      }

      // Test 5: Close connection
      io.println("Test 5: Closing database connection...")
      case client.disconnect(conn) {
        Ok(_) -> io.println("  ✓ Connection closed\n")
        Error(e) -> {
          io.println("  ✗ Close failed: " <> string.inspect(e))
          panic as "Connection close failed"
        }
      }
    }
    Error(e) -> {
      io.println("  ✗ Connection failed: " <> string.inspect(e))
      panic as "Connection open failed"
    }
  }
}

pub fn transaction_test() {
  io.println("Test 6: Transaction flow...")

  case client.connect("/tmp/lithoglyph_test") {
    Ok(conn) -> {
      // Test 6a: Begin transaction
      io.println("  6a: Beginning transaction...")
      case client.begin_transaction(conn, client.ReadWrite) {
        Ok(txn) -> {
          io.println("    ✓ Transaction started\n")

          // Test 6b: Apply operation (CBOR map {1: 2})
          io.println("  6b: Applying operation...")
          let cbor_map = <<0xa1, 0x01, 0x02>>
          case client.apply_operation(txn, cbor_map) {
            Ok(#(block_id, _provenance)) -> {
              io.println("    ✓ Operation applied")
              io.println("    Block ID: " <> string.inspect(block_id))
              io.println("    (Expected: <<0,0,0,0,0,0,0,1>>)\n")
            }
            Error(e) -> {
              io.println("    ✗ Apply failed: " <> string.inspect(e))
              let _ = client.abort(txn)
              panic as "Apply operation failed"
            }
          }

          // Test 6c: Commit transaction
          io.println("  6c: Committing transaction...")
          case client.commit(txn) {
            Ok(_) -> io.println("    ✓ Transaction committed\n")
            Error(e) -> {
              io.println("    ✗ Commit failed: " <> string.inspect(e))
              panic as "Transaction commit failed"
            }
          }
        }
        Error(e) -> {
          io.println("    ✗ Begin transaction failed: " <> string.inspect(e))
          panic as "Transaction begin failed"
        }
      }

      // Clean up
      let _ = client.disconnect(conn)
    }
    Error(e) -> {
      io.println("  ✗ Connection failed: " <> string.inspect(e))
      panic as "Connection failed"
    }
  }
}

pub fn with_transaction_test() {
  io.println("Test 7: High-level with_transaction...")

  case client.connect("/tmp/lithoglyph_test") {
    Ok(conn) -> {
      // Use the high-level with_transaction helper
      case
        client.with_transaction(conn, client.ReadWrite, fn(txn) {
          let cbor_map = <<0xa1, 0x02, 0x03>>
          client.apply_operation(txn, cbor_map)
        })
      {
        Ok(_) -> io.println("  ✓ with_transaction completed successfully\n")
        Error(e) -> {
          io.println("  ✗ with_transaction failed: " <> string.inspect(e))
          panic as "with_transaction failed"
        }
      }

      // Clean up
      let _ = client.disconnect(conn)
      io.println("=== All tests passed! ===\n")
    }
    Error(e) -> {
      io.println("  ✗ Connection failed: " <> string.inspect(e))
      panic as "Connection failed"
    }
  }
}
