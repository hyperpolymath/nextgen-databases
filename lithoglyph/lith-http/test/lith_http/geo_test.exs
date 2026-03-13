# SPDX-License-Identifier: PMPL-1.0-or-later
# Copyright (c) 2026 Jonathan D.A. Jewell (@hyperpolymath) <j.d.a.jewell@open.ac.uk>

defmodule LithHttp.GeoTest do
  @moduledoc """
  Tests for LithHttp.Geo module.
  Covers GeoJSON geometry validation, bounding box intersection,
  and provenance retrieval (PoC stub).
  """

  use ExUnit.Case, async: true

  alias LithHttp.Geo

  # ============================================================
  # Geometry validation
  # ============================================================

  describe "validate_geometry/1" do
    test "accepts valid Point geometry" do
      assert :ok = Geo.validate_geometry(%{"type" => "Point", "coordinates" => [1.0, 2.0]})
    end

    test "accepts valid LineString geometry" do
      coords = [[0.0, 0.0], [1.0, 1.0]]
      assert :ok = Geo.validate_geometry(%{"type" => "LineString", "coordinates" => coords})
    end

    test "accepts valid Polygon geometry" do
      ring = [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0], [0.0, 0.0]]
      assert :ok = Geo.validate_geometry(%{"type" => "Polygon", "coordinates" => [ring]})
    end

    test "accepts MultiPoint geometry" do
      assert :ok = Geo.validate_geometry(%{
        "type" => "MultiPoint",
        "coordinates" => [[1.0, 2.0], [3.0, 4.0]]
      })
    end

    test "accepts MultiLineString geometry" do
      assert :ok = Geo.validate_geometry(%{
        "type" => "MultiLineString",
        "coordinates" => [[[0.0, 0.0], [1.0, 1.0]]]
      })
    end

    test "accepts MultiPolygon geometry" do
      ring = [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 0.0]]
      assert :ok = Geo.validate_geometry(%{
        "type" => "MultiPolygon",
        "coordinates" => [[ring]]
      })
    end

    test "rejects geometry without type" do
      assert {:error, _} = Geo.validate_geometry(%{"coordinates" => [1.0, 2.0]})
    end

    test "rejects geometry without coordinates" do
      assert {:error, _} = Geo.validate_geometry(%{"type" => "Point"})
    end

    test "rejects completely empty map" do
      assert {:error, _} = Geo.validate_geometry(%{})
    end

    test "rejects non-map input" do
      assert {:error, _} = Geo.validate_geometry("not a map")
      assert {:error, _} = Geo.validate_geometry(nil)
      assert {:error, _} = Geo.validate_geometry(42)
    end

    test "rejects unsupported geometry type" do
      assert {:error, _} = Geo.validate_geometry(%{
        "type" => "GeometryCollection",
        "coordinates" => []
      })
    end

    test "rejects Point with wrong number of coordinates" do
      assert {:error, _} = Geo.validate_geometry(%{
        "type" => "Point",
        "coordinates" => [1.0]
      })
      assert {:error, _} = Geo.validate_geometry(%{
        "type" => "Point",
        "coordinates" => [1.0, 2.0, 3.0]
      })
    end

    test "rejects Point with non-numeric coordinates" do
      assert {:error, _} = Geo.validate_geometry(%{
        "type" => "Point",
        "coordinates" => ["a", "b"]
      })
    end

    test "rejects LineString with fewer than 2 positions" do
      assert {:error, _} = Geo.validate_geometry(%{
        "type" => "LineString",
        "coordinates" => [[0.0, 0.0]]
      })
    end

    test "rejects Polygon with no rings" do
      assert {:error, _} = Geo.validate_geometry(%{
        "type" => "Polygon",
        "coordinates" => []
      })
    end

    test "accepts Point with integer coordinates" do
      assert :ok = Geo.validate_geometry(%{"type" => "Point", "coordinates" => [1, 2]})
    end
  end

  # ============================================================
  # Bounding box intersection
  # ============================================================

  describe "bbox_intersects?/2" do
    test "detects intersection of overlapping bboxes" do
      feature = %{
        "geometry" => %{"type" => "Point", "coordinates" => [5.0, 5.0]}
      }
      bbox = {0.0, 0.0, 10.0, 10.0}
      assert Geo.bbox_intersects?(feature, bbox)
    end

    test "detects non-intersection when point is outside bbox" do
      feature = %{
        "geometry" => %{"type" => "Point", "coordinates" => [20.0, 20.0]}
      }
      bbox = {0.0, 0.0, 10.0, 10.0}
      refute Geo.bbox_intersects?(feature, bbox)
    end

    test "detects edge intersection (point on bbox boundary)" do
      feature = %{
        "geometry" => %{"type" => "Point", "coordinates" => [10.0, 10.0]}
      }
      bbox = {0.0, 0.0, 10.0, 10.0}
      assert Geo.bbox_intersects?(feature, bbox)
    end

    test "returns false for feature without geometry" do
      refute Geo.bbox_intersects?(%{}, {0.0, 0.0, 10.0, 10.0})
    end

    test "returns false for non-map input" do
      refute Geo.bbox_intersects?("not a feature", {0.0, 0.0, 10.0, 10.0})
    end

    test "handles LineString bounding box" do
      feature = %{
        "geometry" => %{
          "type" => "LineString",
          "coordinates" => [[2.0, 2.0], [8.0, 8.0]]
        }
      }
      # Overlapping bbox
      assert Geo.bbox_intersects?(feature, {0.0, 0.0, 5.0, 5.0})
      # Non-overlapping bbox
      refute Geo.bbox_intersects?(feature, {20.0, 20.0, 30.0, 30.0})
    end

    test "handles Polygon bounding box" do
      ring = [[1.0, 1.0], [5.0, 1.0], [5.0, 5.0], [1.0, 5.0], [1.0, 1.0]]
      feature = %{
        "geometry" => %{
          "type" => "Polygon",
          "coordinates" => [ring]
        }
      }
      assert Geo.bbox_intersects?(feature, {0.0, 0.0, 3.0, 3.0})
      refute Geo.bbox_intersects?(feature, {10.0, 10.0, 20.0, 20.0})
    end
  end

  # ============================================================
  # Feature provenance (PoC stub)
  # ============================================================

  describe "get_feature_provenance/2" do
    test "returns provenance chain for any feature_id" do
      assert {:ok, result} = Geo.get_feature_provenance(make_ref(), "feat_abc123")
      assert result.feature_id == "feat_abc123"
      assert is_list(result.provenance_chain)
      assert length(result.provenance_chain) > 0

      chain_entry = hd(result.provenance_chain)
      assert is_binary(chain_entry.block_id)
      assert is_binary(chain_entry.timestamp)
      assert chain_entry.source == "insert"
      assert chain_entry.operation == "create"
    end
  end

  # ============================================================
  # Geometry query stub
  # ============================================================

  describe "query_by_geometry/3" do
    test "returns empty FeatureCollection (PoC stub)" do
      geometry = %{"type" => "Point", "coordinates" => [0.0, 0.0]}
      assert {:ok, result} = Geo.query_by_geometry(make_ref(), geometry, %{})
      assert result.type == "FeatureCollection"
      assert result.features == []
    end
  end
end
