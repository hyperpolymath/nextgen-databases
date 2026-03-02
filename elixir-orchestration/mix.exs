# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.MixProject do
  use Mix.Project

  def project do
    [
      app: :verisim,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      releases: [
        verisim: [
          include_executables_for: [:unix],
          applications: [runtime_tools: :permanent]
        ]
      ],

      # Docs
      name: "VeriSim Orchestration",
      source_url: "https://gitlab.com/hyperpolymath/verisimdb",
      docs: [
        main: "VeriSim",
        extras: ["README.md"]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {VeriSim.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # HTTP client for Rust core communication
      {:req, "~> 0.5"},

      # HTTP server for orchestration API (telemetry, status)
      {:bandit, "~> 1.6"},

      # JSON encoding/decoding
      {:jason, "~> 1.4"},

      # Telemetry and metrics
      {:telemetry, "~> 1.2"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},

      # Process registry
      {:horde, "~> 0.9"},

      # Testing
      {:ex_machina, "~> 2.7", only: :test},
      {:mox, "~> 1.0", only: :test},
      {:stream_data, "~> 1.1", only: [:test, :dev]},

      # Optional: native protocol adapters for federation
      # These are only needed when using :wire protocol instead of HTTP
      {:postgrex, "~> 0.19", optional: true},
      {:redix, "~> 1.5", optional: true},
      {:exqlite, "~> 0.27", optional: true},
      {:bolt_sips, "~> 2.0", optional: true},

      # Development
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      test: ["test"],
      "test.watch": ["test.watch"]
    ]
  end
end
