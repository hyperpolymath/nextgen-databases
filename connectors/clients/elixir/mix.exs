# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule VeriSimClient.MixProject do
  @moduledoc """
  Mix project configuration for the VeriSimDB Elixir client SDK.

  Provides hexad entity management, multi-modal search (text, vector, spatial),
  drift detection, provenance chain operations, VQL query execution, and
  federation across distributed VeriSimDB instances.
  """

  use Mix.Project

  def project do
    [
      app: :verisim_client,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "VeriSimDB Client",
      source_url: "https://gitlab.com/hyperpolymath/verisimdb",
      description: "VeriSimDB client SDK for Elixir — octad entity management, drift detection, and federation",
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["PMPL-1.0-or-later"],
      links: %{
        "GitLab" => "https://gitlab.com/hyperpolymath/verisimdb",
        "GitHub" => "https://github.com/hyperpolymath/verisimdb"
      }
    ]
  end
end
