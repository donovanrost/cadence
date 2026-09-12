import { afterEach, expect, test, vi } from "vite-plus/test";
import { flushPromises, mount } from "@vue/test-utils";
import { alarmConditionsContribution, AlarmConditionsLegacyRedirect } from "../../alarm-conditions";
import { admitAlarmDocument, alarmHref, type AlarmDocument } from "./contracts";
import { alarmFixture } from "./testing";
const mounted: ReturnType<typeof mount>[] = [];
afterEach(() => mounted.splice(0).forEach((w) => w.unmount()));
function start(model = alarmFixture()) {
  const context = { organizationId: model.organization_id, missionId: model.mission_id },
    readPort = { read: vi.fn(async () => model) },
    port = { navigate: vi.fn() };
  const w = mount(alarmConditionsContribution.component, {
    props: { ...alarmConditionsContribution.read(model, context), port, readPort },
  });
  mounted.push(w);
  return { w, context, readPort, port };
}
test("the public alarm contribution renders producer conditions and follows exact evidence", async () => {
  const doc: AlarmDocument = process.env.CADENCE_ALARM_DOCUMENT
    ? JSON.parse(process.env.CADENCE_ALARM_DOCUMENT)
    : alarmFixture();
  const { w, port } = start(doc);
  expect(w.findAll("[data-limit-event]")).toHaveLength(doc.states.items.length);
  const row = doc.states.items[0];
  await w.get(`[data-limit-event="${row.id}"] a[href="${row.evidence_href}"]`).trigger("click");
  expect(port.navigate).toHaveBeenLastCalledWith(row.evidence_href);
  await w.get(`[data-limit-event="${row.id}"] a[href="${row.definition_href}"]`).trigger("click");
  expect(port.navigate).toHaveBeenLastCalledWith(row.definition_href);
  if (process.env.CADENCE_ALARM_DOCUMENT) process.stdout.write("CADENCE_ALARM_CONSUMER_OK\n");
});
test("paged conditions retain full counts and filter URLs preserve existing keys", async () => {
  const doc = alarmFixture(27, 2);
  const { w, port } = start(doc);
  expect(w.findAll("[data-limit-event]")).toHaveLength(2);
  expect(w.get("#alarm-summary").text()).toContain("27");
  await w.get(`a[href="${doc.states.previous_href}"]`).trigger("click");
  expect(port.navigate).toHaveBeenLastCalledWith(doc.states.previous_href);
  await w.get("#alarm-severity").setValue("critical");
  await w.get("#alarm-state").setValue("active");
  await w.get("#alarm-query").setValue("voltage");
  await w.get("#alarm-filters").trigger("submit");
  const q = new URLSearchParams(vi.mocked(port.navigate).mock.calls.at(-1)![0].split("?")[1]);
  expect(Object.fromEntries(q)).toMatchObject({
    severity: "critical",
    state: "active",
    query: "voltage",
    spacecraft_id: "all",
    page: "1",
  });
  await w.get("#alarm-filter-reset").trigger("click");
  expect(port.navigate).toHaveBeenLastCalledWith(
    alarmHref(doc.links.self, {
      severity: "all",
      state: "all",
      query: "",
      spacecraft_id: "all",
      page: 1,
      spacecraft_page: 1,
      spacecraft_query: "",
    }),
  );
});
test("spacecraft search pages preserve the selected scope", async () => {
  const doc = alarmFixture();
  doc.query.spacecraft_page = 2;
  doc.query.spacecraft_id = "craft-0";
  doc.spacecraft_filter = "Selected craft";
  doc.spacecraft = {
    items: [
      { id: "craft-25", label: "Twenty five" },
      { id: "craft-26", label: "Twenty six" },
    ],
    total_count: 27,
    page: 2,
    page_size: 25,
    previous_href: alarmHref(doc.links.self, { ...doc.query, spacecraft_page: 1 }),
    next_href: null,
  };
  const { w, port } = start(doc);
  expect(w.get("#alarm-spacecraft").element).toHaveProperty("value", "craft-0");
  await w.get(`a[href="${doc.spacecraft.previous_href}"]`).trigger("click");
  expect(port.navigate).toHaveBeenCalledWith(doc.spacecraft.previous_href);
});
test("rejects foreign scope, contradictory counts, substituted evidence and wrong paging filters", () => {
  const d = alarmFixture(27, 2),
    ctx = { organizationId: d.organization_id, missionId: d.mission_id };
  expect(admitAlarmDocument(d, { ...ctx, missionId: "other" })).toBeNull();
  for (const mutate of [
    (x: AlarmDocument) => x.counts.critical++,
    (x: AlarmDocument) =>
      (x.states.items[0].evidence_href = x.states.items[0].evidence_href.replace(
        "sample-25",
        "sample-26",
      )),
    (x: AlarmDocument) =>
      (x.states.previous_href = x.states.previous_href!.replace(
        "severity=all",
        "severity=warning",
      )),
    (x: AlarmDocument) => (x.query.state = "nominal"),
  ]) {
    const x = structuredClone(d);
    mutate(x);
    expect(admitAlarmDocument(x, ctx)).toBeNull();
  }
  expect(() => alarmConditionsContribution.read(d, { ...ctx, resourceId: "unexpected" })).toThrow();
});
test("failed or foreign refresh retains last loaded evidence and navigation", async () => {
  const { w, readPort, port } = start();
  readPort.read.mockRejectedValueOnce(Error("forbidden"));
  await w.get("#refresh-alarm-conditions").trigger("click");
  await flushPromises();
  expect(w.get("#alarm-conditions-error").text()).toContain("last loaded evidence");
  expect(w.findAll("[data-limit-event]")).toHaveLength(1);
  readPort.read.mockResolvedValueOnce({ ...alarmFixture(), mission_id: "foreign" });
  await w.get("#refresh-alarm-conditions").trigger("click");
  await flushPromises();
  expect(w.find("#alarm-conditions-error").exists()).toBe(true);
  await w.get(`a[href="${alarmFixture().links.definitions}"]`).trigger("click");
  expect(port.navigate).toHaveBeenCalledWith(alarmFixture().links.definitions);
});

test("legacy entry preserves the canonical Ops destination and rejects arbitrary URLs", () => {
  const w = mount(AlarmConditionsLegacyRedirect, {
    props: {
      mission_id: "mission-alarm",
      query: { state: "active", severity: "critical", query: "voltage" },
    },
  });
  mounted.push(w);
  expect(w.get("a").attributes("href")).toContain("/missions/mission-alarm/ops/alarms?");
  expect(w.get("a").attributes("href")).toContain("state=active");
  const invalid = mount(AlarmConditionsLegacyRedirect, {
    props: { mission_id: "mission-alarm", query: { url: "https://example.com" } },
  });
  mounted.push(invalid);
  expect(invalid.find("a").exists()).toBe(false);
});

test("condition severity and violation must match the canonical evaluated state", () => {
  const doc = alarmFixture(),
    context = { organizationId: doc.organization_id, missionId: doc.mission_id };
  doc.states.items[0].violation = false;
  expect(admitAlarmDocument(doc, context)).toBeNull();
  doc.states.items[0].violation = true;
  doc.states.items[0].state = "unknown";
  expect(admitAlarmDocument(doc, context)).toBeNull();
});
