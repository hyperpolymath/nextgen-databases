// SPDX-License-Identifier: PMPL-1.0-or-later

/**
 * Lith Analytics Export
 *
 * Data export for visualization and reporting
 */

/** Export format */
type exportFormat =
  | CSV
  | JSON
  | ChartJS
  | D3
  | Vega
  | TableData

/** Chart type */
type chartType =
  | Line
  | Bar
  | Pie
  | Scatter
  | Area
  | Histogram
  | Heatmap

/** Chart configuration */
type chartConfig = {
  chartType: chartType,
  title: string,
  xAxis: string,
  yAxis: string,
  series: array<string>,
  colors: option<array<string>>,
  legend: bool,
}

/** Export options */
type exportOptions = {
  format: exportFormat,
  chartConfig: option<chartConfig>,
  includeHeaders: bool,
  dateFormat: string,
  decimalPlaces: int,
}

/** Default export options */
let defaultOptions: exportOptions = {
  format: JSON,
  chartConfig: None,
  includeHeaders: true,
  dateFormat: "ISO",
  decimalPlaces: 2,
}

/** Format number with decimal places */
let formatNumber = (n: float, decimals: int): string => {
  let multiplier = Js.Math.pow_float(~base=10.0, ~exp=Int.toFloat(decimals))
  Float.toString(Js.Math.round(n *. multiplier) /. multiplier)
}

/** Export to CSV */
let toCSV = (
  data: array<Js.Dict.t<Js.Json.t>>,
  options: exportOptions,
): string => {
  if Array.length(data) == 0 {
    ""
  } else {
    let lines: array<string> = []

    // Get headers from first row
    let headers = switch data->Array.get(0) {
    | Some(row) => Js.Dict.keys(row)
    | None => []
    }

    // Add header line
    if options.includeHeaders {
      lines->Array.push(headers->Array.join(","))->ignore
    }

    // Add data lines
    data->Array.forEach(row => {
      let values = headers->Array.map(h => {
        switch Js.Dict.get(row, h) {
        | Some(v) =>
          switch Js.Json.classify(v) {
          | JSONString(s) =>
            if String.includes(s, ",") || String.includes(s, "\"") {
              `"${String.replaceAll(s, "\"", "\"\"")}"`
            } else {
              s
            }
          | JSONNumber(n) => formatNumber(n, options.decimalPlaces)
          | JSONTrue => "true"
          | JSONFalse => "false"
          | JSONNull => ""
          | JSONObject(_) | JSONArray(_) => Js.Json.stringify(v)
          }
        | None => ""
        }
      })
      lines->Array.push(values->Array.join(","))->ignore
    })

    lines->Array.join("\n")
  }
}

/** Export to Chart.js format */
let toChartJS = (
  data: array<Js.Dict.t<Js.Json.t>>,
  config: chartConfig,
): Js.Json.t => {
  // Extract labels (x-axis values)
  let labels = data->Array.filterMap(row =>
    switch Js.Dict.get(row, config.xAxis) {
    | Some(v) => Some(Js.Json.stringify(v))
    | None => None
    }
  )

  // Extract datasets
  let datasets = config.series->Array.mapWithIndex((series, i) => {
    let values = data->Array.filterMap(row =>
      switch Js.Dict.get(row, series) {
      | Some(v) =>
        switch Js.Json.classify(v) {
        | JSONNumber(n) => Some(n)
        | _ => None
        }
      | None => None
      }
    )

    let color = switch config.colors {
    | Some(colors) => colors->Array.get(mod(i, Array.length(colors)))->Option.getOr("#000000")
    | None => "#000000"
    }

    let obj = Js.Dict.empty()
    Js.Dict.set(obj, "label", Js.Json.string(series))
    Js.Dict.set(obj, "data", Js.Json.array(values->Array.map(Js.Json.number)))
    Js.Dict.set(obj, "borderColor", Js.Json.string(color))
    Js.Dict.set(obj, "backgroundColor", Js.Json.string(color))
    Js.Json.object_(obj)
  })

  let chartTypeStr = switch config.chartType {
  | Line => "line"
  | Bar => "bar"
  | Pie => "pie"
  | Scatter => "scatter"
  | Area => "line"
  | Histogram => "bar"
  | Heatmap => "scatter"
  }

  let result = Js.Dict.empty()
  Js.Dict.set(result, "type", Js.Json.string(chartTypeStr))

  let dataObj = Js.Dict.empty()
  Js.Dict.set(dataObj, "labels", Js.Json.array(labels->Array.map(Js.Json.string)))
  Js.Dict.set(dataObj, "datasets", Js.Json.array(datasets))
  Js.Dict.set(result, "data", Js.Json.object_(dataObj))

  let optionsObj = Js.Dict.empty()
  let pluginsObj = Js.Dict.empty()
  let titleObj = Js.Dict.empty()
  Js.Dict.set(titleObj, "display", Js.Json.boolean(true))
  Js.Dict.set(titleObj, "text", Js.Json.string(config.title))
  Js.Dict.set(pluginsObj, "title", Js.Json.object_(titleObj))
  let legendObj = Js.Dict.empty()
  Js.Dict.set(legendObj, "display", Js.Json.boolean(config.legend))
  Js.Dict.set(pluginsObj, "legend", Js.Json.object_(legendObj))
  Js.Dict.set(optionsObj, "plugins", Js.Json.object_(pluginsObj))
  Js.Dict.set(result, "options", Js.Json.object_(optionsObj))

  Js.Json.object_(result)
}

