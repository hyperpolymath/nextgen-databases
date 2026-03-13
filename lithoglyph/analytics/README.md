# Lith Advanced Analytics

Advanced analytics features for Lith including aggregations, time series analysis, window functions, and visualization exports.

## Features

| Feature | File | Description |
|---------|------|-------------|
| Aggregations | `Lith_Analytics_Aggregations.res` | Statistical aggregations |
| Time Series | `Lith_Analytics_TimeSeries.res` | Time-based analysis |
| Window Functions | `Lith_Analytics_Window.res` | SQL-style windows |
| Export | `Lith_Analytics_Export.res` | Visualization exports |

## Aggregations

Statistical aggregation functions for data analysis.

```rescript
// Basic aggregations
let values = [1.0, 2.0, 3.0, 4.0, 5.0]
let total = sum(values)         // 15.0
let average = avg(values)       // 3.0
let minimum = minValue(values)  // Some(1.0)
let maximum = maxValue(values)  // Some(5.0)
let mid = median(values)        // Some(3.0)
let sd = stddev(values)         // 1.414...
let p95 = percentile(values, 95.0) // 4.8

// Group by with aggregations
let results = groupBy(
  documents,
  ["category", "region"],
  [(Sum, "amount"), (Avg, "price"), (Count, "id")]
)
```

### Supported Aggregations

| Function | Description |
|----------|-------------|
| `Count` | Count of values |
| `Sum` | Sum of numeric values |
| `Avg` | Arithmetic mean |
| `Min` | Minimum value |
| `Max` | Maximum value |
| `Median` | Median (50th percentile) |
| `Stddev` | Standard deviation |
| `Variance` | Variance |
| `Percentile(n)` | nth percentile |
| `CountDistinct` | Count of unique values |

## Time Series Analysis

Time-based data analysis and trend detection.

```rescript
// Create time series
let points = [
  {timestamp: 1704067200000.0, value: 100.0, metadata: None},
  {timestamp: 1704153600000.0, value: 110.0, metadata: None},
  {timestamp: 1704240000000.0, value: 105.0, metadata: None},
]

let series = createTimeSeries("sales", "amount", points, Day)

// Analyze trend
let trend = analyzeTrend(series)
// {direction: Increasing, slope: 2.5, rSquared: 0.92, changePercent: 5.0}

// Moving average
let ma = movingAverage(series, 7) // 7-day moving average

// Anomaly detection
let anomalies = detectAnomalies(series, 2.0) // 2 standard deviations
```

### Time Granularities

| Granularity | Description |
|-------------|-------------|
| `Second` | Per-second buckets |
| `Minute` | Per-minute buckets |
| `Hour` | Per-hour buckets |
| `Day` | Per-day buckets |
| `Week` | Per-week buckets |
| `Month` | Per-month buckets |
| `Quarter` | Per-quarter buckets |
| `Year` | Per-year buckets |

### Trend Directions

| Direction | Meaning |
|-----------|---------|
| `Increasing` | Positive trend (R² > 0.3, slope > 0.01) |
| `Decreasing` | Negative trend (R² > 0.3, slope < -0.01) |
| `Stable` | No significant trend |
| `Volatile` | High variance (R² < 0.3) |

## Window Functions

SQL-style window functions for advanced analytics.

```rescript
// Define window specification
let spec = {
  partitionBy: ["department"],
  orderBy: [("salary", false)], // descending
  frameType: Rows,
  frameStart: UnboundedPreceding,
  frameEnd: CurrentRow,
}

// Apply window function
let results = execute(employees, Rank, spec)
// Returns rank within each department

// Cumulative sum
let cumSum = execute(sales, CumulativeSum("amount"), {
  ...defaultWindowSpec,
  orderBy: [("date", true)],
})

// Lead/Lag for comparison
let yoyGrowth = execute(revenue, Lag("amount", 12, Some(0.0)), {
  ...defaultWindowSpec,
  orderBy: [("month", true)],
})
```

### Available Window Functions

| Function | Description |
|----------|-------------|
| `RowNumber` | Sequential row number |
| `Rank` | Rank with gaps |
| `DenseRank` | Rank without gaps |
| `Ntile(n)` | Divide into n buckets |
| `Lag(field, n, default)` | Value n rows before |
| `Lead(field, n, default)` | Value n rows after |
| `FirstValue(field)` | First value in frame |
| `LastValue(field)` | Last value in frame |
| `NthValue(field, n)` | nth value in frame |
| `CumulativeSum(field)` | Running total |
| `RunningAvg(field)` | Running average |
| `PercentRank` | Relative rank (0-1) |

## Export

Data export for visualization and reporting.

```rescript
// Export to CSV
let csv = export(data, {...defaultOptions, format: CSV})

// Export for Chart.js
let chartConfig = {
  chartType: Line,
  title: "Monthly Sales",
  xAxis: "month",
  yAxis: "amount",
  series: ["actual", "forecast"],
  colors: Some(["#3b82f6", "#ef4444"]),
  legend: true,
}
let chartData = export(data, {
  ...defaultOptions,
  format: ChartJS,
  chartConfig: Some(chartConfig),
})

// Export for Vega-Lite
let vegaSpec = export(data, {
  ...defaultOptions,
  format: Vega,
  chartConfig: Some({...chartConfig, chartType: Bar}),
})

// Export as table data
let tableData = export(data, {...defaultOptions, format: TableData})
```

### Export Formats

| Format | Description | Use Case |
|--------|-------------|----------|
| `CSV` | Comma-separated values | Spreadsheets |
| `JSON` | JSON array | APIs |
| `ChartJS` | Chart.js config | Web charts |
| `D3` | D3-compatible data | Custom viz |
| `Vega` | Vega-Lite spec | Declarative charts |
| `TableData` | Columns + rows | Data tables |

### Chart Types

| Type | Description |
|------|-------------|
| `Line` | Line chart |
| `Bar` | Bar chart |
| `Pie` | Pie chart |
| `Scatter` | Scatter plot |
| `Area` | Area chart |
| `Histogram` | Histogram |
| `Heatmap` | Heatmap |

## Architecture

```
analytics/
├── README.md
└── src/
    ├── Lith_Analytics_Aggregations.res  # Statistical aggregations
    ├── Lith_Analytics_TimeSeries.res    # Time series analysis
    ├── Lith_Analytics_Window.res        # Window functions
    └── Lith_Analytics_Export.res        # Visualization exports
```

## Use Cases

### Sales Analytics

```rescript
// Monthly sales by region
let monthlySales = groupBy(
  orders,
  ["region", "month"],
  [(Sum, "amount"), (Count, "id"), (Avg, "amount")]
)

// Sales trend
let series = createTimeSeries("sales", "amount", salesData, Month)
let trend = analyzeTrend(series)
```

### Financial Analysis

```rescript
// Year-over-year comparison
let yoyResults = execute(revenue, Lag("amount", 12, None), {
  partitionBy: ["product"],
  orderBy: [("month", true)],
  frameType: Rows,
  frameStart: UnboundedPreceding,
  frameEnd: CurrentRow,
})

// Moving average for smoothing
let ma20 = movingAverage(stockPrices, 20)
```

### User Analytics

```rescript
// Cohort analysis
let cohorts = groupBy(
  users,
  ["signup_month", "activity_month"],
  [(CountDistinct, "user_id")]
)

// Percentile rankings
let userRanks = execute(users, PercentRank, {
  partitionBy: ["segment"],
  orderBy: [("engagement_score", false)],
  ...defaultWindowSpec,
})
```

## License

PMPL-1.0-or-later
