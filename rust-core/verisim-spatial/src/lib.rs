// SPDX-License-Identifier: PMPL-1.0-or-later
//! VeriSim Spatial Modality
//!
//! Provides geospatial indexing and querying capabilities for hexad entities.
//! Supports WGS84 (EPSG:4326) coordinates by default, with configurable SRID
//! for other coordinate reference systems.
//!
//! # Architecture
//!
//! - **Coordinates**: Latitude/longitude/altitude tuple in WGS84.
//! - **GeometryType**: Point, LineString, Polygon, MultiPoint, MultiPolygon.
//! - **SpatialData**: Full spatial description of an entity including
//!   coordinates, geometry type, SRID, and arbitrary properties.
//! - **SpatialStore** trait: Async storage with radius search, bounding box
//!   search, and k-nearest-neighbour queries.
//! - **InMemorySpatialStore**: Reference implementation using brute-force
//!   distance computation.  A production deployment would use an R-tree or
//!   similar spatial index.

use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::Arc;
use thiserror::Error;
use tokio::sync::RwLock;
use tracing::{debug, instrument};

/// Spatial-specific errors
#[derive(Error, Debug)]
pub enum SpatialError {
    /// Entity spatial data not found
    #[error("Spatial data not found for entity: {0}")]
    NotFound(String),

    /// Invalid coordinate values (out of WGS84 range, NaN, etc.)
    #[error("Invalid coordinates: {0}")]
    InvalidCoordinates(String),

    /// Spatial index error (R-tree corruption, etc.)
    #[error("Spatial index error: {0}")]
    IndexError(String),

    /// Generic I/O or storage error
    #[error("Spatial I/O error: {0}")]
    IoError(String),
}

/// A geographic coordinate in WGS84.
///
/// Latitude ranges from -90.0 to +90.0 (north positive).
/// Longitude ranges from -180.0 to +180.0 (east positive).
/// Altitude is optional, in metres above the WGS84 ellipsoid.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Coordinates {
    /// Latitude in decimal degrees (-90.0 to +90.0)
    pub latitude: f64,
    /// Longitude in decimal degrees (-180.0 to +180.0)
    pub longitude: f64,
    /// Altitude in metres above the WGS84 ellipsoid (optional)
    pub altitude: Option<f64>,
}

impl Coordinates {
    /// Create new coordinates, validating WGS84 range.
    pub fn new(latitude: f64, longitude: f64, altitude: Option<f64>) -> Result<Self, SpatialError> {
        if !(-90.0..=90.0).contains(&latitude) {
            return Err(SpatialError::InvalidCoordinates(format!(
                "Latitude {} out of range [-90, 90]",
                latitude
            )));
        }
        if !(-180.0..=180.0).contains(&longitude) {
            return Err(SpatialError::InvalidCoordinates(format!(
                "Longitude {} out of range [-180, 180]",
                longitude
            )));
        }
        if latitude.is_nan() || longitude.is_nan() {
            return Err(SpatialError::InvalidCoordinates(
                "Coordinates must not be NaN".to_string(),
            ));
        }
        Ok(Self {
            latitude,
            longitude,
            altitude,
        })
    }

    /// Create coordinates without validation (for internal / trusted use).
    pub fn new_unchecked(latitude: f64, longitude: f64, altitude: Option<f64>) -> Self {
        Self {
            latitude,
            longitude,
            altitude,
        }
    }
}

/// Supported geometry types.
///
/// Follows the OGC Simple Features specification naming.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, Hash)]
pub enum GeometryType {
    /// A single point in 2D or 3D space
    Point,
    /// An ordered sequence of points forming a line
    LineString,
    /// A closed ring of points forming a polygon
    Polygon,
    /// A collection of points
    MultiPoint,
    /// A collection of polygons
    MultiPolygon,
}

impl std::fmt::Display for GeometryType {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            GeometryType::Point => write!(f, "Point"),
            GeometryType::LineString => write!(f, "LineString"),
            GeometryType::Polygon => write!(f, "Polygon"),
            GeometryType::MultiPoint => write!(f, "MultiPoint"),
            GeometryType::MultiPolygon => write!(f, "MultiPolygon"),
        }
    }
}

/// Full spatial description of an entity.
///
/// The `coordinates` field holds the representative point (centroid for
/// complex geometries).  The `geometry_type` and `srid` describe the
/// coordinate reference context.  Arbitrary `properties` can hold extra
/// spatial metadata (e.g., address, region name, accuracy).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpatialData {
    /// Representative coordinates (centroid for complex geometries)
    pub coordinates: Coordinates,
    /// Type of geometry this entity represents
    pub geometry_type: GeometryType,
    /// Spatial Reference System Identifier (default: 4326 = WGS84)
    pub srid: u32,
    /// Arbitrary spatial properties (address, region, accuracy, etc.)
    pub properties: HashMap<String, String>,
}

