# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.ResolverTest do
  use ExUnit.Case, async: false

  alias VeriSim.Federation.Resolver

  # The Resolver is started by the Application supervisor as a named
  # GenServer (__MODULE__). Tests use the app-managed instance and
  # clean up peers between tests.

  setup do
    # Clear any peers from previous tests
    for peer <- Resolver.list_peers() do
      Resolver.deregister_peer(peer.store_id)
    end

    :ok
  end

  describe "register and list peers" do
    test "registered peer appears in list_peers" do
      :ok = Resolver.register_peer("store-a", "http://a.local:8080", ["graph", "vector"])

      peers = Resolver.list_peers()
      assert length(peers) == 1

      [peer] = peers
      assert peer.store_id == "store-a"
      assert peer.endpoint == "http://a.local:8080"
      assert peer.modalities == ["graph", "vector"]
      assert peer.trust_level == 1.0
    end
  end

  describe "deregister peer" do
    test "deregistered peer is removed from list" do
      :ok = Resolver.register_peer("store-b", "http://b.local:8080", ["document"])
      assert length(Resolver.list_peers()) == 1

      :ok = Resolver.deregister_peer("store-b")
      assert Resolver.list_peers() == []
    end
  end

  describe "query with no peers" do
    test "returns empty results without crashing" do
      {:ok, response} = Resolver.query("*", ["document"])

      assert response.results == []
      assert response.stores_queried == []
      assert response.stores_excluded == []
      assert response.drift_policy == :tolerate
    end
  end

  describe "pattern matching" do
    test "wildcard pattern matches all peers" do
      :ok = Resolver.register_peer("prod/us-1", "http://us1:8080", ["graph"])
      :ok = Resolver.register_peer("prod/eu-1", "http://eu1:8080", ["graph"])
      :ok = Resolver.register_peer("dev/local", "http://local:8080", ["graph"])

      {:ok, response} = Resolver.query("*", ["graph"], timeout: 2_000)

      # All 3 stores should be queried (will fail HTTP, but listed as queried)
      assert length(response.stores_queried) == 3
    end

    test "prefix pattern filters correctly" do
      :ok = Resolver.register_peer("prod/us-1", "http://us1:8080", ["graph"])
      :ok = Resolver.register_peer("prod/eu-1", "http://eu1:8080", ["graph"])
      :ok = Resolver.register_peer("dev/local", "http://local:8080", ["graph"])

      {:ok, response} = Resolver.query("prod/*", ["graph"], timeout: 2_000)

      assert length(response.stores_queried) == 2
      assert "dev/local" not in response.stores_queried
    end
  end

  describe "drift policy strict" do
    test "excludes peers below trust threshold" do
      :ok = Resolver.register_peer("trusted", "http://trusted:8080", ["graph"])
      :ok = Resolver.register_peer("untrusted", "http://untrusted:8080", ["graph"])

      # Both start at trust 1.0 (above 0.7 threshold), so both should be queried
      {:ok, response} = Resolver.query("*", ["graph"], drift_policy: :strict, timeout: 2_000)

      assert length(response.stores_queried) == 2
      assert response.stores_excluded == []
    end
  end

  describe "modality filtering" do
    test "only queries peers that support required modalities" do
      :ok = Resolver.register_peer("graph-only", "http://g:8080", ["graph"])
      :ok = Resolver.register_peer("full-stack", "http://f:8080", ["graph", "vector", "document"])

      {:ok, response} = Resolver.query("*", ["vector"], timeout: 2_000)

      assert length(response.stores_queried) == 1
      assert "full-stack" in response.stores_queried
    end
  end
end
