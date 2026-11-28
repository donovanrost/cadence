import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import {
  createDefaults,
  diffEdits,
  formatSeconds,
  fromDocument,
  inputModeFor,
  kindSchemaReader,
  parseDuration,
  ratioSlip,
  toValue,
  visible,
  type SchemaField,
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

describe("visible_when with every condition (U83, a transport's listener)", () => {
  const listener = (visibleWhen: unknown) =>
    decode(kindSchemaReader, {
      kind: "transport",
      fields: [
        {
          path: "configuration.listener",
          label: "Listener",
          type: "enum",
          unit: null,
          enum: [
            { value: "own", label: "Own listener for each pass" },
            { value: "shared", label: "Shared, routed by SCID" },
          ],
          range: null,
          default: "own",
          required: false,
          help: null,
          visible_when: visibleWhen,
        },
      ],
    });
  const both = {
    all: [
      { path: "configuration.mode", equals: "listen" },
      { path: "configuration.direction_capability", equals: "inbound" },
    ],
  };

  it("shows the field only when every condition holds", () => {
    const read = listener(both);
    if (!read.ok) throw read.error;
    const field = read.value.fields[0];
    if (!field) throw new Error("fixture");
    const at = (mode: string, direction: string) =>
      visible(field, {
        "configuration.mode": mode,
        "configuration.direction_capability": direction,
      });
    expect(at("listen", "inbound")).toBe(true);
    expect(at("listen", "outbound")).toBe(false);
    expect(at("connect", "inbound")).toBe(false);
  });

  it("still reads one condition, and refuses a malformed list", () => {
    expect(listener({ path: "configuration.mode", equals: "listen" }).ok).toBe(true);
    expect(listener({ all: [{ equals: "listen" }] }).ok).toBe(false);
    expect(listener({ all: "listen" }).ok).toBe(false);
    expect(listener({ all: [] }).ok).toBe(false);
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

describe("number fields (ST1 pass review)", () => {
  const base: SchemaField = {
    path: "realization_target",
    label: "Target",
    type: "number",
    unit: null,
    enum: null,
    range: { min: 0, max: 1 },
    default: 0.98,
    required: false,
    help: null,
    create_only: undefined,
    visible_when: null,
    pattern: undefined,
  };
  it("parses decimals within range", () => {
    expect(toValue(base, "0.95")).toEqual({ ok: true, value: 0.95 });
    expect(toValue(base, "1.5")).toEqual({ ok: false, message: "Target is at most 1." });
    expect(toValue(base, "abc").ok).toBe(false);
  });
  it("writes a ratio as a percent", () => {
    const ratio = { ...base, unit: "ratio" };
    expect(toValue(ratio, "95%")).toEqual({ ok: true, value: 0.95 });
    expect(toValue(ratio, "98")).toEqual({ ok: true, value: 0.98 });
    expect(fromDocument({ kind: "s", fields: [ratio] }, { realization_target: 0.95 })).toEqual({
      realization_target: "95%",
    });
  });

  it("reads a minus typed as U+2212 or as a hyphen (#958)", () => {
    const latitude = { ...base, label: "Latitude", range: { min: -90, max: 90 } };
    expect(toValue(latitude, "\u221233.86")).toEqual({ ok: true, value: -33.86 });
    expect(toValue(latitude, "-33.86")).toEqual({ ok: true, value: -33.86 });
    expect(toValue(latitude, "\u221291")).toEqual({
      ok: false,
      message: "Latitude is at least -90.",
    });
    const height: SchemaField = {
      ...latitude,
      type: "integer",
      label: "Height",
      range: { min: -1000, max: 10_000 },
    };
    expect(toValue(height, "\u2212120")).toEqual({ ok: true, value: -120 });
    expect(toValue(height, "-120")).toEqual({ ok: true, value: -120 });
    expect(toValue(height, "12\u22120").ok).toBe(false);
  });

  it("keeps the full keyboard where a number may be negative: phone keypads have no minus (#958)", () => {
    expect(inputModeFor(base)).toBe("decimal");
    expect(inputModeFor({ ...base, type: "integer" })).toBe("numeric");
    expect(inputModeFor({ ...base, range: { min: -90, max: 90 } })).toBeUndefined();
    expect(
      inputModeFor({ ...base, type: "integer", range: { min: -1000, max: 10_000 } }),
    ).toBeUndefined();
    expect(inputModeFor({ ...base, range: null })).toBeUndefined();
    expect(inputModeFor({ ...base, range: { min: null, max: 10 } })).toBeUndefined();
    expect(inputModeFor({ ...base, type: "integer", unit: "micros", range: null })).toBe("decimal");
    expect(
      inputModeFor({ ...base, type: "integer", unit: "s", range: { min: 0, max: null } }),
    ).toBeUndefined();
    expect(inputModeFor({ ...base, type: "string" })).toBeUndefined();
  });

  it("reads the derived_telemetry schema's text type and create_only key (api fa7e9e463)", () => {
    const base = {
      unit: null,
      enum: null,
      range: null,
      default: null,
      help: null,
      visible_when: null,
    };
    const r = decode(kindSchemaReader, {
      kind: "derived_telemetry",
      fields: [
        {
          ...base,
          path: "point_id",
          label: "Point ID",
          type: "string",
          required: true,
          create_only: true,
        },
        { ...base, path: "expression", label: "Expression", type: "text", required: true },
      ],
    });
    expect(r.ok && r.value.fields.map((f) => [f.type, f.create_only])).toEqual([
      ["string", true],
      ["text", undefined],
    ]);
  });
});

describe("percent typed as a fraction (ux)", () => {
  const base = {
    path: "pass_realized_threshold",
    label: "A pass counts as realized at",
    type: "number" as const,
    unit: "ratio",
    enum: null,
    range: { min: 0, max: 1 },
    default: null,
    required: false,
    help: null,
    visible_when: null,
    pattern: undefined,
    create_only: undefined,
  };
  it("flags 0 < value ≤ 1 with a one-tap fix, and nothing else", () => {
    expect(ratioSlip(base, "0.9")).toEqual({
      line: "That's 0.9%. Did you mean 90%?",
      fix: "90",
      label: "Use 90%",
    });
    expect(ratioSlip(base, "1")?.label).toBe("Use 100%");
    expect(ratioSlip(base, "5")).toBeNull();
    expect(ratioSlip(base, "0")).toBeNull();
    expect(ratioSlip({ ...base, unit: null }, "0.9")).toBeNull();
  });
});

describe("json fields (comms parity 4: a ground station's metadata)", () => {
  const meta: SchemaField = {
    path: "metadata",
    label: "Metadata",
    type: "json",
    unit: null,
    enum: null,
    range: null,
    default: {},
    required: false,
    help: null,
    create_only: undefined,
    visible_when: null,
    pattern: undefined,
  };

  it("decodes the json type instead of reading it as text", () => {
    const r = decode(kindSchemaReader, { kind: "ground_station", fields: [meta] });
    expect(r.ok && r.value.fields[0]?.type).toBe("json");
  });

  it("shows the stored object pretty-printed and stages an object back", () => {
    const text = fromDocument(
      { kind: "ground_station", fields: [meta] },
      { metadata: { site: "north", rack: 2 } },
    )["metadata"];
    expect(text).toBe('{\n  "site": "north",\n  "rack": 2\n}');
    expect(toValue(meta, text ?? "")).toEqual({ ok: true, value: { site: "north", rack: 2 } });
  });

  it("treats empty as {} and rejects anything that isn't one JSON object", () => {
    expect(toValue(meta, "  ")).toEqual({ ok: true, value: {} });
    for (const bad of ["[1, 2]", "null", '"text"', "{site: north}", "3"])
      expect(toValue(meta, bad)).toEqual({
        ok: false,
        message: 'Metadata must be a JSON object, like {"site": "north"}.',
      });
  });
});

describe("create forms preselect required defaults (ux 11-16)", () => {
  const f = (over: Partial<SchemaField>): SchemaField => ({
    path: "x",
    label: "X",
    type: "string",
    unit: null,
    enum: null,
    range: null,
    default: null,
    required: false,
    help: null,
    create_only: undefined,
    visible_when: null,
    pattern: undefined,
    ...over,
  });
  const schema = (fields: SchemaField[]) => ({ kind: "transport", fields });

  it("preselects a required field's default, and a required one-option enum", () => {
    const kind = f({
      path: "transport_kind",
      type: "enum",
      required: true,
      default: "tcp_socket",
      enum: [{ value: "tcp_socket", label: "TCP socket" }],
    });
    const lone = f({
      path: "mode",
      type: "enum",
      required: true,
      enum: [{ value: "client", label: "Client" }],
    });
    expect(createDefaults(schema([kind, lone]), {})).toEqual({
      transport_kind: "tcp_socket",
      mode: "client",
    });
  });

  it("leaves optional defaults empty (inherit) and never overwrites a value", () => {
    const optional = f({ path: "port", type: "integer", default: 7000 });
    const typed = f({ path: "display_name", required: true, default: "Main" });
    expect(createDefaults(schema([optional, typed]), { display_name: "Backup" })).toEqual({
      display_name: "Backup",
    });
  });

  it("leaves a required field without a default or a single option empty", () => {
    const choice = f({
      path: "origin",
      type: "enum",
      required: true,
      enum: [
        { value: "direct", label: "Direct" },
        { value: "provider_managed", label: "Provider managed" },
      ],
    });
    expect(createDefaults(schema([choice]), {})).toEqual({});
  });
});
