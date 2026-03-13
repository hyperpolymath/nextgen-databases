# SPDX-License-Identifier: PMPL-1.0-or-later
# FormBD-Geo and FormBD-Analytics Test Script

# Start the application
{:ok, _} = Application.ensure_all_started(:lith_http)

alias LithHttp.{Lithoglyph, Geo, Analytics}

IO.puts("\n=== FormBD-Geo and Analytics Test ===\n")

# ============================================================
# FormBD-Geo Tests
# ============================================================

IO.puts("=== Geo Tests ===\n")

# Test 1: Connect to database
IO.puts("Test 1: Connect to database...")
{:ok, db} = Lithoglyph.connect("/tmp/lith_geo_analytics_test")
IO.puts("  ✓ Database connected\n")

# Test 2: Validate Point geometry
IO.puts("Test 2: Validate Point geometry...")
point_geom = %{"type" => "Point", "coordinates" => [-122.4194, 37.7749]}
:ok = Geo.validate_geometry(point_geom)
IO.puts("  ✓ Point geometry valid\n")

# Test 3: Validate LineString geometry
IO.puts("Test 3: Validate LineString geometry...")
line_geom = %{"type" => "LineString", "coordinates" => [[-122.4, 37.7], [-122.5, 37.8]]}
:ok = Geo.validate_geometry(line_geom)
IO.puts("  ✓ LineString geometry valid\n")

# Test 4: Validate Polygon geometry
IO.puts("Test 4: Validate Polygon geometry...")
poly_geom = %{
  "type" => "Polygon",
  "coordinates" => [[[-122.5, 37.7], [-122.4, 37.7], [-122.4, 37.8], [-122.5, 37.8], [-122.5, 37.7]]]
}
:ok = Geo.validate_geometry(poly_geom)
IO.puts("  ✓ Polygon geometry valid\n")

# Test 5: Insert feature
IO.puts("Test 5: Insert geospatial feature...")
{:ok, %{feature_id: feat_id, block_id: _block_id}} =
  Geo.insert_feature(
    db,
    point_geom,
    %{"name" => "San Francisco", "population" => 873_965},
    %{"source" => "USGS", "confidence" => 0.95}
  )
IO.puts("  ✓ Feature inserted: #{feat_id}\n")

# Test 6: Query by bounding box
IO.puts("Test 6: Query by bounding box...")
{:ok, feature_collection} = Geo.query_by_bbox(db, {-123.0, 37.0, -122.0, 38.0}, %{})
IO.puts("  ✓ Query result: #{inspect(feature_collection["type"])}\n")

# Test 7: Get feature provenance
IO.puts("Test 7: Get feature provenance...")
{:ok, provenance} = Geo.get_feature_provenance(db, feat_id)
IO.puts("  ✓ Provenance chain length: #{length(provenance.provenance_chain)}\n")

# ============================================================
# FormBD-Analytics Tests
# ============================================================

IO.puts("=== Analytics Tests ===\n")

# Test 8: Validate time-series value
IO.puts("Test 8: Validate time-series value...")
:ok = Analytics.validate_value(72.5)
:ok = Analytics.validate_value(100)
{:error, _} = Analytics.validate_value("invalid")
IO.puts("  ✓ Value validation working\n")

# Test 9: Parse interval
IO.puts("Test 9: Parse interval...")
{:ok, 60} = Analytics.parse_interval("1m")
{:ok, 300} = Analytics.parse_interval("5m")
{:ok, 3600} = Analytics.parse_interval("1h")
{:ok, 86400} = Analytics.parse_interval("1d")
IO.puts("  ✓ Interval parsing working\n")

# Test 10: Insert time-series data
IO.puts("Test 10: Insert time-series data...")
timestamp = DateTime.utc_now()
{:ok, %{point_id: point_id, block_id: _block_id}} =
  Analytics.insert_timeseries(
    db,
    "sensor_temp_01",
    timestamp,
    72.5,
    %{"sensor_id" => "temp_01", "location" => "building_a"},
    %{"source" => "iot_gateway", "quality" => "calibrated"}
  )
IO.puts("  ✓ Point inserted: #{point_id}\n")

# Test 11: Query time-series
IO.puts("Test 11: Query time-series...")
start_time = DateTime.add(timestamp, -3600, :second)
end_time = DateTime.add(timestamp, 3600, :second)
{:ok, result} = Analytics.query_timeseries(db, "sensor_temp_01", start_time, end_time, :none, nil, 100)
IO.puts("  ✓ Query result: series_id = #{result.series_id}\n")

# Test 12: Query with aggregation
IO.puts("Test 12: Query with aggregation...")
{:ok, avg_result} = Analytics.query_timeseries(db, "sensor_temp_01", start_time, end_time, :avg, "5m", 100)
IO.puts("  ✓ Aggregation result: #{avg_result.aggregation}\n")

# Test 13: Get time-series provenance
IO.puts("Test 13: Get time-series provenance...")
{:ok, ts_provenance} = Analytics.get_timeseries_provenance(db, "sensor_temp_01")
IO.puts("  ✓ Provenance sources: #{inspect(ts_provenance.provenance_summary.sources)}\n")

# Test 14: Aggregate data points
IO.puts("Test 14: Aggregate data points...")
points = [
  %{value: 10.0},
  %{value: 20.0},
  %{value: 30.0}
]
20.0 = Analytics.aggregate(points, :avg)
10.0 = Analytics.aggregate(points, :min)
30.0 = Analytics.aggregate(points, :max)
60.0 = Analytics.aggregate(points, :sum)
3 = Analytics.aggregate(points, :count)
IO.puts("  ✓ All aggregations working\n")

# Test 15: Disconnect
IO.puts("Test 15: Disconnect...")
:ok = Lithoglyph.disconnect(db)
IO.puts("  ✓ Database disconnected\n")

IO.puts("=== All Geo and Analytics tests passed! ===\n")
