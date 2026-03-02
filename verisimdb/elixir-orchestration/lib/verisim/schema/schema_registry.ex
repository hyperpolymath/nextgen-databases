# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.SchemaRegistry do
  @moduledoc """
  Schema Registry - Manages type definitions and constraints.

  Coordinates the semantic type system across the cluster,
  ensuring consistent type validation and constraint checking.

  ## Type Hierarchy

  Types form a hierarchy:
  - `verisim:Entity` - Base type for all entities
    - `verisim:Document` - Entities with document content
    - `verisim:Node` - Graph nodes
    - Custom types defined by users

  ## Constraints

  Constraints are validated during entity creation/update:
  - Required properties
  - Property patterns (regex)
  - Range constraints (min/max)
  - Custom validators
  """

  use GenServer
  require Logger

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a new type.

  ## Example

      SchemaRegistry.register_type(%{
        iri: "https://example.org/Person",
        label: "Person",
        supertypes: ["verisim:Entity"],
        constraints: [
          %{name: "name_required", kind: {:required, "name"}, message: "Name is required"}
        ]
      })
  """
  def register_type(type_def) do
    GenServer.call(__MODULE__, {:register_type, type_def})
  end

  @doc """
  Get a type definition by IRI.
  """
  def get_type(iri) do
    GenServer.call(__MODULE__, {:get_type, iri})
  end

  @doc """
  List all registered types.
  """
  def list_types do
    GenServer.call(__MODULE__, :list_types)
  end

  @doc """
  Validate an entity against its declared types.
  """
  def validate(entity) do
    GenServer.call(__MODULE__, {:validate, entity})
  end

  @doc """
  Get the type hierarchy (supertypes) for a type.
  """
  def type_hierarchy(iri) do
    GenServer.call(__MODULE__, {:type_hierarchy, iri})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    state = %{
      types: %{},
      type_cache: %{}
    }

    # Register built-in types
    state = register_builtin_types(state)

    {:ok, state}
  end

  @impl true
  def handle_call({:register_type, type_def}, _from, state) do
    iri = type_def.iri

    if Map.has_key?(state.types, iri) do
      {:reply, {:error, :already_exists}, state}
    else
      new_types = Map.put(state.types, iri, type_def)
      new_state = %{state | types: new_types, type_cache: %{}}

      Logger.info("Registered type: #{iri}")
      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:get_type, iri}, _from, state) do
    result = Map.get(state.types, iri)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:list_types, _from, state) do
    types = Map.keys(state.types)
    {:reply, types, state}
  end

  @impl true
  def handle_call({:validate, entity}, _from, state) do
    types = Map.get(entity, :types, [])

    violations =
      types
      |> Enum.flat_map(fn type_iri ->
        case Map.get(state.types, type_iri) do
          nil -> []
          type_def -> validate_constraints(entity, type_def)
        end
      end)

    result = if Enum.empty?(violations), do: :ok, else: {:error, violations}
    {:reply, result, state}
  end

  @impl true
  def handle_call({:type_hierarchy, iri}, _from, state) do
    hierarchy = compute_hierarchy(iri, state.types, [])
    {:reply, hierarchy, state}
  end

  # Private Functions

  defp register_builtin_types(state) do
    builtin_types = [
      %{
        iri: "verisim:Entity",
        label: "Entity",
        supertypes: [],
        constraints: []
      },
      %{
        iri: "verisim:Document",
        label: "Document",
        supertypes: ["verisim:Entity"],
        constraints: [
          %{name: "title_required", kind: {:required, "title"}, message: "Documents must have a title"}
        ]
      },
      %{
        iri: "verisim:Node",
        label: "Graph Node",
        supertypes: ["verisim:Entity"],
        constraints: []
      },
      %{
        iri: "verisim:TimeSeries",
        label: "Time Series",
        supertypes: ["verisim:Entity"],
        constraints: []
      }
    ]

    new_types =
      Enum.reduce(builtin_types, state.types, fn type, acc ->
        Map.put(acc, type.iri, type)
      end)

    %{state | types: new_types}
  end

  defp validate_constraints(entity, type_def) do
    type_def.constraints
    |> Enum.map(fn constraint ->
      case validate_constraint(entity, constraint) do
        :ok -> nil
        {:error, msg} -> msg
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp validate_constraint(entity, %{kind: {:required, property}, message: msg}) do
    properties = Map.get(entity, :properties, %{})
    if Map.has_key?(properties, property) do
      :ok
    else
      {:error, msg}
    end
  end

  defp validate_constraint(entity, %{kind: {:pattern, property, pattern}, message: msg}) do
    properties = Map.get(entity, :properties, %{})
    case Map.get(properties, property) do
      nil -> :ok
      value ->
        if Regex.match?(~r/#{pattern}/, value) do
          :ok
        else
          {:error, msg}
        end
    end
  end

  defp validate_constraint(entity, %{kind: {:range, property, min, max}, message: msg}) do
    properties = Map.get(entity, :properties, %{})
    case Map.get(properties, property) do
      nil -> :ok
      value when is_number(value) ->
        if (is_nil(min) or value >= min) and (is_nil(max) or value <= max) do
          :ok
        else
          {:error, msg}
        end
      _ -> :ok
    end
  end

  defp validate_constraint(_entity, %{kind: kind, message: _msg}) do
    {:error, "Unknown constraint type: #{inspect(kind)}"}
  end

  defp validate_constraint(_entity, _constraint) do
    {:error, "Malformed constraint: missing kind or message"}
  end

  defp compute_hierarchy(iri, types, visited) do
    if iri in visited do
      []  # Prevent cycles
    else
      case Map.get(types, iri) do
        nil -> []
        type_def ->
          supertypes = type_def.supertypes || []
          [iri | Enum.flat_map(supertypes, &compute_hierarchy(&1, types, [iri | visited]))]
      end
    end
  end
end
