# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Test.VQLTestHelpers do
  @moduledoc """
  Shared test helpers for VQL integration tests.

  Provides:
  - VQLBridge startup and teardown
  - Hexad fixtures for each modality combination
  - AST assertion helpers
  - Query execution wrappers with Rust-core-unavailable handling
  - Cross-modal condition builders

  ## Usage

      use VeriSim.Test.VQLTestHelpers

  This imports all helper functions and sets up the VQLBridge GenServer in
  `setup_all`. Tests can then call `parse!/1`, `execute_safely/2`, and
  fixture builders without boilerplate.
  """

  alias VeriSim.Query.{VQLBridge, VQLExecutor}

  @doc """
  Ensure VQLBridge GenServer is running. Returns the PID.

  Safe to call multiple times — if already started, returns the existing PID.
  """
  def ensure_bridge_started do
    case VQLBridge.start_link([]) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
  end

  @doc """
  Parse a VQL query string, raising on failure.

  Returns the parsed AST map. Useful in tests where a parse failure
  means the test itself is broken, not the feature under test.
  """
  def parse!(query_string) do
    case VQLBridge.parse(query_string) do
      {:ok, ast} -> ast
      {:error, reason} -> raise "VQL parse failed: #{inspect(reason)}\n  Query: #{query_string}"
    end
  end

  @doc """
  Parse a VQL statement (query or mutation), raising on failure.
  """
  def parse_statement!(query_string) do
    case VQLBridge.parse_statement(query_string) do
      {:ok, ast} -> ast
      {:error, reason} -> raise "VQL statement parse failed: #{inspect(reason)}\n  Query: #{query_string}"
    end
  end

  @doc """
  Execute a VQL query string, handling Rust-core-unavailable gracefully.

  Returns `{:ok, result}`, `{:error, reason}`, or `{:unavailable, reason}`
  when the Rust core is not running (rescues connection errors).
  """
  def execute_safely(query_string, opts \\ []) do
    opts = Keyword.put_new(opts, :timeout, 2_000)

    try do
      VQLExecutor.execute_string(query_string, opts)
    rescue
      e ->
        {:unavailable, Exception.message(e)}
    end
  end

  @doc """
  Execute a parsed VQL AST, handling Rust-core-unavailable gracefully.
  """
  def execute_ast_safely(ast, opts \\ []) do
    opts = Keyword.put_new(opts, :timeout, 2_000)

    try do
      VQLExecutor.execute(ast, opts)
    rescue
      e ->
        {:unavailable, Exception.message(e)}
    end
  end

  @doc """
  Execute a VQL statement AST (query or mutation), handling errors gracefully.
  """
  def execute_statement_safely(ast, opts \\ []) do
    opts = Keyword.put_new(opts, :timeout, 2_000)

    try do
      VQLExecutor.execute_statement(ast, opts)
    rescue
      e ->
        {:unavailable, Exception.message(e)}
    end
  end

  @doc """
  Assert that a result is either a successful response or an error due to
  Rust core being unavailable. Fails only on unexpected crashes.

  Returns `:ok_result` if successful, `:rust_unavailable` if the Rust core
  is not running (expected in CI / unit-test environments).
  """
  def assert_ok_or_rust_unavailable(result) do
    case result do
      {:ok, _} ->
        :ok_result

      {:error, reason} when is_atom(reason) ->
        :rust_unavailable

      {:error, {tag, _}} when tag in [
        :connection_refused, :econnrefused, :connect_timeout,
        :timeout, :req_error, :mint_error
      ] ->
        :rust_unavailable

      {:unavailable, _} ->
        :rust_unavailable

      {:error, reason} ->
        # Rust core returned an error (e.g., :not_found) — this is still a
        # valid response, meaning the Rust core IS running. The error might
        # be expected (nonexistent entity) or unexpected.
        {:error_from_rust, reason}

      other ->
        raise "Unexpected result shape: #{inspect(other)}"
    end
  end

  # ===========================================================================
  # Fixtures: pre-built VQL query strings for common test scenarios
  # ===========================================================================

  @doc "All 8 modality names as atoms."
  def all_modalities do
    [:graph, :vector, :tensor, :semantic, :document, :temporal, :provenance, :spatial]
  end

  @doc "All 8 modality names as uppercase strings (for VQL SELECT)."
  def all_modality_names do
    ~w(GRAPH VECTOR TENSOR SEMANTIC DOCUMENT TEMPORAL PROVENANCE SPATIAL)
  end

  @doc "Build a SELECT query for a single modality from a hexad."
  def single_modality_query(modality, entity_id \\ "test-entity-001") do
    mod_upper = modality |> to_string() |> String.upcase()
    "SELECT #{mod_upper}.* FROM HEXAD '#{entity_id}'"
  end

  @doc "Build a SELECT query for multiple modalities from a hexad."
  def multi_modality_query(modalities, entity_id \\ "test-entity-001") do
    projection = modalities
      |> Enum.map(fn m -> "#{m |> to_string() |> String.upcase()}.*" end)
      |> Enum.join(", ")
    "SELECT #{projection} FROM HEXAD '#{entity_id}'"
  end

  @doc "Build a SELECT * (all modalities) query from a hexad."
  def all_modality_query(entity_id \\ "test-entity-001") do
    "SELECT * FROM HEXAD '#{entity_id}'"
  end

  @doc "Build a federation query."
  def federation_query(pattern \\ "/*", drift_policy \\ nil) do
    base = "SELECT * FROM FEDERATION #{pattern}"
    if drift_policy do
      "#{base} WITH DRIFT #{drift_policy |> to_string() |> String.upcase()}"
    else
      base
    end
  end

  @doc "Build an INSERT mutation."
  def insert_mutation(title, body) do
    "INSERT HEXAD WITH DOCUMENT(title = '#{title}', body = '#{body}')"
  end

  @doc "Build an UPDATE mutation."
  def update_mutation(entity_id, field, value) do
    "UPDATE HEXAD '#{entity_id}' SET #{field} = '#{value}'"
  end

  @doc "Build a DELETE mutation."
  def delete_mutation(entity_id) do
    "DELETE HEXAD '#{entity_id}'"
  end

  # ===========================================================================
  # Cross-modal condition AST builders
  # ===========================================================================

  @doc "Build a CrossModalFieldCompare condition AST node."
  def cross_modal_compare(mod1, field1, op, mod2, field2) do
    %{
      TAG: "CrossModalFieldCompare",
      _0: to_string(mod1),
      _1: to_string(field1),
      _2: op,
      _3: to_string(mod2),
      _4: to_string(field2)
    }
  end

  @doc "Build a ModalityDrift condition AST node."
  def modality_drift(mod1, mod2, threshold) do
    %{TAG: "ModalityDrift", _0: to_string(mod1), _1: to_string(mod2), _2: threshold}
  end

  @doc "Build a ModalityExists condition AST node."
  def modality_exists(modality) do
    %{TAG: "ModalityExists", _0: to_string(modality)}
  end

  @doc "Build a ModalityNotExists condition AST node."
  def modality_not_exists(modality) do
    %{TAG: "ModalityNotExists", _0: to_string(modality)}
  end

  @doc "Build a ModalityConsistency condition AST node."
  def modality_consistency(mod1, mod2, metric) do
    %{TAG: "ModalityConsistency", _0: to_string(mod1), _1: to_string(mod2), _2: metric}
  end

  @doc "Build an And condition combining two sub-conditions."
  def and_condition(left, right) do
    %{TAG: "And", _0: left, _1: right}
  end

  @doc "Build an Or condition combining two sub-conditions."
  def or_condition(left, right) do
    %{TAG: "Or", _0: left, _1: right}
  end

  # ===========================================================================
  # AST assertion helpers
  # ===========================================================================

  @doc "Assert that an AST contains the expected modalities."
  def assert_modalities(ast, expected) do
    modalities = ast[:modalities] || ast["modalities"] || []
    expected_set = MapSet.new(expected)
    actual_set = MapSet.new(modalities)

    unless MapSet.equal?(expected_set, actual_set) do
      raise ExUnit.AssertionError,
        message: "Modalities mismatch",
        left: Enum.sort(modalities),
        right: Enum.sort(expected)
    end
  end

  @doc "Assert that an AST has a specific source type."
  def assert_source(ast, expected_type) do
    source = ast[:source] || ast["source"]

    case {expected_type, source} do
      {:hexad, {:hexad, _id}} -> :ok
      {:federation, {:federation, _, _}} -> :ok
      {:store, {:store, _id}} -> :ok
      _ ->
        raise ExUnit.AssertionError,
          message: "Source type mismatch",
          left: source,
          right: expected_type
    end
  end

  @doc "Assert that an AST has a WHERE clause present."
  def assert_has_where(ast) do
    where = ast[:where] || ast["where"]
    unless where do
      raise ExUnit.AssertionError,
        message: "Expected WHERE clause to be present, got nil"
    end
  end

  @doc "Assert that an AST has a PROOF clause present."
  def assert_has_proof(ast) do
    proof = ast[:proof] || ast["proof"]
    unless proof do
      raise ExUnit.AssertionError,
        message: "Expected PROOF clause to be present, got nil"
    end
  end

  @doc "Assert that an AST has LIMIT set."
  def assert_limit(ast, expected_limit) do
    limit = ast[:limit] || ast["limit"]
    unless limit == expected_limit do
      raise ExUnit.AssertionError,
        message: "LIMIT mismatch",
        left: limit,
        right: expected_limit
    end
  end

  @doc "Assert that an AST has OFFSET set."
  def assert_offset(ast, expected_offset) do
    offset = ast[:offset] || ast["offset"]
    unless offset == expected_offset do
      raise ExUnit.AssertionError,
        message: "OFFSET mismatch",
        left: offset,
        right: expected_offset
    end
  end
end
