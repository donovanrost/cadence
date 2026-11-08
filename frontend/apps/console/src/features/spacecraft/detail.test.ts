import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { detailReader } from "./detail.ts";

const body = (extra: Record<string, unknown> = {}) => ({
  spacecraft: {
    id: "sc-1",
    name: "EARENDIL-312",
    scid: 312,
    norad_id: null,
    plane: 13,
    slot: 12,
    last_received_at: null,
  },
  profile: { id: "p-1", name: "Block 1", version: 3, latest_version: 4 },
  configuration: null,
  routing_rules: [
    {
      id: "r-1",
      name: "Primary downlink",
      purpose: "TM",
      direction: "inbound",
      role: "primary",
      enabled: true,
      active: true,
      transport: { id: "t-1", name: "Svalbard X-band", version: 2 },
    },
  ],
  readiness: {
    ready: true,
    checks: [
      { key: "identity", status: "ready", title: "SCID 312", body: "Has a SCID." },
      { key: "telemetry", status: "blocker", title: "Never heard", body: "Informational." },
    ],
  },
  ...extra,
});

describe("detailReader", () => {
  it("decodes the detail; telemetry doesn't gate readiness", () => {
    expect(decode(detailReader, body()).ok).toBe(true);
  });

  it("rejects ready=true alongside a gating blocker", () => {
    const result = decode(
      detailReader,
      body({
        readiness: {
          ready: true,
          checks: [{ key: "routing", status: "blocker", title: "No rule", body: "." }],
        },
      }),
    );
    expect(result.ok).toBe(false);
  });

  it("rejects a configuration value until change sets define it", () => {
    expect(decode(detailReader, body({ configuration: { version: 3 } })).ok).toBe(false);
  });

  it("rejects the requested-but-not-shipped direction names", () => {
    const b = body();
    const rule = b.routing_rules[0];
    if (rule) Object.assign(rule, { direction: "downlink" });
    expect(decode(detailReader, b).ok).toBe(false);
  });
});
