defmodule QuandleDBNifLiveIntegrationTest do
  use ExUnit.Case, async: false

  @base_url System.get_env("QDB_LIVE_TEST_BASE_URL")

  if @base_url && @base_url != "" do
    @knot_name System.get_env("QDB_LIVE_TEST_KNOT") || "3_1"

    setup_all do
      old_mode = System.get_env("QDB_NIF_MODE")
      old_api = System.get_env("QDB_API_BASE_URL")

      System.put_env("QDB_NIF_MODE", "live")
      System.put_env("QDB_API_BASE_URL", @base_url)

      on_exit(fn ->
        restore_env("QDB_NIF_MODE", old_mode)
        restore_env("QDB_API_BASE_URL", old_api)
      end)

      :ok
    end

    test "semantic_lookup matches semantic API for configured knot" do
      {:ok, nif_payload} = QuandleDBNif.semantic_lookup(@knot_name)
      api_payload = get_json("#{@base_url}/api/semantic/#{@knot_name}")

      assert nif_payload[:name] == api_payload["knot_name"]
      assert nif_payload[:descriptor_version] == api_payload["descriptor_version"]
      assert nif_payload[:descriptor_hash] == api_payload["descriptor_hash"]
      assert nif_payload[:quandle_key] == api_payload["quandle_key"]
      assert nif_payload[:crossing_number] == api_payload["crossing_number"]
      assert nif_payload[:writhe] == api_payload["writhe"]
      assert nif_payload[:determinant] == api_payload["determinant"]
      assert nif_payload[:signature] == api_payload["signature"]
      assert nif_payload[:quandle_generator_count] == api_payload["quandle_generator_count"]
      assert nif_payload[:quandle_relation_count] == api_payload["quandle_relation_count"]
      assert nif_payload[:colouring_count_3] == api_payload["colouring_count_3"]
      assert nif_payload[:colouring_count_5] == api_payload["colouring_count_5"]
    end

    test "semantic_equivalents matches API for configured knot" do
      {:ok, nif_payload} = QuandleDBNif.semantic_equivalents(@knot_name)
      api_payload = get_json("#{@base_url}/api/semantic-equivalents/#{@knot_name}")

      assert nif_payload[:name] == api_payload["name"]
      assert nif_payload[:descriptor_hash] == api_payload["descriptor_hash"]
      assert nif_payload[:quandle_key] == api_payload["quandle_key"]
      assert nif_payload[:strong_candidates] == api_payload["strong_candidates"]
      assert nif_payload[:weak_candidates] == api_payload["weak_candidates"]
      assert nif_payload[:combined_candidates] == api_payload["combined_candidates"]
      assert nif_payload[:count] == api_payload["count"]
    end

    defp get_json(url) do
      {body, 0} = System.cmd("curl", ["-fsS", url])
      :json.decode(body)
    end

    defp restore_env(name, nil), do: System.delete_env(name)
    defp restore_env(name, value), do: System.put_env(name, value)
  else
    test "live integration tests disabled without QDB_LIVE_TEST_BASE_URL" do
      assert true
    end
  end
end
