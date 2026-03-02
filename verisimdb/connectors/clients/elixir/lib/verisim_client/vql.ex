# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule VeriSimClient.Vql do
  @moduledoc """
  VeriSim Query Language (VQL) execution for VeriSimDB.

  VQL is VeriSimDB's native query language, supporting SQL-like syntax extended
  with multi-modal operations (vector similarity, graph traversal, spatial
  predicates, drift thresholds, etc.). This module provides methods to execute
  VQL statements and retrieve explain / query plans.

  ## Examples

      {:ok, client} = VeriSimClient.new("http://localhost:8080")

      {:ok, result} = VeriSimClient.Vql.execute(client, "SELECT * FROM hexads WHERE drift > 0.5")
      IO.puts("Rows returned: \#{result["row_count"]}")

      {:ok, plan} = VeriSimClient.Vql.explain(client, "SELECT * FROM hexads WHERE drift > 0.5")
  """

  alias VeriSimClient.Types

  @doc """
  Execute a VQL statement against the VeriSimDB instance.

  Supports SELECT, INSERT, UPDATE, DELETE, and VeriSimDB-specific statements
  like `DRIFT CHECK`, `NORMALIZE`, and `FEDERATE`.

  ## Parameters

    * `client` — A `VeriSimClient.t()` connection.
    * `query`  — The VQL statement string.
  """
  @spec execute(VeriSimClient.t(), String.t()) ::
          {:ok, Types.vql_response()} | {:error, term()}
  def execute(%VeriSimClient{} = client, query) when is_binary(query) do
    body = %{query: query}
    VeriSimClient.do_post(client, "/api/v1/vql/execute", body)
  end

  @doc """
  Request an explain / query plan for a VQL statement without executing it.

  Useful for understanding which modalities, indices, and federation peers
  would be involved in a query.

  ## Parameters

    * `client` — A `VeriSimClient.t()` connection.
    * `query`  — The VQL statement string to explain.
  """
  @spec explain(VeriSimClient.t(), String.t()) ::
          {:ok, Types.vql_response()} | {:error, term()}
  def explain(%VeriSimClient{} = client, query) when is_binary(query) do
    body = %{query: query}
    VeriSimClient.do_post(client, "/api/v1/vql/explain", body)
  end
end
