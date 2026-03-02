# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule VeriSimClientTest do
  @moduledoc """
  Basic tests for the VeriSimDB Elixir client SDK.

  These tests exercise client construction and validate that the client struct
  is correctly populated. Network-dependent tests (health check, CRUD, etc.)
  would require a running VeriSimDB instance or a mock server.
  """

  use ExUnit.Case, async: true

  describe "VeriSimClient.new/2" do
    test "creates a client with default options" do
      assert {:ok, client} = VeriSimClient.new("http://localhost:8080")
      assert client.base_url == "http://localhost:8080"
      assert client.auth == :none
      assert client.timeout == 30_000
    end

    test "creates a client with API key auth" do
      assert {:ok, client} =
               VeriSimClient.new("https://verisim.example.com", auth: {:api_key, "test-key"})

      assert client.base_url == "https://verisim.example.com"
      assert client.auth == {:api_key, "test-key"}
    end

    test "creates a client with bearer auth" do
      assert {:ok, client} =
               VeriSimClient.new("http://localhost:8080", auth: {:bearer, "my-token"})

      assert client.auth == {:bearer, "my-token"}
    end

    test "creates a client with basic auth" do
      assert {:ok, client} =
               VeriSimClient.new("http://localhost:8080",
                 auth: {:basic, "user", "pass"}
               )

      assert client.auth == {:basic, "user", "pass"}
    end

    test "creates a client with custom timeout" do
      assert {:ok, client} = VeriSimClient.new("http://localhost:8080", timeout: 5_000)
      assert client.timeout == 5_000
    end

    test "strips trailing slash from base URL" do
      assert {:ok, client} = VeriSimClient.new("http://localhost:8080/")
      assert client.base_url == "http://localhost:8080"
    end

    test "rejects invalid URL schemes" do
      assert {:error, _reason} = VeriSimClient.new("ftp://localhost:8080")
    end
  end

  describe "VeriSimClient.Types" do
    test "all_modalities returns eight modalities" do
      modalities = VeriSimClient.Types.all_modalities()
      assert length(modalities) == 8
      assert :graph in modalities
      assert :vector in modalities
      assert :tensor in modalities
      assert :semantic in modalities
      assert :document in modalities
      assert :temporal in modalities
      assert :provenance in modalities
      assert :spatial in modalities
    end
  end
end
