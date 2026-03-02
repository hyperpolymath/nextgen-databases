# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Query.VQLBridge do
  @moduledoc """
  Bridge between the ReScript VQL parser and Elixir VQL executor.

  Manages a long-running Deno/Node process that runs the compiled ReScript
  VQL parser. Communication uses JSON over stdin/stdout with length-prefixed
  framing for reliable message boundaries.

  ## Architecture

      VQL String ──► VQLBridge (GenServer)
                        │
                        ▼
                     Port (stdin/stdout JSON)
                        │
                        ▼
                     Deno process running compiled VQLParser.res
                        │
                        ▼
                     Parsed AST (JSON) ──► VQLExecutor

  ## Usage

      {:ok, ast} = VQLBridge.parse("SELECT GRAPH, VECTOR FROM HEXAD abc-123")
      {:ok, results} = VQLExecutor.execute(ast)
  """

  use GenServer
  require Logger

  @default_timeout 5_000
  @parser_script_path "vql-bridge/vql_parser_port.js"

  # ---------------------------------------------------------------------------
  # Client API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Parse a VQL query string into an AST map.

  Returns `{:ok, ast}` where ast is a map matching the VQLParser.AST types,
  or `{:error, reason}` on parse failure.
  """
  def parse(query_string, timeout \\ @default_timeout) do
    GenServer.call(__MODULE__, {:parse, query_string}, timeout)
  end

  @doc """
  Parse a slipstream query (no PROOF clause allowed).
  """
  def parse_slipstream(query_string, timeout \\ @default_timeout) do
    GenServer.call(__MODULE__, {:parse_slipstream, query_string}, timeout)
  end

  @doc """
  Parse a dependent-type query (PROOF clause required).
  """
  def parse_dependent(query_string, timeout \\ @default_timeout) do
    GenServer.call(__MODULE__, {:parse_dependent, query_string}, timeout)
  end

  @doc """
  Parse a VQL mutation (INSERT / UPDATE / DELETE).
  """
  def parse_mutation(query_string, timeout \\ @default_timeout) do
    GenServer.call(__MODULE__, {:parse_mutation, query_string}, timeout)
  end

  @doc """
  Parse a VQL statement (query or mutation).
  """
  def parse_statement(query_string, timeout \\ @default_timeout) do
    GenServer.call(__MODULE__, {:parse_statement, query_string}, timeout)
  end

  @doc """
  Parse and execute a VQL query string in one call.
  Combines VQLBridge.parse/1 with VQLExecutor.execute/2.
  """
  def parse_and_execute(query_string, opts \\ []) do
    case parse(query_string) do
      {:ok, ast} -> VeriSim.Query.VQLExecutor.execute(ast, opts)
      {:error, _} = error -> error
    end
  end

  @doc """
  Parse and execute a VQL statement (query or mutation).
  """
  def parse_and_execute_statement(query_string, opts \\ []) do
    case parse_statement(query_string) do
      {:ok, ast} -> VeriSim.Query.VQLExecutor.execute_statement(ast, opts)
      {:error, _} = error -> error
    end
  end

  @doc """
  Type-check a parsed VQL-DT AST.

  Sends the AST to the ReScript type checker (VQLBidir.synthesizeQuery)
  via the Deno/Node subprocess. Returns inferred types, proof obligations,
  and composition strategy.

  Falls back to `{:error, :type_checker_unavailable}` if the subprocess is
  not running — callers MUST NOT silently bypass this.

  ## Returns

  - `{:ok, type_info}` where type_info contains:
    - `:proof_obligations` — list of proof specs from the type checker
    - `:composition_strategy` — how proofs should be composed (:conjunction, :disjunction, etc.)
    - `:inferred_types` — map of modality → field → type
  - `{:error, :type_checker_unavailable}` — subprocess not running
  - `{:error, reason}` — type checking failed (invalid query, type mismatch, etc.)
  """
  def typecheck(ast, timeout \\ @default_timeout) do
    GenServer.call(__MODULE__, {:typecheck, ast}, timeout)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(opts) do
    runtime = Keyword.get(opts, :runtime, detect_runtime())
    script_path = Keyword.get(opts, :script_path, resolve_script_path())

    state = %{
      port: nil,
      runtime: runtime,
      script_path: script_path,
      pending: %{},
      next_id: 1
    }

    case start_port(state) do
      {:ok, port} ->
        Logger.info("VQLBridge started with #{runtime}")
        {:ok, %{state | port: port}}

      {:error, reason} ->
        Logger.warning("VQLBridge: parser process unavailable (#{reason}), falling back to built-in parser")
        {:ok, state}
    end
  end

  @impl true
  def handle_call({:typecheck, _ast}, _from, %{port: nil} = state) do
    # Type checking requires the ReScript subprocess — no fallback.
    # Callers MUST handle this error; silently passing would defeat VQL-DT.
    {:reply, {:error, :type_checker_unavailable}, state}
  end

  @impl true
  def handle_call({:typecheck, ast}, from, state) do
    id = state.next_id
    message = Jason.encode!(%{
      "id" => id,
      "action" => "typecheck",
      "ast" => ast
    })

    send_to_port(state.port, message)
    pending = Map.put(state.pending, id, from)
    {:noreply, %{state | pending: pending, next_id: id + 1}}
  end

  @impl true
  def handle_call({action, query_string}, _from, %{port: nil} = state)
      when action in [:parse, :parse_slipstream, :parse_dependent,
                      :parse_mutation, :parse_statement] do
    # Fallback: no external parser available, use built-in Elixir parser
    result = builtin_parse(query_string, action)
    {:reply, result, state}
  end

  @impl true
  def handle_call({action, query_string}, from, state)
      when action in [:parse, :parse_slipstream, :parse_dependent,
                      :parse_mutation, :parse_statement] do
    id = state.next_id
    message = Jason.encode!(%{
      "id" => id,
      "action" => Atom.to_string(action),
      "query" => query_string
    })

    # Send length-prefixed message to port
    send_to_port(state.port, message)

    pending = Map.put(state.pending, id, from)
    {:noreply, %{state | pending: pending, next_id: id + 1}}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    case Jason.decode(IO.iodata_to_binary(data)) do
      {:ok, %{"id" => id, "ok" => ast}} ->
        case Map.pop(state.pending, id) do
          {nil, _} -> {:noreply, state}
          {from, pending} ->
            GenServer.reply(from, {:ok, atomize_keys(ast)})
            {:noreply, %{state | pending: pending}}
        end

      {:ok, %{"id" => id, "error" => reason}} ->
        case Map.pop(state.pending, id) do
          {nil, _} -> {:noreply, state}
          {from, pending} ->
            GenServer.reply(from, {:error, reason})
            {:noreply, %{state | pending: pending}}
        end

      {:error, _} ->
        Logger.warning("VQLBridge: received malformed data from parser port")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.warning("VQLBridge: parser process exited with status #{status}")

    # Reply to all pending requests with error
    for {_id, from} <- state.pending do
      GenServer.reply(from, {:error, :parser_crashed})
    end

    # Try to restart
    case start_port(state) do
      {:ok, new_port} ->
        Logger.info("VQLBridge: parser process restarted")
        {:noreply, %{state | port: new_port, pending: %{}}}

      {:error, _} ->
        {:noreply, %{state | port: nil, pending: %{}}}
    end
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp start_port(state) do
    runtime = state.runtime
    script = state.script_path

    if runtime && File.exists?(script) do
      try do
        port = Port.open(
          {:spawn_executable, runtime},
          [:binary, :exit_status, {:args, [script]}, {:line, 1_048_576}]
        )
        {:ok, port}
      rescue
        e -> {:error, Exception.message(e)}
      end
    else
      {:error, "runtime (#{runtime}) or script (#{script}) not found"}
    end
  end

  defp send_to_port(port, message) do
    Port.command(port, message <> "\n")
  end

  defp detect_runtime do
    cond do
      System.find_executable("deno") -> System.find_executable("deno")
      System.find_executable("node") -> System.find_executable("node")
      true -> nil
    end
  end

  defp resolve_script_path do
    # Look relative to the project root
    base = Application.get_env(:verisim, :project_root, File.cwd!())
    Path.join(base, @parser_script_path)
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) ->
        {String.to_existing_atom(key), atomize_keys(value)}
      {key, value} ->
        {key, atomize_keys(value)}
    end)
  rescue
    ArgumentError -> map
  end

  defp atomize_keys(list) when is_list(list), do: Enum.map(list, &atomize_keys/1)
  defp atomize_keys(other), do: other

  # ---------------------------------------------------------------------------
  # Built-in Elixir Parser (fallback when Deno/Node unavailable)
  # ---------------------------------------------------------------------------

  defp builtin_parse(query_string, action) do
    query_string = String.trim(query_string)

    case action do
      :parse_mutation ->
        with {:ok, tokens} <- tokenize(query_string),
             {:ok, mutation} <- parse_mutation_tokens(tokens) do
          {:ok, mutation}
        end

      :parse_statement ->
        with {:ok, tokens} <- tokenize(query_string) do
          first = tokens |> List.first() |> to_string() |> String.upcase()
          case first do
            cmd when cmd in ["INSERT", "UPDATE", "DELETE"] ->
              with {:ok, mutation} <- parse_mutation_tokens(tokens) do
                {:ok, %{TAG: "Mutation", _0: mutation}}
              end
            _ ->
              with {:ok, ast} <- parse_tokens(tokens) do
                {:ok, %{TAG: "Query", _0: ast}}
              end
          end
        end

      _ ->
        with {:ok, tokens} <- tokenize(query_string),
             {:ok, ast} <- parse_tokens(tokens) do
          case action do
            :parse_slipstream ->
              if ast[:proof], do: {:error, "Slipstream queries cannot have PROOF clause"}, else: {:ok, ast}
            :parse_dependent ->
              if ast[:proof], do: {:ok, ast}, else: {:error, "Dependent-type queries require PROOF clause"}
            :parse ->
              {:ok, ast}
          end
        end
    end
  end

  defp tokenize(input) do
    # Simple whitespace-aware tokenizer
    tokens =
      input
      |> String.replace(~r/\s+/, " ")
      |> String.split(" ", trim: true)

    {:ok, tokens}
  end

  defp parse_tokens(tokens) do
    with {:ok, modalities, projections, aggregates, rest} <- parse_select_extended(tokens),
         {:ok, source, rest} <- parse_from(rest),
         {:ok, where_clause, rest} <- parse_where(rest),
         {:ok, group_by, rest} <- parse_group_by(rest),
         {:ok, having, rest} <- parse_having(rest),
         {:ok, proof, rest} <- parse_proof(rest),
         {:ok, order_by, rest} <- parse_order_by(rest),
         {:ok, limit, rest} <- parse_limit(rest),
         {:ok, offset, _rest} <- parse_offset(rest) do
      {:ok, %{
        modalities: modalities,
        projections: projections,
        aggregates: aggregates,
        source: source,
        where: where_clause,
        groupBy: group_by,
        having: having,
        proof: proof,
        orderBy: order_by,
        limit: limit,
        offset: offset
      }}
    end
  end

  defp parse_select(["SELECT" | rest]) do
    {modalities, rest} = take_modalities(rest, [])
    {:ok, modalities, rest}
  end

  defp parse_select(_), do: {:error, "Expected SELECT"}

  defp take_modalities(["GRAPH" | rest], acc), do: take_modalities(strip_comma(rest), [:graph | acc])
  defp take_modalities(["VECTOR" | rest], acc), do: take_modalities(strip_comma(rest), [:vector | acc])
  defp take_modalities(["TENSOR" | rest], acc), do: take_modalities(strip_comma(rest), [:tensor | acc])
  defp take_modalities(["SEMANTIC" | rest], acc), do: take_modalities(strip_comma(rest), [:semantic | acc])
  defp take_modalities(["DOCUMENT" | rest], acc), do: take_modalities(strip_comma(rest), [:document | acc])
  defp take_modalities(["TEMPORAL" | rest], acc), do: take_modalities(strip_comma(rest), [:temporal | acc])
  defp take_modalities(["PROVENANCE" | rest], acc), do: take_modalities(strip_comma(rest), [:provenance | acc])
  defp take_modalities(["SPATIAL" | rest], acc), do: take_modalities(strip_comma(rest), [:spatial | acc])
  defp take_modalities(["*" | rest], acc), do: take_modalities(strip_comma(rest), [:all | acc])
  defp take_modalities(rest, acc), do: {Enum.reverse(acc), rest}

  defp strip_comma(["," <> token | rest]) when token != "" do
    [token | rest]
  end
  defp strip_comma(["," | rest]), do: rest
  defp strip_comma(rest), do: rest

  defp parse_from(["FROM", "HEXAD", uuid | rest]) do
    {:ok, {:hexad, uuid}, rest}
  end

  defp parse_from(["FROM", "FEDERATION", pattern | rest]) do
    {drift_policy, rest} = parse_drift_policy(rest)
    {:ok, {:federation, pattern, drift_policy}, rest}
  end

  defp parse_from(["FROM", "STORE", store_id | rest]) do
    {:ok, {:store, store_id}, rest}
  end

  defp parse_from(_), do: {:error, "Expected FROM clause"}

  defp parse_drift_policy(["WITH", "DRIFT", policy | rest]) do
    drift = case String.upcase(policy) do
      "STRICT" -> :strict
      "REPAIR" -> :repair
      "TOLERATE" -> :tolerate
      "LATEST" -> :latest
      _ -> nil
    end
    {drift, rest}
  end

  defp parse_drift_policy(rest), do: {nil, rest}

  defp parse_where(["WHERE" | rest]) do
    # Simplified: collect everything until PROOF, LIMIT, OFFSET, or end
    {condition_tokens, rest} = Enum.split_while(rest, fn token ->
      token not in ["PROOF", "LIMIT", "OFFSET"]
    end)

    condition = if condition_tokens == [] do
      nil
    else
      %{raw: Enum.join(condition_tokens, " ")}
    end

    {:ok, condition, rest}
  end

  defp parse_where(rest), do: {:ok, nil, rest}

  defp parse_proof(["PROOF" | rest]) do
    {proof_tokens, rest} = Enum.split_while(rest, fn token ->
      token not in ["LIMIT", "OFFSET"]
    end)

    raw = Enum.join(proof_tokens, " ")

    # Split multi-proof specs on AND/OR connectors into a list.
    # "EXISTENCE(a) AND PROVENANCE(b)" → [%{raw: "EXISTENCE(a)"}, %{raw: "PROVENANCE(b)"}]
    specs = VeriSim.Query.VQLTypeChecker.parse_proof_specs(%{raw: raw})

    proof = case specs do
      [] -> %{raw: raw}
      [single] -> single
      multiple -> multiple
    end

    {:ok, proof, rest}
  end

  defp parse_proof(rest), do: {:ok, nil, rest}

  defp parse_limit(["LIMIT", n | rest]) do
    case Integer.parse(n) do
      {limit, _} -> {:ok, limit, rest}
      :error -> {:error, "Invalid LIMIT value"}
    end
  end

  defp parse_limit(rest), do: {:ok, nil, rest}

  defp parse_offset(["OFFSET", n | rest]) do
    case Integer.parse(n) do
      {offset, _} -> {:ok, offset, rest}
      :error -> {:error, "Invalid OFFSET value"}
    end
  end

  defp parse_offset(rest), do: {:ok, nil, rest}

  # Extended SELECT parser: handles MODALITY.field projections and aggregates
  defp parse_select_extended(["SELECT" | rest]) do
    {items, rest} = take_select_items(rest, [], [], [])
    {:ok, elem(items, 0), elem(items, 1), elem(items, 2), rest}
  end

  defp parse_select_extended(_), do: {:error, "Expected SELECT"}

  @modality_names ~w(GRAPH VECTOR TENSOR SEMANTIC DOCUMENT TEMPORAL PROVENANCE SPATIAL)
  @aggregate_funcs ~w(COUNT SUM AVG MIN MAX)

  # Safe atom conversion using allowlist — prevents atom table exhaustion
  @safe_atoms %{
    "graph" => :graph, "vector" => :vector, "tensor" => :tensor,
    "semantic" => :semantic, "document" => :document, "temporal" => :temporal,
    "provenance" => :provenance, "spatial" => :spatial,
    "all" => :all,
    "count" => :count, "sum" => :sum, "avg" => :avg, "min" => :min, "max" => :max
  }

  defp safe_to_atom(str) when is_binary(str) do
    downcased = String.downcase(str)

    case Map.fetch(@safe_atoms, downcased) do
      {:ok, atom} ->
        atom

      :error ->
        raise ArgumentError,
              "Unknown VQL token #{inspect(str)} — not in @safe_atoms allowlist"
    end
  end

  defp take_select_items(tokens, mods, projs, aggs) do
    case tokens do
      # COUNT(*)
      [func, "(*)" | rest] when func in @aggregate_funcs ->
        take_select_items(strip_comma(rest), mods, projs, [:count_all | aggs])

      [func, "(", "*", ")" | rest] when func in @aggregate_funcs ->
        take_select_items(strip_comma(rest), mods, projs, [:count_all | aggs])

      # FUNC(MODALITY.field)
      [func | rest] when func in @aggregate_funcs ->
        case parse_aggregate_arg(rest) do
          {:ok, mod, field, rest} ->
            agg = {:aggregate_field, safe_to_atom(func), %{modality: mod, field: field}}
            mod_atom = safe_to_atom(mod)
            mods = if mod_atom in mods, do: mods, else: [mod_atom | mods]
            take_select_items(strip_comma(rest), mods, projs, [agg | aggs])
          _ ->
            {{Enum.reverse(mods), nilify(projs), nilify(aggs)}, tokens}
        end

      # MODALITY.field (column projection)
      [token | rest] ->
        case String.split(token, ".", parts: 2) do
          [mod_str, field] when mod_str in @modality_names ->
            proj = %{modality: safe_to_atom(mod_str), field: field}
            mod_atom = safe_to_atom(mod_str)
            mods = if mod_atom in mods, do: mods, else: [mod_atom | mods]
            take_select_items(strip_comma(rest), mods, [proj | projs], aggs)

          _ ->
            # Try as bare modality
            up = String.upcase(String.replace(token, ",", ""))
            cond do
              up in @modality_names ->
                mod_atom = safe_to_atom(up)
                take_select_items(strip_comma(rest), [mod_atom | mods], projs, aggs)
              up == "*" ->
                take_select_items(strip_comma(rest), [:all | mods], projs, aggs)
              true ->
                {{Enum.reverse(mods), nilify(projs), nilify(aggs)}, tokens}
            end
        end

      [] ->
        {{Enum.reverse(mods), nilify(projs), nilify(aggs)}, []}
    end
  end

  defp parse_aggregate_arg(["(" <> rest_token | rest]) do
    # Handle "(MODALITY.field)" — may be split across tokens
    inner = String.trim_trailing(rest_token, ")")
    case String.split(inner, ".", parts: 2) do
      [mod, field] when mod in @modality_names ->
        rest = case rest do
          [")" | r] -> r
          _ -> rest
        end
        {:ok, mod, field, rest}
      _ -> :error
    end
  end
  defp parse_aggregate_arg(_), do: :error

  defp nilify([]), do: nil
  defp nilify(list), do: Enum.reverse(list)

  # GROUP BY parser
  defp parse_group_by(["GROUP", "BY" | rest]) do
    {fields, rest} = take_field_refs(rest, [])
    {:ok, if(fields == [], do: nil, else: fields), rest}
  end

  defp parse_group_by(rest), do: {:ok, nil, rest}

  defp take_field_refs([token | rest], acc) do
    clean = String.replace(token, ",", "")
    case String.split(clean, ".", parts: 2) do
      [mod_str, field] when mod_str in @modality_names ->
        ref = %{modality: safe_to_atom(mod_str), field: field}
        take_field_refs(strip_comma(rest), [ref | acc])
      _ ->
        {Enum.reverse(acc), [token | rest]}
    end
  end

  defp take_field_refs([], acc), do: {Enum.reverse(acc), []}

  # HAVING parser (collects tokens until ORDER/PROOF/LIMIT/OFFSET/end)
  defp parse_having(["HAVING" | rest]) do
    {condition_tokens, rest} = Enum.split_while(rest, fn token ->
      String.upcase(token) not in ["ORDER", "PROOF", "LIMIT", "OFFSET"]
    end)

    condition = if condition_tokens == [] do
      nil
    else
      %{raw: Enum.join(condition_tokens, " ")}
    end

    {:ok, condition, rest}
  end

  defp parse_having(rest), do: {:ok, nil, rest}

  # ORDER BY parser
  defp parse_order_by(["ORDER", "BY" | rest]) do
    {items, rest} = take_order_items(rest, [])
    {:ok, if(items == [], do: nil, else: items), rest}
  end

  defp parse_order_by(rest), do: {:ok, nil, rest}

  defp take_order_items([token | rest], acc) do
    clean = String.replace(token, ",", "")
    case String.split(clean, ".", parts: 2) do
      [mod_str, field] when mod_str in @modality_names ->
        {direction, rest} = case rest do
          ["ASC" | r] -> {:asc, strip_comma(r)}
          ["DESC" | r] -> {:desc, strip_comma(r)}
          ["ASC," <> _ | _] -> {:asc, strip_comma(rest)}
          ["DESC," <> _ | _] -> {:desc, strip_comma(rest)}
          _ -> {:asc, strip_comma(rest)}
        end

        item = %{
          field: %{modality: safe_to_atom(mod_str), field: field},
          direction: direction
        }
        take_order_items(rest, [item | acc])

      _ ->
        {Enum.reverse(acc), [token | rest]}
    end
  end

  defp take_order_items([], acc), do: {Enum.reverse(acc), []}

  # ---------------------------------------------------------------------------
  # Mutation Parser (INSERT / UPDATE / DELETE)
  # ---------------------------------------------------------------------------

  defp parse_mutation_tokens(["INSERT", "HEXAD", "WITH" | rest]) do
    {modality_data, rest} = take_modality_data(rest, [])
    {:ok, proof, _rest} = parse_proof(rest)
    {:ok, %{
      TAG: "Insert",
      modalities: modality_data,
      proof: proof
    }}
  end

  defp parse_mutation_tokens(["UPDATE", "HEXAD", uuid, "SET" | rest]) do
    {sets, rest} = take_set_assignments(rest, [])
    {:ok, proof, _rest} = parse_proof(rest)
    {:ok, %{
      TAG: "Update",
      hexadId: uuid,
      sets: sets,
      proof: proof
    }}
  end

  defp parse_mutation_tokens(["DELETE", "HEXAD", uuid | rest]) do
    {:ok, proof, _rest} = parse_proof(rest)
    {:ok, %{
      TAG: "Delete",
      hexadId: uuid,
      proof: proof
    }}
  end

  defp parse_mutation_tokens(_), do: {:error, "Expected INSERT, UPDATE, or DELETE"}

  # Parse modality data for INSERT: DOCUMENT(field=value, ...), VECTOR([...]), etc.
  defp take_modality_data(tokens, acc) do
    case tokens do
      [mod | rest] when mod in @modality_names ->
        case rest do
          ["(" <> inner_start | rest2] ->
            {inner_tokens, rest3} = collect_until_close_paren([inner_start | rest2], [])
            data = %{modality: safe_to_atom(mod), raw: Enum.join(inner_tokens, " ")}
            take_modality_data(strip_comma(rest3), [data | acc])
          _ ->
            {Enum.reverse(acc), tokens}
        end
      _ ->
        {Enum.reverse(acc), tokens}
    end
  end

  defp collect_until_close_paren([], acc), do: {Enum.reverse(acc), []}
  defp collect_until_close_paren([token | rest], acc) do
    if String.ends_with?(token, ")") do
      cleaned = String.trim_trailing(token, ")")
      if cleaned != "", do: {Enum.reverse([cleaned | acc]), rest}, else: {Enum.reverse(acc), rest}
    else
      collect_until_close_paren(rest, [token | acc])
    end
  end

  # Parse SET assignments for UPDATE: field = value, field = value
  defp take_set_assignments(tokens, acc) do
    case tokens do
      [field, "=", value | rest] ->
        assignment = %{field: field, value: value}
        take_set_assignments(strip_comma(rest), [assignment | acc])
      _ ->
        {Enum.reverse(acc), tokens}
    end
  end
end
