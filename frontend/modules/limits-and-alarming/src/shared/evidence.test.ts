import { expect, test } from "vite-plus/test";
import { evidence } from "./evidence";

const at = "2026-09-08T12:00:00.123456Z";
const generated = "2026-09-08T11:59:59.5Z";
const row = (href: string, generation_time: string | null = null) => ({
  point_id: "HK.voltage",
  sample_id: "sample-1",
  spacecraft_id: "craft-1",
  generation_time,
  receipt_time: at,
  evidence_href: href,
});
const q = (o: Record<string, string>) => new URLSearchParams(o).toString();
const fleet = "/console/acme/earendil/fleet/42/telemetry?";

test("api D2: the console Investigate link and its fallbacks are admitted", () => {
  for (const href of [
    fleet + q({ points: "HK.voltage", focus: "HK.voltage", at }),
    fleet + q({ at, focus: "HK.voltage", points: "HK.voltage" }),
    "/console/acme/earendil/telemetry?" + q({ p: "HK.voltage" }),
    "/console",
  ])
    expect(evidence(row(href), "m-1"), href).toBe(true);
});

test("at is the generation time when the sample has one, else the receipt time", () => {
  const link = (t: string) => fleet + q({ points: "HK.voltage", focus: "HK.voltage", at: t });
  expect(evidence(row(link(generated), generated), "m-1")).toBe(true);
  expect(evidence(row(link(at), generated), "m-1")).toBe(false);
  expect(evidence(row(link(at)), "m-1")).toBe(true);
});

test("a console link naming another point, time or key is refused", () => {
  for (const href of [
    fleet + q({ points: "HK.current", focus: "HK.voltage", at }),
    fleet + q({ points: "HK.voltage", focus: "HK.current", at }),
    fleet + q({ points: "HK.voltage", focus: "HK.voltage", at: "2026-09-08T12:00:00Z" }),
    fleet + q({ points: "HK.voltage", focus: "HK.voltage" }),
    fleet + q({ points: "HK.voltage", focus: "HK.voltage", at, sample_id: "sample-1" }),
    fleet + q({ points: "HK.voltage", focus: "HK.voltage", at }) + "&at=" + encodeURIComponent(at),
    "/console/acme/earendil/fleet/x42/telemetry?" +
      q({ points: "HK.voltage", focus: "HK.voltage", at }),
    "/console/acme/earendil/fleet/42/uplink?" +
      q({ points: "HK.voltage", focus: "HK.voltage", at }),
    "/console/acme/earendil/telemetry?" + q({ p: "HK.current" }),
    "/console/acme/earendil/telemetry?" + q({ p: "HK.voltage", sc: "42" }),
    "/console/acme/earendil/telemetry",
    "/console?",
    "/console/",
    "/console/../../admin/telemetry?" + q({ p: "HK.voltage" }),
    "/console/%2e%2e/x/telemetry?" + q({ p: "HK.voltage" }),
    "https://evil.test/console/acme/earendil/telemetry?" + q({ p: "HK.voltage" }),
    "/console/acme/earendil/telemetry?" + q({ p: "HK.voltage" }) + "#x",
    "/console/acme/earendil/telemetry?p=HK.voltage?x=1",
  ])
    expect(evidence(row(href), "m-1"), href).toBe(false);
});

test("the pre-D2 explore link stays admitted until api's change is live", () => {
  const old = (o: Record<string, string>) => "/missions/m-1/ops/explore?" + q(o);
  const base = { point_id: "HK.voltage", spacecraft_id: "craft-1", sample_id: "sample-1" };
  expect(evidence(row(old({ ...base, selected_time: at })), "m-1")).toBe(true);
  expect(evidence(row(old({ ...base, sample_id: "sample-2", selected_time: at })), "m-1")).toBe(
    false,
  );
  expect(evidence(row(old({ ...base, selected_time: at })), "m-2")).toBe(false);
});
