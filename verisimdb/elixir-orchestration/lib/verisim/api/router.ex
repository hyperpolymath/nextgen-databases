# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Api.Router do
  @moduledoc """
  Lightweight HTTP API router for VeriSimDB orchestration endpoints.

  Serves endpoints that are native to the Elixir orchestration layer
  (telemetry, orchestration health, consensus status) rather than proxied
  to the Rust core. Runs on a separate port (default 4080) from the Rust
  core API (default 8080).

  ## Endpoints

  - `GET /health` — Orchestration layer health check
  - `GET /telemetry` — Product telemetry report (opt-in, aggregate-only)
  - `GET /telemetry/modality-heatmap` — Modality usage breakdown
  - `GET /telemetry/query-patterns` — Query pattern distribution
  - `GET /telemetry/drift` — Drift detection report
  - `GET /telemetry/performance` — Query performance summary
  - `GET /telemetry/federation` — Federation health metrics
  - `GET /status` — Orchestration status (consensus, entity count, etc.)

  ## Configuration

  Port is configurable via:
  - `config :verisim, orch_api_port: 4080`
  - Environment variable: `VERISIM_ORCH_PORT`

  ## CORS

  All endpoints return `Access-Control-Allow-Origin: *` to allow PanLL
  and other local tools to query without proxy configuration.
  """

  use Plug.Router

  plug :match
  plug Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Jason
  plug :set_cors_headers
  plug :dispatch

  # ── Health ────────────────────────────────────────────────────────────

  get "/health" do
    response = %{
      status: "ok",
      layer: "orchestration",
      node: Node.self() |> to_string(),
      uptime_seconds: uptime_seconds(),
      telemetry_enabled: VeriSim.Telemetry.Collector.enabled?()
    }

    json_response(conn, 200, response)
  end

  # ── Full Telemetry Report ─────────────────────────────────────────────

  get "/telemetry" do
    if VeriSim.Telemetry.Collector.enabled?() do
      json_string = VeriSim.Telemetry.Reporter.report_json()
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, json_string)
    else
      json_response(conn, 200, %{
        telemetry_enabled: false,
        message: "Telemetry collection is disabled. Enable with VERISIM_TELEMETRY=true.",
        privacy_notice: "When enabled, only aggregate counters are collected. No PII, no query content."
      })
    end
  end

  # ── Individual Telemetry Sections ─────────────────────────────────────

  get "/telemetry/modality-heatmap" do
    json_response(conn, 200, VeriSim.Telemetry.Reporter.modality_heatmap())
  end

  get "/telemetry/query-patterns" do
    json_response(conn, 200, VeriSim.Telemetry.Reporter.query_patterns())
  end

  get "/telemetry/drift" do
    json_response(conn, 200, VeriSim.Telemetry.Reporter.drift_report())
  end

  get "/telemetry/performance" do
    json_response(conn, 200, VeriSim.Telemetry.Reporter.performance_summary())
  end

  get "/telemetry/federation" do
    json_response(conn, 200, VeriSim.Telemetry.Reporter.federation_health())
  end

  get "/telemetry/proof-types" do
    json_response(conn, 200, VeriSim.Telemetry.Reporter.proof_type_usage())
  end

  get "/telemetry/entities" do
    json_response(conn, 200, VeriSim.Telemetry.Reporter.entity_summary())
  end

  get "/telemetry/health" do
    json_response(conn, 200, VeriSim.Telemetry.Reporter.health_report())
  end

  get "/telemetry/error-budget" do
    json_response(conn, 200, VeriSim.Telemetry.Reporter.error_budget_report())
  end

  # ── Orchestration Status ──────────────────────────────────────────────

  get "/status" do
    node_id = Application.get_env(:verisim, :kraft_node_id, "local")

    consensus_status =
      try do
        VeriSim.Consensus.KRaftNode.diagnostics(node_id)
      catch
        :exit, _ -> %{state: "unavailable"}
        _kind, _reason -> %{state: "unavailable"}
      end

    federation_peers =
      try do
        VeriSim.Federation.Resolver.list_peers()
      catch
        :exit, _ -> []
        _kind, _reason -> []
      end

    response = %{
      orchestration: "running",
      consensus: consensus_status,
      federation_adapters: length(federation_peers),
      telemetry_enabled: VeriSim.Telemetry.Collector.enabled?()
    }

    json_response(conn, 200, response)
  end

  # ── Catch-all ─────────────────────────────────────────────────────────

  match _ do
    json_response(conn, 404, %{error: "not_found", message: "Unknown endpoint"})
  end

  # ── Private helpers ───────────────────────────────────────────────────

  defp json_response(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(body))
  end

  defp set_cors_headers(conn, _opts) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET, OPTIONS")
    |> put_resp_header("access-control-allow-headers", "content-type")
  end

  defp uptime_seconds do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    div(uptime_ms, 1000)
  end
end
