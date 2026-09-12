import { jsonFixture } from "../../../../../test-support/json-fixture";
import { required } from "../../../../../test-support/required";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { flushPromises, mount } from "@vue/test-utils";
import { PostureSurface } from "../../posture";
import { postureFixture } from "../../shared/testing";
import { admitDocument, type PostureDocument } from "./contracts";
const mounted: { unmount: () => void }[] = [];
afterEach(() => mounted.splice(0).forEach((w) => w.unmount()));
function populated() {
  const d = postureFixture(),
    stamp = "2026-09-08T12:00:00Z";
  d.counts.red = 1;
  d.states.total_count = 1;
  d.states.items = [
    {
      id: "limit-event",
      point_id: "HK.voltage",
      point_name: "Voltage",
      spacecraft_id: null,
      limit_set_name: "FLIGHT",
      definition_id: "definition-1",
      definition_version: 1,
      sample_id: "sample-1",
      source_sample_type: "telemetry_sample",
      value: "42",
      state: "red_high",
      severity: "red",
      violation: true,
      generation_time: null,
      receipt_time: stamp,
      definition_href: d.links.self + "?definition=definition-1&version=1",
      evidence_href:
        "/missions/mission-limits/ops/explore?" +
        new URLSearchParams({
          point_id: "HK.voltage",
          sample_id: "sample-1",
          selected_time: stamp,
        }),
    },
  ];
  return d;
}
function start(d = populated()) {
  const port = { read: vi.fn(async () => d), navigate: vi.fn<(href: string) => void>() };
  const w = mount(PostureSurface, { props: { document: d, port } });
  mounted.push(w);
  return { w, port };
}
test("producer supplied posture renders scoped states and exact producing-version links", () => {
  const d: PostureDocument = process.env.CADENCE_LIMITS_POSTURE
    ? required(admitDocument(jsonFixture(process.env.CADENCE_LIMITS_POSTURE)))
    : populated();
  expect(admitDocument(d)).not.toBeNull();
  const { w } = start(d);
  expect(w.find("#limits-posture-page").exists()).toBe(true);
  expect(w.findAll("[data-limit-event]")).toHaveLength(d.states.items.length);
  if (process.env.CADENCE_LIMITS_POSTURE) process.stdout.write("CADENCE_LIMITS_POSTURE_OK\n");
});
test("retains actual timestamps and producing-version identity while changing scope filters", async () => {
  const { w, port } = start();
  expect(w.text()).toContain("2026-09-08T12:00:00Z");
  expect(w.text()).toContain("Produced by definition-1 · v1");
  await w.get("#posture-severity").setValue("yellow");
  await w.get("#posture-spacecraft").setValue("mission");
  await w.get("#limit-posture-filters").trigger("submit");
  const target = required(vi.mocked(port.navigate).mock.calls[0])[0];
  expect(target).toContain("severity=yellow");
  expect(target).toContain("spacecraft=mission");
});
test("rejects substituted sample links, inconsistent counts and foreign spacecraft rows", () => {
  const a = populated();
  required(a.states.items[0]).evidence_href = required(a.states.items[0]).evidence_href.replace(
    "sample-1",
    "sample-2",
  );
  expect(admitDocument(a)).toBeNull();
  const b = populated();
  b.counts.red = 2;
  expect(admitDocument(b)).toBeNull();
  const c = populated();
  c.query.spacecraft = "craft-1";
  expect(admitDocument(c)).toBeNull();
});
test("a failed refresh labels retained evidence and preserves navigation", async () => {
  const { w, port } = start();
  port.read.mockRejectedValue(Error("offline"));
  await w.get("#refresh-limit-posture").trigger("click");
  await flushPromises();
  expect(w.get("#limits-posture-error").text()).toContain("last loaded evidence");
  expect(w.findAll("[data-limit-event]")).toHaveLength(1);
  expect(w.find(`a[href="${populated().links.manage}"]`).exists()).toBe(true);
});