impl SpatialData {
    /// Create spatial data for a point with default WGS84 SRID.
    pub fn point(latitude: f64, longitude: f64, altitude: Option<f64>) -> Result<Self, SpatialError> {
        Ok(Self {
            coordinates: Coordinates::new(latitude, longitude, altitude)?,
            geometry_type: GeometryType::Point,
            srid: 4326,
            properties: HashMap::new(),
        })
    }

    /// Create spatial data with a specified geometry type and SRID.
    pub fn with_geometry(
        coordinates: Coordinates,
        geometry_type: GeometryType,
        srid: u32,
    ) -> Self {
        Self {
            coordinates,
            geometry_type,
            srid,
            properties: HashMap::new(),
        }
    }

    /// Add a property to this spatial data.
    pub fn with_property(mut self, key: impl Into<String>, value: impl Into<String>) -> Self {
        self.properties.insert(key.into(), value.into());
        self
    }
}

/// A bounding box for spatial queries.
///
/// Defined by the south-west (min) and north-east (max) corners.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BoundingBox {
    /// Minimum latitude (south)
    pub min_lat: f64,
    /// Minimum longitude (west)
    pub min_lon: f64,
    /// Maximum latitude (north)
    pub max_lat: f64,
    /// Maximum longitude (east)
    pub max_lon: f64,
}

/// Result of a spatial search, pairing entity ID with its data and distance.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SpatialSearchResult {
    /// Entity ID
    pub entity_id: String,
    /// The entity's spatial data
    pub data: SpatialData,
    /// Distance from the query point in kilometres
    pub distance_km: f64,
}

/// Async trait for spatial storage backends.
///
/// Implementations must be `Send + Sync` for safe sharing across Tokio tasks.
#[async_trait]
pub trait SpatialStore: Send + Sync {
    /// Index (upsert) spatial data for an entity.
    async fn index(&self, entity_id: &str, data: SpatialData) -> Result<(), SpatialError>;

    /// Get spatial data for an entity.
    async fn get(&self, entity_id: &str) -> Result<Option<SpatialData>, SpatialError>;

    /// Delete spatial data for an entity.
    async fn delete(&self, entity_id: &str) -> Result<(), SpatialError>;

    /// Search for entities within a given radius (km) of a point.
    async fn search_radius(
        &self,
        center: &Coordinates,
        radius_km: f64,
        limit: usize,
    ) -> Result<Vec<SpatialSearchResult>, SpatialError>;

    /// Search for entities within a bounding box.
    async fn search_within(
        &self,
        bounds: &BoundingBox,
        limit: usize,
    ) -> Result<Vec<SpatialSearchResult>, SpatialError>;

    /// Find the k nearest entities to a given point.
    async fn nearest(
        &self,
        point: &Coordinates,
        k: usize,
    ) -> Result<Vec<SpatialSearchResult>, SpatialError>;
}

/// Approximate distance in kilometres between two WGS84 points using the
/// Haversine formula.
///
/// This is accurate to within ~0.5% for most distances on Earth.
pub fn haversine_distance(a: &Coordinates, b: &Coordinates) -> f64 {
    const EARTH_RADIUS_KM: f64 = 6371.0;

    let lat1 = a.latitude.to_radians();
    let lat2 = b.latitude.to_radians();
    let dlat = (b.latitude - a.latitude).to_radians();
    let dlon = (b.longitude - a.longitude).to_radians();

    let h = (dlat / 2.0).sin().powi(2)
        + lat1.cos() * lat2.cos() * (dlon / 2.0).sin().powi(2);

    let c = 2.0 * h.sqrt().asin();
    EARTH_RADIUS_KM * c
}

/// In-memory implementation of [`SpatialStore`].
///
/// Uses brute-force distance computation for searches.  Suitable for
/// development, testing, and small-to-medium datasets.  A production
/// deployment should use an R-tree or similar spatial index.
pub struct InMemorySpatialStore {
    data: Arc<RwLock<HashMap<String, SpatialData>>>,
}

impl InMemorySpatialStore {
    /// Create a new empty in-memory spatial store.
    pub fn new() -> Self {
        Self {
            data: Arc::new(RwLock::new(HashMap::new())),
        }
    }
}

impl Default for InMemorySpatialStore {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl SpatialStore for InMemorySpatialStore {
    #[instrument(skip(self, data))]
    async fn index(&self, entity_id: &str, data: SpatialData) -> Result<(), SpatialError> {
        // Validate coordinates even if SpatialData was constructed directly
        if !(-90.0..=90.0).contains(&data.coordinates.latitude)
            || !(-180.0..=180.0).contains(&data.coordinates.longitude)
        {
            return Err(SpatialError::InvalidCoordinates(format!(
                "lat={}, lon={} out of WGS84 range",
                data.coordinates.latitude, data.coordinates.longitude
            )));
        }

        let mut store = self.data.write().await;
        store.insert(entity_id.to_string(), data);
        debug!(entity_id = %entity_id, "Spatial data indexed");
        Ok(())
    }

