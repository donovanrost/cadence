import { describe, expect, it } from "vite-plus/test";
import { decode } from "@/api";
import { countsReader } from "./counts.ts";

const base = {
  observed_at: "2026-11-16T03:07:12Z",
  alarms: null,
  commands: null,
  fleet: null,
  contacts: null,
};
const posture = {
  critical: 2,
  caution: 1,
  stale: 3,
  nominal: 488,
  never_heard: 6,
  total: 500,
  limits_configured: true,
  telemetry: "ok",
  observed_at: "2026-11-16T03:07:12Z",
};

describe("/counts posture (api-ops 64b16a90e)", () => {
  it("decodes the posture object", () => {
    const r = decode(countsReader, { ...base, posture });
    expect(r.ok && r.value.posture?.never_heard).toBe(6);
    expect(r.ok && r.value.posture?.telemetry).toBe("ok");
  });
  it("still decodes an older server's /counts without it (the posture shows nothing)", () => {
    const r = decode(countsReader, base);
    expect(r.ok).toBe(true);
    expect(r.ok && r.value.posture).toBeUndefined();
  });
  it("reads an unknown telemetry word as unrecognized, not a failure", () => {
    const r = decode(countsReader, { ...base, posture: { ...posture, telemetry: "partial" } });
    expect(r.ok && r.value.posture?.telemetry).toBe("unrecognized");
  });
});
