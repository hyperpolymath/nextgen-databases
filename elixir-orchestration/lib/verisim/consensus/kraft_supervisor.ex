# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Consensus.KRaftSupervisor do
  @moduledoc """
  Supervisor for the KRaft consensus cluster.

  Starts a local Elixir Registry for node name resolution, then
  starts the configured KRaft nodes under supervision.

  ## Usage

      # In application.ex
      children = [
        {VeriSim.Consensus.KRaftSupervisor, nodes: [
          [node_id: "node-1", peers: ["node-2", "node-3"]],
          [node_id: "node-2", peers: ["node-1", "node-3"]],
          [node_id: "node-3", peers: ["node-1", "node-2"]],
        ]}
      ]
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    nodes = Keyword.get(opts, :nodes, [])

    children =
      [
        # Process registry for node name resolution
        {Registry, keys: :unique, name: VeriSim.Consensus.Registry}
      ] ++
        Enum.map(nodes, fn node_opts ->
          node_id = Keyword.fetch!(node_opts, :node_id)

          Supervisor.child_spec(
            {VeriSim.Consensus.KRaftNode, node_opts},
            id: {VeriSim.Consensus.KRaftNode, node_id}
          )
        end)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