/** Export to Vega-Lite format */
let toVegaLite = (
  data: array<Js.Dict.t<Js.Json.t>>,
  config: chartConfig,
): Js.Json.t => {
  let markType = switch config.chartType {
  | Line => "line"
  | Bar => "bar"
  | Pie => "arc"
  | Scatter => "point"
  | Area => "area"
  | Histogram => "bar"
  | Heatmap => "rect"
  }

  let result = Js.Dict.empty()
  Js.Dict.set(result, "$schema", Js.Json.string("https://vega.github.io/schema/vega-lite/v5.json"))
  Js.Dict.set(result, "title", Js.Json.string(config.title))

  // Data
  let dataObj = Js.Dict.empty()
  Js.Dict.set(dataObj, "values", Js.Json.array(data->Array.map(row => Js.Json.object_(row))))
  Js.Dict.set(result, "data", Js.Json.object_(dataObj))

  // Mark
  Js.Dict.set(result, "mark", Js.Json.string(markType))

  // Encoding
  let encodingObj = Js.Dict.empty()

  let xObj = Js.Dict.empty()
  Js.Dict.set(xObj, "field", Js.Json.string(config.xAxis))
  Js.Dict.set(xObj, "type", Js.Json.string("nominal"))
  Js.Dict.set(encodingObj, "x", Js.Json.object_(xObj))

  let yObj = Js.Dict.empty()
  Js.Dict.set(yObj, "field", Js.Json.string(config.yAxis))
  Js.Dict.set(yObj, "type", Js.Json.string("quantitative"))
  Js.Dict.set(encodingObj, "y", Js.Json.object_(yObj))

  Js.Dict.set(result, "encoding", Js.Json.object_(encodingObj))

  Js.Json.object_(result)
}

/** Export to D3 format (simple data structure) */
let toD3 = (data: array<Js.Dict.t<Js.Json.t>>): Js.Json.t => {
  Js.Json.array(data->Array.map(row => Js.Json.object_(row)))
}

/** Export to table data format */
let toTableData = (data: array<Js.Dict.t<Js.Json.t>>): Js.Json.t => {
  if Array.length(data) == 0 {
    let obj = Js.Dict.empty()
    Js.Dict.set(obj, "columns", Js.Json.array([]))
    Js.Dict.set(obj, "rows", Js.Json.array([]))
    Js.Json.object_(obj)
  } else {
    let columns = switch data->Array.get(0) {
    | Some(row) => Js.Dict.keys(row)
    | None => []
    }

    let rows = data->Array.map(row => {
      Js.Json.array(
        columns->Array.map(col =>
          Js.Dict.get(row, col)->Option.getOr(Js.Json.null)
        ),
      )
    })

    let obj = Js.Dict.empty()
    Js.Dict.set(obj, "columns", Js.Json.array(columns->Array.map(Js.Json.string)))
    Js.Dict.set(obj, "rows", Js.Json.array(rows))
    Js.Json.object_(obj)
  }
}

/** Main export function */
let export = (
  data: array<Js.Dict.t<Js.Json.t>>,
  options: exportOptions,
): string => {
  switch options.format {
  | CSV => toCSV(data, options)
  | JSON => Js.Json.stringify(Js.Json.array(data->Array.map(row => Js.Json.object_(row))))
  | ChartJS =>
    switch options.chartConfig {
    | Some(config) => Js.Json.stringify(toChartJS(data, config))
    | None => "{}"
    }
  | D3 => Js.Json.stringify(toD3(data))
  | Vega =>
    switch options.chartConfig {
    | Some(config) => Js.Json.stringify(toVegaLite(data, config))
    | None => "{}"
    }
  | TableData => Js.Json.stringify(toTableData(data))
  }
}

/** Chart type to string */
let chartTypeToString = (t: chartType): string => {
  switch t {
  | Line => "line"
  | Bar => "bar"
  | Pie => "pie"
  | Scatter => "scatter"
  | Area => "area"
  | Histogram => "histogram"
  | Heatmap => "heatmap"
  }
}

/** Export format to string */
let formatToString = (f: exportFormat): string => {
  switch f {
  | CSV => "csv"
  | JSON => "json"
  | ChartJS => "chartjs"
  | D3 => "d3"
  | Vega => "vega"
  | TableData => "table"
  }
}
