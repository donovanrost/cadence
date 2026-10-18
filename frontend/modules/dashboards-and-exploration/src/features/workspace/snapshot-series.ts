import type { WorkspaceFrame } from "./contracts";

export type Series = {
  id: string;
  label: string;
  unit: string | null;
  time_axis: WorkspaceFrame["time_axis"];
  points: Array<[number, number | null]>;
  envelope?: {
    kind: "min_max";
    points: Array<[number, number, number]>;
  };
};

/** Columnar frames stay numeric. Missing values are gaps, never zeroes. */
export function snapshotSeries(frames: WorkspaceFrame[], placementId: string): Series[] {
  return frames.flatMap((frame, index) => {
    if (frame.shape !== "wide" || frame.time_axis === null) throw Error("Unsupported chart frame");
    const start = frame.fields.find((f) => f.name === "bucket_start" && f.kind === "time");
    const end = frame.fields.find((f) => f.name === "bucket_end" && f.kind === "time");
    const time = start ?? frame.fields.find((f) => f.name === "time" && f.kind === "time");
    if (!time) throw Error("Missing chart time axis");
    const numeric = frame.fields.filter((f) => f.kind === "number");
    const representatives = start ? numeric.filter((f) => f.name.endsWith("_value")) : numeric;
    if (!representatives.length || (start && !end)) throw Error("Missing chart values");
    return representatives.map((field) => {
      const base = start ? field.name.slice(0, -6) : field.name;
      const lower = numeric.find((f) => f.name === `${base}_min`);
      const upper = numeric.find((f) => f.name === `${base}_max`);
      const envelopeFields = start && end && lower && upper ? { end, lower, upper } : null;
      if (start && !envelopeFields) throw Error("Incomplete chart envelope");
      const points: Series["points"] = [];
      const envelope: Array<[number, number, number]> = [];
      for (let row = 0; row < time.values.length; row++) {
        const timestamp = time.values[row];
        if (typeof timestamp !== "number") throw Error("Missing chart timestamp");
        const value = field.values[row];
        if (value !== null && typeof value !== "number") throw Error("Invalid chart value");
        points.push([timestamp, value]);
        if (envelopeFields) {
          const stop = envelopeFields.end.values[row],
            min = envelopeFields.lower.values[row],
            max = envelopeFields.upper.values[row];
          if (typeof stop !== "number" || stop < timestamp) throw Error("Invalid chart bucket");
          // An absent envelope remains absent, rather than manufacturing a zero band.
          if (min === null && max === null) continue;
          if (typeof min !== "number" || typeof max !== "number" || min > max)
            throw Error("Invalid chart envelope");
          envelope.push([timestamp, min, max]);
        }
      }
      points.sort((a, b) => a[0] - b[0]);
      if (new Set(points.map(([time]) => time)).size !== points.length)
        throw Error("Ambiguous chart timestamps");
      envelope.sort((a, b) => a[0] - b[0]);
      return {
        id: JSON.stringify([placementId, index, base]),
        label: frames.length > 1 ? `${base} · ${index + 1}` : base,
        unit: field.unit,
        time_axis: frame.time_axis,
        points,
        ...(start ? { envelope: { kind: "min_max" as const, points: envelope } } : {}),
      };
    });
  });
}
