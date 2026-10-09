import type { WidgetFields } from "./contracts";

type Option = { value: string; label: string };
const options = (pairs: Record<string, string>): Option[] =>
  Object.entries(pairs).map(([value, label]) => ({ value, label }));

export const typeOptions = options({
  value_tile: "Value",
  time_series: "Time series",
  status_matrix: "Status matrix",
  data_table: "Table",
  state_timeline: "State timeline",
  event_timeline: "Events",
  constellation_health: "Fleet health",
});
export const windowOptions = options({
  "60": "1m",
  "300": "5m",
  "900": "15m",
  "1800": "30m",
  "3600": "1h",
});
export const precisionOptions = options({
  "0": "0",
  "1": "1",
  "2": "2",
  "3": "3",
  "4": "4",
  "6": "6",
});
export const fillOptions = options({ "0": "None", "8": "Light", "15": "Medium", "30": "Strong" });
export const legendOptions = options({ auto: "Auto", always: "Always", hidden: "Hidden" });
export const lineOptions = options({ thin: "Thin", normal: "Normal", bold: "Bold" });
export const axisOptions = options({ unit: "Per unit", shared: "Shared" });
export const repeatOverOptions = options({
  spacecraft: "Spacecraft",
  contact: "Contacts",
  ground_station: "Ground stations",
  transport: "Transports",
  link: "Links",
});
export const repeatLayoutOptions = options({ wrap_grid: "Wrap", row: "Row", column: "Column" });
export const scopeKindOptions = options({
  mission: "Mission",
  spacecraft: "Spacecraft",
  contact: "Contact",
  ground_station: "Ground station",
  source_endpoint: "Source endpoint",
  transport: "Transport",
  link: "Link",
});

/** Widgets bound to observables; event and fleet widgets resolve their own sources. */
export const bindsObservables = (type: string) =>
  !["event_timeline", "constellation_health"].includes(type);

export function sourceOptions(type: string): Option[] {
  return options({
    telemetry: "Telemetry",
    operational_observables: "Operational",
    ...(type === "state_timeline" ? { limits: "Limits" } : {}),
  });
}

export function modeOptions(type: string) {
  return [
    { value: "context", label: "Follow dashboard" },
    { value: "fixed", label: "One spacecraft" },
    { value: "scope", label: "Resource" },
    ...(["time_series", "status_matrix", "data_table"].includes(type)
      ? [{ value: "repeat", label: "Repeat" }]
      : []),
  ];
}

export const observableLimit = (type: string) =>
  ["value_tile", "state_timeline"].includes(type) ? 1 : type === "time_series" ? 8 : 24;

/** Option sets must include the current value so an unusual saved value stays visible. */
export function withCurrent(list: Option[], value: string): Option[] {
  return list.some((o) => o.value === value) ? list : [...list, { value, label: value }];
}

export const flag = (fields: WidgetFields, key: keyof WidgetFields) => fields[key] === "true";
