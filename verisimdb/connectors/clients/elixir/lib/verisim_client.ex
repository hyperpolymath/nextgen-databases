# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule VeriSimClient do
  @moduledoc """
  Main client module for connecting to a VeriSimDB instance.

  Holds connection configuration (base URL, authentication, timeout) and
  provides low-level HTTP helpers that the domain modules (`Hexad`, `Search`,
  `Drift`, `Provenance`, `Vql`, `Federation`) delegate to.

  ## Quick Start

      {:ok, client} = VeriSimClient.new("http://localhost:8080")
      {:ok, true} = VeriSimClient.health(client)

  ## Authentication

  Four authentication modes are supported:

    * `:none` — No authentication (local development, trusted networks).
    * `{:api_key, key}` — API key via the `X-API-Key` header.
    * `{:bearer, token}` — Bearer token via the `Authorization` header.
    * `{:basic, username, password}` — HTTP Basic authentication.

  ## Examples

      # Unauthenticated
      {:ok, client} = VeriSimClient.new("http://localhost:8080")

      # API key
      {:ok, client} = VeriSimClient.new("http://localhost:8080", auth: {:api_key, "my-key"})

      # Bearer token
      {:ok, client} = VeriSimClient.new("http://localhost:8080", auth: {:bearer, "my-token"})
  """

  @type auth ::
          :none
          | {:api_key, String.t()}
          | {:bearer, String.t()}
          | {:basic, String.t(), String.t()}

  @type t :: %__MODULE__{
          base_url: String.t(),
          auth: auth(),
          timeout: pos_integer()
        }

  defstruct [:base_url, auth: :none, timeout: 30_000]

  # ---------------------------------------------------------------------------
  # Constructors
  # ---------------------------------------------------------------------------

  @doc """
  Create a new VeriSimDB client.

  ## Options

    * `:auth` — Authentication mode (default: `:none`). See module docs.
    * `:timeout` — Per-request timeout in milliseconds (default: 30_000).

  ## Examples

      {:ok, client} = VeriSimClient.new("http://localhost:8080")
      {:ok, client} = VeriSimClient.new("http://localhost:8080", auth: {:api_key, "key"}, timeout: 10_000)
  """
  @spec new(String.t(), keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(base_url, opts \\ []) do
    auth = Keyword.get(opts, :auth, :none)
    timeout = Keyword.get(opts, :timeout, 30_000)

    # Validate the base URL is parseable.
    case URI.parse(base_url) do
      %URI{scheme: scheme} when scheme in ["http", "https"] ->
        # Strip trailing slash for consistent path joining.
        base = String.trim_trailing(base_url, "/")

        {:ok,
         %__MODULE__{
           base_url: base,
           auth: auth,
           timeout: timeout
         }}

      _ ->
        {:error, "Invalid base URL: #{base_url}. Must use http:// or https:// scheme."}
    end
  end

  # ---------------------------------------------------------------------------
  # Health check
  # ---------------------------------------------------------------------------

  @doc """
  Ping the VeriSimDB health endpoint.

  Returns `{:ok, true}` if the server is reachable and healthy, or an error tuple.
  """
  @spec health(t()) :: {:ok, boolean()} | {:error, term()}
  def health(%__MODULE__{} = client) do
    case do_get(client, "/health") do
      {:ok, _body} -> {:ok, true}
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Internal HTTP helpers (used by domain modules)
  # ---------------------------------------------------------------------------

  @doc false
  @spec do_get(t(), String.t()) :: {:ok, term()} | {:error, term()}
  def do_get(%__MODULE__{} = client, path) do
    url = build_url(client, path)

    Req.new(url: url, receive_timeout: client.timeout)
    |> apply_auth(client.auth)
    |> Req.get()
    |> handle_response()
  end

  @doc false
  @spec do_post(t(), String.t(), term()) :: {:ok, term()} | {:error, term()}
  def do_post(%__MODULE__{} = client, path, body) do
    url = build_url(client, path)

    Req.new(url: url, receive_timeout: client.timeout, json: body)
    |> apply_auth(client.auth)
    |> Req.post()
    |> handle_response()
  end

  @doc false
  @spec do_put(t(), String.t(), term()) :: {:ok, term()} | {:error, term()}
  def do_put(%__MODULE__{} = client, path, body) do
    url = build_url(client, path)

    Req.new(url: url, receive_timeout: client.timeout, json: body)
    |> apply_auth(client.auth)
    |> Req.put()
    |> handle_response()
  end

  @doc false
  @spec do_delete(t(), String.t()) :: :ok | {:error, term()}
  def do_delete(%__MODULE__{} = client, path) do
    url = build_url(client, path)

    case Req.new(url: url, receive_timeout: client.timeout)
         |> apply_auth(client.auth)
         |> Req.delete() do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        :ok

      {:ok, %Req.Response{status: 404, body: body}} ->
        {:error, {:not_found, extract_message(body)}}

      {:ok, %Req.Response{status: status, body: body}} when status in [401, 403] ->
        {:error, {:unauthorized, extract_message(body)}}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:server_error, status, extract_message(body)}}

      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp build_url(%__MODULE__{base_url: base}, path) do
    base <> path
  end

  defp apply_auth(req, :none), do: req

  defp apply_auth(req, {:api_key, key}) do
    Req.Request.put_header(req, "x-api-key", key)
  end

  defp apply_auth(req, {:bearer, token}) do
    Req.Request.put_header(req, "authorization", "Bearer #{token}")
  end

  defp apply_auth(req, {:basic, username, password}) do
    encoded = Base.encode64("#{username}:#{password}")
    Req.Request.put_header(req, "authorization", "Basic #{encoded}")
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}})
       when status in 200..299 do
    {:ok, body}
  end

  defp handle_response({:ok, %Req.Response{status: 404, body: body}}) do
    {:error, {:not_found, extract_message(body)}}
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}})
       when status in [401, 403] do
    {:error, {:unauthorized, extract_message(body)}}
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, {:server_error, status, extract_message(body)}}
  end

  defp handle_response({:error, reason}) do
    {:error, {:network_error, reason}}
  end

  defp extract_message(%{"message" => msg}) when is_binary(msg), do: msg
  defp extract_message(%{"error" => err}) when is_binary(err), do: err
  defp extract_message(body) when is_binary(body), do: body
  defp extract_message(body), do: inspect(body)
end
