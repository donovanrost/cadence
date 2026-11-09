import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import {
  diffEdits,
  formatSeconds,
  fromDocument,
  kindSchemaReader,
  parseDuration,
  visible,
} from "./kindSchema.ts";

const decoded = decode(kindSchemaReader, {
  kind: "transport",
  fields: [
    {
      path: "display_name",
      label: "Name",
      type: "string",
      unit: null,
      enum: null,
      range: { min: 1, max: 20 },
      default: null,
      required: true,
      help: null,
      visible_when: null,
    },
    {
      path: "configuration.framing_mode",
      label: "Framing",
      type: "enum",
      unit: null,
      enum: [
        { value: "fixed_size", label: "Fixed size" },
        { value: "stream", label: "Stream" },
      ],
      range: null,
      default: null,
      required: false,
      help: null,
      visible_when: null,
    },
    {
      path: "configuration.frame_size",
      label: "Frame size",
      type: "integer",
      unit: "bytes",
      enum: null,
      range: { max: 2048 },
      default: null,
      required: false,
      help: null,
      visible_when: { path: "configuration.framing_mode", equals: "fixed_size" },
    },
  ],
});
if (!decoded.ok) throw decoded.error;
const schema = decoded.value;

describe("kind schema forms", () => {
  it("reads nested values and follows visible_when", () => {
    const values = fromDocument(schema, {
      display_name: "SVB",
      configuration: { framing_mode: "stream", frame_size: 1115 },
    });
    expect(values["configuration.frame_size"]).toBe("1115");
    const frame = schema.fields[2];
    if (!frame) throw new Error("fixture");
    expect(visible(frame, values)).toBe(false);
    expect(visible(frame, { ...values, "configuration.framing_mode": "fixed_size" })).toBe(true);
  });

  it("stages only changed visible fields, typed, and reports problems per field", () => {
    const before = fromDocument(schema, {
      display_name: "SVB",
      configuration: { framing_mode: "fixed_size", frame_size: 1115 },
    });
    expect(diffEdits(schema, before, { ...before, "configuration.frame_size": "1279" })).toEqual({
      ok: true,
      changes: [{ path: "configuration.frame_size", value: 1279 }],
    });
    const bad = diffEdits(schema, before, {
      ...before,
      display_name: "",
      "configuration.frame_size": "9999",
    });
    expect(bad.ok).toBe(false);
    if (!bad.ok)
      expect(Object.keys(bad.errors).sort()).toEqual(["configuration.frame_size", "display_name"]);
  });
});

describe("U24 units", () => {
  it("formats and parses durations", () => {
    expect(formatSeconds(172_800)).toBe("48h 00m");
    expect(formatSeconds(5_445)).toBe("1h 30m 45s");
    expect(parseDuration("48h")).toBe(172_800);
    expect(parseDuration("2d")).toBe(172_800);
    expect(parseDuration("90m")).toBe(5_400);
    expect(parseDuration("1d 6h")).toBe(108_000);
    expect(parseDuration("48h 00m")).toBe(172_800);
    expect(parseDuration("3600")).toBe(3_600);
    expect(parseDuration("2 weeks")).toBeNull();
  });
});