    async fn get(&self, entity_id: &str) -> Result<Option<SpatialData>, SpatialError> {
        let store = self.data.read().await;
        Ok(store.get(entity_id).cloned())
    }

    async fn delete(&self, entity_id: &str) -> Result<(), SpatialError> {
        let mut store = self.data.write().await;
        store.remove(entity_id);
        Ok(())
    }

    async fn search_radius(
        &self,
        center: &Coordinates,
        radius_km: f64,
        limit: usize,
    ) -> Result<Vec<SpatialSearchResult>, SpatialError> {
        let store = self.data.read().await;
        let mut results: Vec<SpatialSearchResult> = store
            .iter()
            .filter_map(|(id, data)| {
                let dist = haversine_distance(center, &data.coordinates);
                if dist <= radius_km {
                    Some(SpatialSearchResult {
                        entity_id: id.clone(),
                        data: data.clone(),
                        distance_km: dist,
                    })
                } else {
                    None
                }
            })
            .collect();

        // Sort by distance ascending
        results.sort_by(|a, b| {
            a.distance_km
                .partial_cmp(&b.distance_km)
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        results.truncate(limit);
        Ok(results)
    }

    async fn search_within(
        &self,
        bounds: &BoundingBox,
        limit: usize,
    ) -> Result<Vec<SpatialSearchResult>, SpatialError> {
        let store = self.data.read().await;
        // Compute bounding box center for distance calculation
        let center = Coordinates::new_unchecked(
            (bounds.min_lat + bounds.max_lat) / 2.0,
            (bounds.min_lon + bounds.max_lon) / 2.0,
            None,
        );

        let mut results: Vec<SpatialSearchResult> = store
            .iter()
            .filter_map(|(id, data)| {
                let lat = data.coordinates.latitude;
                let lon = data.coordinates.longitude;
                if lat >= bounds.min_lat
                    && lat <= bounds.max_lat
                    && lon >= bounds.min_lon
                    && lon <= bounds.max_lon
                {
                    Some(SpatialSearchResult {
                        entity_id: id.clone(),
                        data: data.clone(),
                        distance_km: haversine_distance(&center, &data.coordinates),
                    })
                } else {
                    None
                }
            })
            .collect();

        results.sort_by(|a, b| {
            a.distance_km
                .partial_cmp(&b.distance_km)
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        results.truncate(limit);
        Ok(results)
    }

    async fn nearest(
        &self,
        point: &Coordinates,
        k: usize,
    ) -> Result<Vec<SpatialSearchResult>, SpatialError> {
        let store = self.data.read().await;
        let mut results: Vec<SpatialSearchResult> = store
            .iter()
            .map(|(id, data)| SpatialSearchResult {
                entity_id: id.clone(),
                data: data.clone(),
                distance_km: haversine_distance(point, &data.coordinates),
            })
            .collect();

        results.sort_by(|a, b| {
            a.distance_km
                .partial_cmp(&b.distance_km)
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        results.truncate(k);
        Ok(results)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_coordinates_valid() {
        let coords = Coordinates::new(51.5074, -0.1278, None);
        assert!(coords.is_ok(), "London coordinates should be valid");
    }

    #[test]
    fn test_coordinates_invalid_latitude() {
        let coords = Coordinates::new(91.0, 0.0, None);
        assert!(matches!(coords, Err(SpatialError::InvalidCoordinates(_))));
    }

    #[test]
    fn test_coordinates_invalid_longitude() {
        let coords = Coordinates::new(0.0, 181.0, None);
        assert!(matches!(coords, Err(SpatialError::InvalidCoordinates(_))));
    }

    #[test]
    fn test_coordinates_nan() {
        let coords = Coordinates::new(f64::NAN, 0.0, None);
        assert!(matches!(coords, Err(SpatialError::InvalidCoordinates(_))));
    }

    #[test]
    fn test_haversine_same_point() {
        let a = Coordinates::new_unchecked(51.5074, -0.1278, None);
        let dist = haversine_distance(&a, &a);
        assert!(dist < 0.001, "Same point distance should be ~0, got {}", dist);
    }

    #[test]
    fn test_haversine_london_to_paris() {
        let london = Coordinates::new_unchecked(51.5074, -0.1278, None);
        let paris = Coordinates::new_unchecked(48.8566, 2.3522, None);
        let dist = haversine_distance(&london, &paris);
        // London to Paris is ~344 km
        assert!(
            (330.0..360.0).contains(&dist),
            "London-Paris distance should be ~344 km, got {} km",
            dist
        );
    }

    #[test]
    fn test_haversine_antipodal() {
        let north = Coordinates::new_unchecked(0.0, 0.0, None);
        let south = Coordinates::new_unchecked(0.0, 180.0, None);
        let dist = haversine_distance(&north, &south);
        // Half circumference ~20015 km
        assert!(
            dist > 19000.0 && dist < 21000.0,
            "Antipodal distance should be ~20015 km, got {} km",
            dist
        );
    }

    #[test]
    fn test_spatial_data_point() {
        let data = SpatialData::point(51.5074, -0.1278, None).unwrap();
        assert_eq!(data.geometry_type, GeometryType::Point);
        assert_eq!(data.srid, 4326);
    }

    #[tokio::test]
    async fn test_in_memory_store_index_and_get() {
        let store = InMemorySpatialStore::new();
        let data = SpatialData::point(51.5074, -0.1278, None).unwrap();

        store.index("entity-1", data.clone()).await.unwrap();
        let retrieved = store.get("entity-1").await.unwrap();
        assert!(retrieved.is_some());
        assert_eq!(retrieved.unwrap().coordinates.latitude, 51.5074);
    }

    #[tokio::test]
    async fn test_in_memory_store_delete() {
        let store = InMemorySpatialStore::new();
        let data = SpatialData::point(51.5074, -0.1278, None).unwrap();

        store.index("entity-1", data).await.unwrap();
        store.delete("entity-1").await.unwrap();
        assert!(store.get("entity-1").await.unwrap().is_none());
    }

    #[tokio::test]
    async fn test_in_memory_store_radius_search() {
        let store = InMemorySpatialStore::new();

        // London
        store
            .index("london", SpatialData::point(51.5074, -0.1278, None).unwrap())
            .await
            .unwrap();
        // Paris
        store
            .index("paris", SpatialData::point(48.8566, 2.3522, None).unwrap())
            .await
            .unwrap();
        // New York
        store
            .index("nyc", SpatialData::point(40.7128, -74.0060, None).unwrap())
            .await
            .unwrap();

        // Search within 500 km of London — should find London and Paris
        let center = Coordinates::new(51.5074, -0.1278, None).unwrap();
        let results = store.search_radius(&center, 500.0, 10).await.unwrap();

        assert_eq!(results.len(), 2, "Should find London and Paris within 500km");
        assert_eq!(results[0].entity_id, "london", "London should be closest");
    }

    #[tokio::test]
    async fn test_in_memory_store_bounding_box() {
        let store = InMemorySpatialStore::new();

        // London
        store
            .index("london", SpatialData::point(51.5074, -0.1278, None).unwrap())
            .await
            .unwrap();
        // Paris
        store
            .index("paris", SpatialData::point(48.8566, 2.3522, None).unwrap())
            .await
            .unwrap();
        // New York
        store
            .index("nyc", SpatialData::point(40.7128, -74.0060, None).unwrap())
            .await
            .unwrap();

        // Bounding box around Western Europe
        let bounds = BoundingBox {
            min_lat: 45.0,
            min_lon: -5.0,
            max_lat: 55.0,
            max_lon: 10.0,
        };

        let results = store.search_within(&bounds, 10).await.unwrap();
        assert_eq!(results.len(), 2, "Should find London and Paris in W. Europe box");
    }

    #[tokio::test]
    async fn test_in_memory_store_nearest() {
        let store = InMemorySpatialStore::new();

        store
            .index("london", SpatialData::point(51.5074, -0.1278, None).unwrap())
            .await
            .unwrap();
        store
            .index("paris", SpatialData::point(48.8566, 2.3522, None).unwrap())
            .await
            .unwrap();
        store
            .index("nyc", SpatialData::point(40.7128, -74.0060, None).unwrap())
            .await
            .unwrap();

        // k-nearest to London (k=2) — should return London then Paris
        let point = Coordinates::new(51.5074, -0.1278, None).unwrap();
        let results = store.nearest(&point, 2).await.unwrap();

        assert_eq!(results.len(), 2);
        assert_eq!(results[0].entity_id, "london");
        assert_eq!(results[1].entity_id, "paris");
    }

    #[tokio::test]
    async fn test_in_memory_store_invalid_coordinates() {
        let store = InMemorySpatialStore::new();
        let data = SpatialData {
            coordinates: Coordinates::new_unchecked(999.0, 0.0, None),
            geometry_type: GeometryType::Point,
            srid: 4326,
            properties: HashMap::new(),
        };

        let result = store.index("bad", data).await;
        assert!(matches!(result, Err(SpatialError::InvalidCoordinates(_))));
    }
}
