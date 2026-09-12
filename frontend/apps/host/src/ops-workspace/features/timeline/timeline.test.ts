import { flushPromises, mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import { readTimeline, timelineHref, type TimelineModel } from "./contracts";
import TimelinePage from "./TimelinePage.vue";
import TimelinePanel from "./TimelinePanel.vue";
import { fixture } from "./fixtures.test-support";
const props = (model = fixture()) => ({
  model,
  navigate: vi.fn(),
  refresh: vi.fn().mockResolvedValue(undefined),
});
test("filters navigate with the applied draft and clear selection while event links retain applied filters", async () => {
  const input = props();
  const wrapper = mount(TimelinePanel, { props: input });
  const link = wrapper.get("#mission-timeline-events a").attributes("href")!;
  expect(new URL(link, "https://cadence.test").searchParams.get("category")).toBe("health");
  expect(new URL(link, "https://cadence.test").searchParams.get("event_id")).toBe(
    "mission_event:newer",
  );
  await wrapper.get("#timeline_severity").setValue("warning");
  await wrapper.get("#timeline-filter-form").trigger("submit");
  const target = new URL(input.navigate.mock.calls[0]![0], "https://cadence.test");
  expect(target.pathname).toBe("/missions/mission-1/ops/timeline");
  expect(target.searchParams.get("severity")).toBe("warning");
  expect(target.searchParams.has("event_id")).toBe(false);
  expect(wrapper.get("#timeline-selected-event-id").text()).toBe("mission_event:selected");
  expect(wrapper.get("#timeline-clear-selection").attributes("href")).toBe(
    "/missions/mission-1/ops/timeline?category=health",
  );
  wrapper.unmount();
});
test("unavailable selection can be cleared without losing filters", () => {
  const model = fixture();
  model.selected_status = "unavailable";
  model.selected = null;
  const wrapper = mount(TimelinePanel, { props: props(model) });
  expect(wrapper.find("#timeline-event-unavailable").exists()).toBe(true);
  expect(wrapper.get("#timeline-clear-unavailable").attributes("href")).toBe(
    "/missions/mission-1/ops/timeline?category=health",
  );
  wrapper.unmount();
});
test("invalid filter values remain editable and do not render stale events as matching", async () => {
  const model = fixture();
  model.query.category = "invalid";
  model.errors = ["category"];
  model.events = [];
  const input = props(model);
  const wrapper = mount(TimelinePanel, { props: input });
  expect(wrapper.find("#timeline-filter-errors").exists()).toBe(true);
  expect(wrapper.findAll("#mission-timeline-events li")).toHaveLength(0);
  await wrapper.get("#timeline_category").setValue("operations");
  await wrapper.get("#timeline-filter-form").trigger("submit");
  expect(input.navigate.mock.calls[0]![0]).toBe(
    "/missions/mission-1/ops/timeline?category=operations",
  );
  wrapper.unmount();
});
test("refresh is bounded to one request and failure keeps the observed evidence visible", async () => {
  let reject!: (reason: Error) => void;
  const refresh = vi.fn(() => new Promise<void>((_, failure) => (reject = failure)));
  const wrapper = mount(TimelinePanel, { props: { ...props(), refresh } });
  await wrapper.get("#refresh-timeline").trigger("click");
  await wrapper.get("#refresh-timeline").trigger("click");
  expect(refresh).toHaveBeenCalledTimes(1);
  expect(wrapper.get("#refresh-timeline").attributes("disabled")).toBeDefined();
  reject(Error("offline"));
  await flushPromises();
  expect(wrapper.text()).toContain("previous observation");
  expect(wrapper.get("#timeline-selected-event-id").text()).toBe("mission_event:selected");
  wrapper.unmount();
});
test("unknown envelopes and cross-mission evidence fail in the core boundary and recover", async () => {
  const data = fixture();
  const refresh = vi.fn();
  const snapshot = { version: 1, page: "timeline", status: "ready", context: data.context, data };
  const wrapper = mount(TimelinePage, {
    props: { snapshot, organizationId: "org-1", missionId: "foreign", navigate: vi.fn(), refresh },
  });
  expect(wrapper.find("#core-timeline-error").exists()).toBe(true);
  expect(wrapper.find("#ops-timeline-page").exists()).toBe(false);
  await wrapper.get("#core-timeline-retry").trigger("click");
  expect(refresh).toHaveBeenCalledTimes(1);
  await wrapper.setProps({ missionId: "mission-1" });
  expect(wrapper.find("#ops-timeline-page").exists()).toBe(true);
  await wrapper.setProps({ snapshot: { ...snapshot, version: 2 } });
  expect(wrapper.find("#core-timeline-error").exists()).toBe(true);
  wrapper.unmount();
});
test("malformed records and forged selection cannot be admitted", () => {
  for (const change of [
    (d: TimelineModel) => (d.context.organization_id = "foreign"),
    (d: TimelineModel) => d.events.push(d.events[0]!),
    (d: TimelineModel) => (d.selected!.id = "foreign"),
    (d: TimelineModel) => (d.source_dashboard_id = "foreign"),
    (d: TimelineModel) => (d.events[0]!.occurred_at = "invalid"),
  ]) {
    const value = fixture();
    change(value);
    expect(() => readTimeline(value, "org-1", "mission-1")).toThrow();
  }
  expect(() => timelineHref("../foreign", {})).toThrow();
});
test.skipIf(!process.env.CADENCE_TIMELINE_DOCUMENT)(
  "actual producer document reaches filters and selected canonical evidence",
  () => {
    const document = JSON.parse(process.env.CADENCE_TIMELINE_DOCUMENT!);
    const model = readTimeline(
      document,
      document.context.organization_id,
      document.context.mission_id,
    );
    const wrapper = mount(TimelinePanel, { props: props(model) });
    expect(wrapper.get("#timeline-selected-event-id").text()).toBe("mission_event:selected");
    expect(wrapper.get("#timeline-event-detail").text()).toContain("Canonical source evidence");
    expect(wrapper.findAll("#mission-timeline-events li")).toHaveLength(1);
    expect(wrapper.get("#timeline_from").element).toHaveProperty("value", "2026-09-03T00:00:00Z");
    expect(wrapper.text()).not.toContain("not a UI field");
    wrapper.unmount();
  },
);

test("history links retain filters and applying a new filter returns to the newest page", async () => {
  const model = fixture();
  model.query.before_at = "2026-09-03T00:00:00Z";
  model.query.before_id = "mission_event:previous";
  model.next_cursor = { at: "2026-09-01T00:00:00Z", id: "mission_event:older" };
  const input = props(model);
  const wrapper = mount(TimelinePanel, { props: input });
  const older = new URL(
    wrapper.get("#timeline-older-events").attributes("href")!,
    "https://cadence.test",
  );
  expect(older.searchParams.get("category")).toBe("health");
  expect(older.searchParams.get("before_id")).toBe("mission_event:older");
  expect(older.searchParams.has("event_id")).toBe(false);
  expect(wrapper.get("#timeline-newest-events").attributes("href")).toBe(
    "/missions/mission-1/ops/timeline?category=health",
  );
  await wrapper.get("#timeline-filter-form").trigger("submit");
  expect(input.navigate.mock.calls[0]![0]).toBe("/missions/mission-1/ops/timeline?category=health");
  wrapper.unmount();
});
