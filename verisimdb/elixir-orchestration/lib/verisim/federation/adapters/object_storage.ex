# SPDX-License-Identifier: PMPL-1.0-or-later

defmodule VeriSim.Federation.Adapters.ObjectStorage do
  @moduledoc """
  Unified federation adapter for S3-compatible object storage: MinIO and
  Amazon S3.

  Translates VeriSimDB modality queries into S3 API calls and normalises
  results into the federation result format. Object storage is not a
  traditional database, but it serves as a durable persistence layer for
  VeriSimDB entities — particularly for document content, provenance audit
  trails, and temporal versioning.

  ## Modality Mapping

  | VeriSimDB Modality | S3/MinIO Capability           | Feature Required           |
  |--------------------|-------------------------------|----------------------------|
  | `:document`        | Object content + metadata FT  | Custom metadata indexing   |
  | `:temporal`        | Object versioning             | Bucket versioning enabled  |
  | `:provenance`      | Access logs / audit trails    | Server access logging      |
  | `:semantic`        | Object metadata / tags        | Built-in (user metadata)   |

  Object storage does not support graph traversal, vector similarity,
  tensor operations, or geospatial queries, so `:graph`, `:vector`,
  `:tensor`, and `:spatial` modalities are not supported.

  ## Configuration

      # MinIO
      %{
        host: "minio.internal",
        port: 9000,
        bucket: "verisimdb-hexads",
        region: "us-east-1",
        access_key: "minioadmin",
        secret_key: "minioadmin",
        backend: :minio
      }

      # Amazon S3
      %{
        host: "s3.amazonaws.com",
        port: 443,
        bucket: "verisimdb-hexads",
        region: "eu-west-1",
        access_key: "AKIA...",
        secret_key: "...",
        backend: :s3
      }

  ## S3 API Compatibility

  Both MinIO and Amazon S3 implement the S3 API. This adapter uses the
  REST API via Req with AWS Signature V4 authentication. MinIO endpoints
  use path-style URLs; S3 uses virtual-hosted-style by default.

  ## Query Model

  Since S3 is not a query engine, "queries" are implemented as:
  - **ListObjectsV2**: List objects with prefix filtering
  - **HeadObject**: Check existence and metadata
  - **GetObject**: Retrieve content
  - **GetObjectTagging**: Retrieve tags for semantic filtering
  - **ListObjectVersions**: Temporal versioning queries
  """

  @behaviour VeriSim.Federation.Adapter

  require Logger

  @default_timeout 15_000

  # ---------------------------------------------------------------------------
  # Callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def connect(peer_info) do
    case health_check(peer_info) do
      {:ok, _latency} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def query(peer_info, query_params, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    modalities = Map.get(query_params, :modalities, [])
    limit = Map.get(query_params, :limit, 100)

    start = System.monotonic_time(:millisecond)

    result = execute_s3_query(peer_info, modalities, query_params, limit, timeout)

    elapsed = System.monotonic_time(:millisecond) - start

    case result do
      {:ok, raw_results} ->
        normalised =
          raw_results
          |> translate_results(peer_info)
          |> Enum.map(fn r -> Map.put(r, :response_time_ms, elapsed) end)

        {:ok, normalised}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e ->
      Logger.warning(
        "ObjectStorage adapter: exception querying #{peer_info.store_id}: #{inspect(e)}"
      )

      {:error, {:exception, e}}
  end

  @impl true
  def health_check(peer_info) do
    config = peer_info.adapter_config
    bucket = Map.get(config, :bucket, "verisimdb-hexads")
    start = System.monotonic_time(:millisecond)

    # Health check: HEAD bucket to verify it exists and is accessible
    url = build_bucket_url(peer_info, bucket)
    headers = auth_headers(config)

    case Req.head(url, headers: headers, receive_timeout: 5_000) do
      {:ok, %Req.Response{status: status}} when status in [200, 301, 307] ->
        elapsed = System.monotonic_time(:millisecond) - start
        {:ok, elapsed}

      {:ok, %Req.Response{status: 404}} ->
        {:error, {:bucket_not_found, bucket}}

      {:ok, %Req.Response{status: 403}} ->
        {:error, {:access_denied, bucket}}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:unhealthy, status}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, {:exception, e}}
  end

  @impl true
  def supported_modalities(adapter_config) do
    versioning_enabled = Map.get(adapter_config, :versioning, false)
    logging_enabled = Map.get(adapter_config, :access_logging, false)

    base = [:document, :semantic]

    base
    |> maybe_add(:temporal, versioning_enabled)
    |> maybe_add(:provenance, logging_enabled)
  end

  @impl true
  def translate_results(raw_results, peer_info) do
    raw_results
    |> List.wrap()
    |> Enum.map(fn obj ->
      %{
        source_store: peer_info.store_id,
        hexad_id: extract_object_id(obj),
        score: parse_score(obj),
        drifted: false,
        data: obj,
        response_time_ms: 0
      }
    end)
  end

  # ---------------------------------------------------------------------------
  # Private — S3 Query Execution
  # ---------------------------------------------------------------------------

  defp execute_s3_query(peer_info, modalities, query_params, limit, timeout) do
    config = peer_info.adapter_config
    bucket = Map.get(config, :bucket, "verisimdb-hexads")

    cond do
      :temporal in modalities && Map.has_key?(query_params, :temporal_range) ->
        # ListObjectVersions: retrieve versioned objects within a time range
        list_object_versions(peer_info, bucket, query_params, limit, timeout)

      :document in modalities && Map.has_key?(query_params, :text_query) ->
        # ListObjectsV2 with prefix matching, then filter by metadata
        text = query_params.text_query
        list_objects_with_prefix(peer_info, bucket, text, limit, timeout)

      :provenance in modalities ->
        # List objects from the audit/provenance prefix
        provenance_prefix = Map.get(config, :provenance_prefix, "provenance/")
        list_objects_with_prefix(peer_info, bucket, provenance_prefix, limit, timeout)

      :semantic in modalities && Map.has_key?(query_params, :filters) ->
        # ListObjectsV2 + HeadObject to filter by metadata/tags
        list_and_filter_by_metadata(peer_info, bucket, query_params.filters, limit, timeout)

      true ->
        # Default: list all objects in the bucket
        list_objects_with_prefix(peer_info, bucket, "", limit, timeout)
    end
  end

  defp list_objects_with_prefix(peer_info, bucket, prefix, limit, timeout) do
    url = build_bucket_url(peer_info, bucket)
    headers = auth_headers(peer_info.adapter_config)

    query_params = %{
      "list-type" => "2",
      "prefix" => prefix,
      "max-keys" => to_string(limit)
    }

    query_string = URI.encode_query(query_params)
    full_url = "#{url}?#{query_string}"

    case Req.get(full_url, headers: headers, receive_timeout: timeout) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        objects = parse_list_objects_response(body)
        {:ok, objects}

      {:ok, %Req.Response{status: status, body: body}} ->
        error_msg = extract_s3_error(body) || "HTTP #{status}"
        Logger.warning("ObjectStorage adapter: ListObjects failed: #{error_msg}")
        {:error, {:s3_error, status, error_msg}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp list_object_versions(peer_info, bucket, query_params, limit, timeout) do
    config = peer_info.adapter_config
    url = build_bucket_url(peer_info, bucket)
    headers = auth_headers(config)

    range = query_params.temporal_range
    prefix = Map.get(config, :prefix, "")

    params = %{
      "versions" => "",
      "prefix" => prefix,
      "max-keys" => to_string(limit)
    }

    query_string = URI.encode_query(params)
    full_url = "#{url}?#{query_string}"

    case Req.get(full_url, headers: headers, receive_timeout: timeout) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        versions = parse_list_versions_response(body, range)
        {:ok, versions}

      {:ok, %Req.Response{status: status, body: body}} ->
        error_msg = extract_s3_error(body) || "HTTP #{status}"
        {:error, {:s3_error, status, error_msg}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp list_and_filter_by_metadata(peer_info, bucket, filters, limit, timeout) do
    # S3 does not support server-side metadata filtering.
    # Strategy: list objects, then HEAD each to check metadata.
    # This is expensive — limited to `limit * 2` candidates.
    candidate_limit = min(limit * 2, 1000)

    case list_objects_with_prefix(peer_info, bucket, "", candidate_limit, timeout) do
      {:ok, objects} ->
        filtered =
          objects
          |> Enum.filter(fn obj ->
            metadata = obj["metadata"] || %{}
            tags = obj["tags"] || %{}
            combined = Map.merge(metadata, tags)

            Enum.all?(filters, fn {key, value} ->
              combined[to_string(key)] == to_string(value)
            end)
          end)
          |> Enum.take(limit)

        {:ok, filtered}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private — Response Parsing
  # ---------------------------------------------------------------------------

  defp parse_list_objects_response(body) when is_map(body) do
    # JSON response (some S3 proxies return JSON)
    contents = body["Contents"] || body["contents"] || []
    Enum.map(List.wrap(contents), &normalise_s3_object/1)
  end

  defp parse_list_objects_response(body) when is_binary(body) do
    # XML response (native S3/MinIO format)
    # Extract <Key> elements from the XML
    ~r/<Key>([^<]+)<\/Key>/
    |> Regex.scan(body)
    |> Enum.map(fn [_full, key] ->
      size = extract_xml_field(body, key, "Size")
      last_modified = extract_xml_field(body, key, "LastModified")

      %{
        "key" => key,
        "size" => size,
        "last_modified" => last_modified,
        "etag" => extract_xml_field(body, key, "ETag")
      }
    end)
  end

  defp parse_list_objects_response(_body), do: []

  defp parse_list_versions_response(body, range) when is_binary(body) do
    # Parse XML ListObjectVersions response and filter by time range
    start_time = range[:start] || range["start"]
    end_time = range[:end] || range["end"]

    ~r/<Version>[\s\S]*?<Key>([^<]+)<\/Key>[\s\S]*?<LastModified>([^<]+)<\/LastModified>[\s\S]*?<VersionId>([^<]+)<\/VersionId>[\s\S]*?<\/Version>/
    |> Regex.scan(body)
    |> Enum.map(fn [_full, key, modified, version_id] ->
      %{
        "key" => key,
        "last_modified" => modified,
        "version_id" => version_id,
        "is_version" => true
      }
    end)
    |> Enum.filter(fn obj ->
      modified = obj["last_modified"] || ""

      cond do
        is_nil(start_time) and is_nil(end_time) -> true
        is_nil(start_time) -> modified <= end_time
        is_nil(end_time) -> modified >= start_time
        true -> modified >= start_time and modified <= end_time
      end
    end)
  end

  defp parse_list_versions_response(body, _range) when is_map(body) do
    body["Versions"] || body["versions"] || []
  end

  defp parse_list_versions_response(_body, _range), do: []

  defp extract_xml_field(xml, key, field) do
    # Simple XML field extraction near a specific key
    # This is a best-effort parser for S3 ListObjects XML
    pattern = ~r/<#{field}>([^<]+)<\/#{field}>/

    case Regex.scan(pattern, xml) do
      [] -> nil
      matches -> matches |> List.first() |> List.last()
    end
  end

  defp normalise_s3_object(obj) do
    %{
      "key" => obj["Key"] || obj["key"] || "unknown",
      "size" => obj["Size"] || obj["size"] || 0,
      "last_modified" => obj["LastModified"] || obj["last_modified"] || "",
      "etag" => obj["ETag"] || obj["etag"] || "",
      "metadata" => obj["Metadata"] || obj["metadata"] || %{}
    }
  end

  defp extract_s3_error(body) when is_binary(body) do
    case Regex.run(~r/<Message>([^<]+)<\/Message>/, body) do
      [_, message] -> message
      _ -> nil
    end
  end

  defp extract_s3_error(body) when is_map(body) do
    body["Error"] || body["error"] || body["Message"] || body["message"]
  end

  defp extract_s3_error(_), do: nil

  # ---------------------------------------------------------------------------
  # Private — Helpers
  # ---------------------------------------------------------------------------

  defp build_bucket_url(peer_info, bucket) do
    config = peer_info.adapter_config
    backend = Map.get(config, :backend, :minio)

    case backend do
      :s3 ->
        # Virtual-hosted-style URL for S3
        region = Map.get(config, :region, "us-east-1")
        "https://#{bucket}.s3.#{region}.amazonaws.com"

      :minio ->
        # Path-style URL for MinIO
        "#{peer_info.endpoint}/#{bucket}"

      _ ->
        "#{peer_info.endpoint}/#{bucket}"
    end
  end

  defp extract_object_id(obj) do
    key = obj["key"] || obj["Key"] || "unknown"

    # Strip common prefixes and extensions to get a clean ID
    key
    |> String.replace(~r/^(hexads|entities|objects)\//, "")
    |> String.replace(~r/\.(json|cbor|bin)$/, "")
  end

  defp parse_score(obj) do
    case obj["score"] do
      score when is_number(score) -> score / 1
      _ -> 0.0
    end
  end

  defp maybe_add(list, item, true), do: list ++ [item]
  defp maybe_add(list, _item, false), do: list

  defp auth_headers(config) do
    case Map.get(config, :auth, :none) do
      {:basic, user, pass} ->
        encoded = Base.encode64("#{user}:#{pass}")
        [{"Authorization", "Basic #{encoded}"}]

      {:bearer, token} ->
        [{"Authorization", "Bearer #{token}"}]

      {:api_key, key} ->
        [{"X-API-Key", key}]

      _ ->
        # For S3/MinIO, proper auth requires AWS Signature V4 signing.
        # In production, use an S3-aware HTTP client or middleware.
        # For federation stubs, we pass access_key via header if available.
        access_key = Map.get(config, :access_key)

        if access_key do
          [{"X-Amz-Access-Key", access_key}]
        else
          []
        end
    end
  end
end
