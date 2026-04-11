# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule VeriSimClient.Vcl do
  @moduledoc """
  VeriSim Consonance Language (VCL) execution for VeriSimDB.

  VCL is VeriSimDB's native query language, supporting SQL-like syntax extended
  with multi-modal operations (vector similarity, graph traversal, spatial
  predicates, drift thresholds, etc.). This module provides methods to execute
  VCL statements and retrieve explain / query plans.

  ## Examples

      {:ok, client} = VeriSimClient.new("http://localhost:8080")

      {:ok, result} = VeriSimClient.Vcl.execute(client, "SELECT * FROM octads WHERE drift > 0.5")
      IO.puts("Rows returned: \#{result["row_count"]}")

      {:ok, plan} = VeriSimClient.Vcl.explain(client, "SELECT * FROM octads WHERE drift > 0.5")
  """

  alias VeriSimClient.Types

  @doc """
  Execute a VCL statement against the VeriSimDB instance.

  Supports SELECT, INSERT, UPDATE, DELETE, and VeriSimDB-specific statements
  like `DRIFT CHECK`, `NORMALIZE`, and `FEDERATE`.

  ## Parameters

    * `client` — A `VeriSimClient.t()` connection.
    * `query`  — The VCL statement string.
  """
  @spec execute(VeriSimClient.t(), String.t()) ::
          {:ok, Types.vcl_response()} | {:error, term()}
  def execute(%VeriSimClient{} = client, query) when is_binary(query) do
    body = %{query: query}
    VeriSimClient.do_post(client, "/api/v1/vcl/execute", body)
  end

  @doc """
  Request an explain / query plan for a VCL statement without executing it.

  Useful for understanding which modalities, indices, and federation peers
  would be involved in a query.

  ## Parameters

    * `client` — A `VeriSimClient.t()` connection.
    * `query`  — The VCL statement string to explain.
  """
  @spec explain(VeriSimClient.t(), String.t()) ::
          {:ok, Types.vcl_response()} | {:error, term()}
  def explain(%VeriSimClient{} = client, query) when is_binary(query) do
    body = %{query: query}
    VeriSimClient.do_post(client, "/api/v1/vcl/explain", body)
  end
end
