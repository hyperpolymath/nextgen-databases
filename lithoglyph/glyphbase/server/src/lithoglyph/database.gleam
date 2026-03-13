// SPDX-License-Identifier: PMPL-1.0-or-later
// Lith database connection manager

import lithoglyph/client.{type Connection, ReadOnly, ReadWrite}
import lithoglyph/operations.{type Operation, encode_operation}
import gleam/option.{type Option, None, Some}

/// Database state
pub opaque type DatabaseState {
  DatabaseState(conn: Option(Connection), path: String)
}

/// Create a new database state with the given path
pub fn new(path: String) -> DatabaseState {
  DatabaseState(conn: None, path: path)
}

/// Open the database connection
pub fn open(state: DatabaseState) -> #(DatabaseState, client.LithResult(Nil)) {
  case state.conn {
    Some(_) -> #(state, Ok(Nil))
    None -> {
      case client.connect(state.path) {
        Ok(conn) -> #(DatabaseState(..state, conn: Some(conn)), Ok(Nil))
        Error(e) -> #(state, Error(e))
      }
    }
  }
}

/// Close the database connection
pub fn close(state: DatabaseState) -> #(DatabaseState, client.LithResult(Nil)) {
  case state.conn {
    None -> #(state, Ok(Nil))
    Some(conn) -> {
      case client.disconnect(conn) {
        Ok(_) -> #(DatabaseState(..state, conn: None), Ok(Nil))
        Error(e) -> #(state, Error(e))
      }
    }
  }
}

/// Execute an operation on the database
pub fn execute(
  state: DatabaseState,
  op: Operation,
) -> #(DatabaseState, client.LithResult(BitArray)) {
  case state.conn {
    None -> #(state, Error(client.ConnectionError("Database not connected")))
    Some(conn) -> {
      let encoded_op = encode_operation(op)
      // Determine if this is a read-only or read-write operation
      let mode = get_operation_mode(op)
      case client.with_transaction(conn, mode, fn(txn) {
        case client.apply_operation(txn, encoded_op) {
          Ok(#(result, _provenance)) -> Ok(result)
          Error(e) -> Error(e)
        }
      }) {
        Ok(result) -> #(state, Ok(result))
        Error(e) -> #(state, Error(e))
      }
    }
  }
}

/// Get the transaction mode for an operation
fn get_operation_mode(op: Operation) -> client.TransactionMode {
  case op {
    operations.CreateBase(_, _, _) -> ReadWrite
    operations.GetBase(_) -> ReadOnly
    operations.ListBases -> ReadOnly
    operations.UpdateBase(_, _, _) -> ReadWrite
    operations.DeleteBase(_) -> ReadWrite
    operations.CreateTable(_, _, _, _, _) -> ReadWrite
    operations.GetTable(_, _) -> ReadOnly
    operations.ListTables(_) -> ReadOnly
    operations.UpdateTable(_, _, _) -> ReadWrite
    operations.DeleteTable(_, _) -> ReadWrite
    operations.CreateRow(_, _, _, _) -> ReadWrite
    operations.GetRow(_, _, _) -> ReadOnly
    operations.ListRows(_, _, _, _, _) -> ReadOnly
    operations.UpdateRow(_, _, _, _, _) -> ReadWrite
    operations.DeleteRow(_, _, _) -> ReadWrite
    operations.GetCell(_, _, _, _) -> ReadOnly
    operations.UpdateCell(_, _, _, _, _, _) -> ReadWrite
    operations.GetProvenance(_, _, _, _) -> ReadOnly
  }
}

/// Get the current connection (for advanced use cases)
pub fn get_connection(state: DatabaseState) -> Option(Connection) {
  state.conn
}

// ============================================================
// Simplified Interface (for request handling)
// ============================================================

/// Execute a read-only operation on an existing connection
pub fn read(conn: Connection, op: Operation) -> client.LithResult(BitArray) {
  let encoded_op = encode_operation(op)
  client.with_transaction(conn, ReadOnly, fn(txn) {
    case client.apply_operation(txn, encoded_op) {
      Ok(#(result, _)) -> Ok(result)
      Error(e) -> Error(e)
    }
  })
}

/// Execute a read-write operation on an existing connection
pub fn write(conn: Connection, op: Operation) -> client.LithResult(BitArray) {
  let encoded_op = encode_operation(op)
  client.with_transaction(conn, ReadWrite, fn(txn) {
    case client.apply_operation(txn, encoded_op) {
      Ok(#(result, _)) -> Ok(result)
      Error(e) -> Error(e)
    }
  })
}
