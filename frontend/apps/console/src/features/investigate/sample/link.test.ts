import { describe, expect, it } from "vite-plus/test";
import { spacecraftRow } from "@/features/fleet/index.ts";
import { sampleLink } from "./link.ts";
import { pointId as pointIdReader } from "@/api/index.ts";

const scid = spacecraftRow(312).scid;

describe("ux U80: links that open the Sample aside (B1, B2 escalations, H2)", () => {
  const at = "2026-11-08T02:08:11Z";
  it("rings the time and opens the aside exactly when the receipt time is known", () => {
    expect(
      sampleLink(scid, pointIdReader("EPS.VBAT"), {
        id: "s-1",
        at,
        receipt_time: "2026-11-08T02:08:11.25Z",
      }),
    ).toEqual({
      name: "ops.spacecraft",
      params: { scId: scid, tab: "telemetry" },
      query: {
        points: "EPS.VBAT",
        focus: "EPS.VBAT",
        at,
        sample: "s-1",
        received: "2026-11-08T02:08:11.25Z",
      },
    });
  });
  it("leaves received out when unknown, and sample out when there is none", () => {
    expect(sampleLink(scid, pointIdReader("P"), { id: "s-1", at })).toMatchObject({
      query: { sample: "s-1" },
    });
    expect(
      sampleLink(scid, pointIdReader("P"), { id: "s-1", at, receipt_time: null }),
    ).not.toHaveProperty("query.received");
    expect(sampleLink(scid, pointIdReader("P"), { id: null, at })).not.toHaveProperty(
      "query.sample",
    );
  });
});
