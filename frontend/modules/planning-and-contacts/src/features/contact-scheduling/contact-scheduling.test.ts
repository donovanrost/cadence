import { afterEach, expect, test, vi } from "vite-plus/test";
import { flushPromises, mount } from "@vue/test-utils";
import { OpsContactSchedule } from "../../contact-scheduling";
import {
  admitContactSchedule,
  admitSearch,
  cancelEvidence,
  scheduleHref,
} from "./contact-schedule";
import {
  completion,
  receiptFixture,
  scheduleFixture,
  searchFixture,
} from "./contact-schedule.test-support";
afterEach(() => vi.restoreAllMocks());
function harness() {
  const model = scheduleFixture(),
    execute = vi.fn(),
    refresh = vi.fn().mockResolvedValue(model);
  const wrapper = mount(OpsContactSchedule, {
    props: { schedule: model, port: { context: model.context, execute, refresh } },
  });
  return { model, execute, refresh, wrapper };
}
test("semantic admission binds scope, spacecraft, route evidence and independent bounded ledgers", () => {
  const m = scheduleFixture();
  expect(admitContactSchedule(m, m.context)).toEqual(m);
  for (const change of [
    (v: any) => (v.context.mission_id = "foreign"),
    (v: any) => (v.routes.entries[0].spacecraft_id = "foreign"),
    (v: any) => (v.routes.entries[0].evidence.provider_version = 0),
    (v: any) => (v.routes.entries[0].evidence.extra = "unreviewed"),
    (v: any) => (v.scheduled.more = true),
    (v: any) => v.scheduled.entries.push(v.scheduled.entries[0]),
    (v: any) => (v.query.scheduled_page = 2),
    (v: any) => (v.reservations.entries[0].provider_revision = 0),
    (v: any) => (v.query.spacecraft_q = "x".repeat(121)),
  ]) {
    const bad = structuredClone(m);
    change(bad);
    expect(admitContactSchedule(bad, m.context)).toBeNull();
  }
  expect(scheduleHref(m, { reservations_page: 2 })).toBe(
    "/missions/mission-one/ops/contacts?spacecraft_id=craft-one&reservations_page=2",
  );
});
test("native search seals the reviewed route, reserve sends only its opaque token, and a confirmed receipt survives read failure", async () => {
  const { model, execute, refresh, wrapper } = harness();
  const found = searchFixture(model);
  execute.mockResolvedValueOnce(completion(found));
  await wrapper.get("#contact-search").trigger("submit");
  await flushPromises();
  expect(execute).toHaveBeenNthCalledWith(1, "search", {
    contact_search: found.search,
    route_evidence: model.routes.entries[0]!.evidence,
  });
  execute.mockResolvedValueOnce(completion(receiptFixture()));
  refresh.mockRejectedValueOnce(Error("private"));
  await wrapper.get("#reserve-opportunity-one").trigger("click");
  await flushPromises();
  expect(execute).toHaveBeenNthCalledWith(2, "reserve", { token: "opaque-token-one" });
  expect(wrapper.get("#contact-schedule-receipt").text()).toContain("reservation-one");
  expect(wrapper.get("#reserve-opportunity-one").attributes("disabled")).toBeDefined();
  expect(wrapper.text()).not.toContain("private");
  expect(refresh).toHaveBeenCalledTimes(1);
  wrapper.unmount();
});
test("cancellation requires native confirmation and sends the reviewed revision even after a ledger refresh", async () => {
  const { model, execute, refresh, wrapper } = harness();
  await wrapper.get("#cancel-review-reservation-one").trigger("click");
  expect(execute).not.toHaveBeenCalled();
  const advanced = structuredClone(model);
  advanced.reservations.entries[0]!.provider_revision = 5;
  refresh.mockResolvedValue(advanced);
  await wrapper.get("#contact-schedule-refresh").trigger("click");
  await flushPromises();
  execute.mockResolvedValue(completion(receiptFixture("canceled")));
  await wrapper.get("#contact-cancel-confirm").trigger("click");
  await flushPromises();
  expect(execute).toHaveBeenCalledExactlyOnceWith("cancel", {
    reservation_evidence: cancelEvidence(model.context, model.reservations.entries[0]!),
  });
  expect(wrapper.find("#contact-cancellation-review").exists()).toBe(false);
  wrapper.unmount();
});
test("unknown provider outcomes retain review and lock mutations across read refreshes", async () => {
  const { execute, refresh, wrapper } = harness();
  execute.mockRejectedValue(Error("private-provider-detail"));
  await wrapper.get("#cancel-review-reservation-one").trigger("click");
  await wrapper.get("#contact-cancel-confirm").trigger("click");
  await flushPromises();
  expect(wrapper.find("#contact-schedule-uncertain").exists()).toBe(true);
  await wrapper.get("#contact-schedule-refresh").trigger("click");
  await flushPromises();
  expect(refresh).toHaveBeenCalledTimes(1);
  expect(wrapper.get("#contact-cancel-confirm").attributes("disabled")).toBeDefined();
  expect(wrapper.get("#contact-search-submit").element.closest("fieldset")?.disabled).toBe(true);
  expect(execute).toHaveBeenCalledTimes(1);
  expect(wrapper.text()).not.toContain("private-provider-detail");
  wrapper.unmount();
});
test("a later uncertain operation cannot reuse an earlier successful receipt", async () => {
  const { model, execute, wrapper } = harness();
  execute
    .mockResolvedValueOnce(completion(searchFixture(model)))
    .mockResolvedValueOnce(completion(receiptFixture()))
    .mockRejectedValueOnce(Error("lost"));
  await wrapper.get("#contact-search").trigger("submit");
  await flushPromises();
  await wrapper.get("#reserve-opportunity-one").trigger("click");
  await flushPromises();
  await wrapper.get("#cancel-review-reservation-one").trigger("click");
  await wrapper.get("#contact-cancel-confirm").trigger("click");
  await flushPromises();
  expect(wrapper.find("#contact-schedule-receipt").exists()).toBe(false);
  expect(wrapper.find("#contact-schedule-uncertain").exists()).toBe(true);
  wrapper.unmount();
});
test("search rejects cross-scope, stale pins, repeated identities and windows outside the captured search", () => {
  const m = scheduleFixture(),
    found = searchFixture(m);
  for (const change of [
    (v: any) => (v.context.mission_id = "other"),
    (v: any) => v.route.evidence.transport_version++,
    (v: any) => v.opportunities.push(v.opportunities[0]),
    (v: any) => (v.opportunities[0].starts_at = "2099-09-09T11:00:00Z"),
    (v: any) => (v.opportunities[0].token = "x".repeat(8193)),
  ]) {
    const bad = structuredClone(found);
    change(bad);
    expect(admitSearch(bad, m.context, found.search, m.routes.entries[0]!)).toBeNull();
  }
});
test("expired and unavailable opportunities cannot be reserved", async () => {
  const { model, execute, wrapper } = harness(),
    found = searchFixture(model);
  found.opportunities[0]!.expires_at = "2020-01-01T00:00:00Z";
  execute.mockResolvedValue(completion(found));
  await wrapper.get("#contact-search").trigger("submit");
  await flushPromises();
  expect(wrapper.get("#reserve-opportunity-one").attributes("disabled")).toBeDefined();
  wrapper.unmount();
});
test("pending operations suppress duplicate submissions and departed results never refresh", async () => {
  const { execute, refresh, wrapper } = harness();
  let done!: (v: unknown) => void;
  execute.mockImplementation(
    () =>
      new Promise((resolve) => {
        done = resolve;
      }),
  );
  await wrapper.get("#cancel-review-reservation-one").trigger("click");
  await wrapper.get("#contact-cancel-confirm").trigger("click");
  await wrapper.get("#contact-cancel-confirm").trigger("click");
  expect(execute).toHaveBeenCalledTimes(1);
  wrapper.unmount();
  done(completion(receiptFixture("canceled")));
  await flushPromises();
  expect(refresh).not.toHaveBeenCalled();
});
test("invalid producer data can recover through a read, and failed reads retain the previous ledgers", async () => {
  const { model, refresh, wrapper } = harness();
  await wrapper.setProps({ schedule: {} });
  expect(wrapper.find("#contact-schedule-unavailable").exists()).toBe(true);
  await wrapper.get("#contact-schedule-retry").trigger("click");
  await flushPromises();
  expect(wrapper.find("#ops-contact-schedule-page").exists()).toBe(true);
  refresh.mockResolvedValueOnce({ ...model, contract_version: 2 });
  await wrapper.get("#contact-schedule-refresh").trigger("click");
  await flushPromises();
  expect(wrapper.find("#contact-scheduled-ledger").exists()).toBe(true);
  wrapper.unmount();
});
test("producer-supplied contact scheduling workflow", async () => {
  if (!process.env.CADENCE_SCHEDULE_MODEL) return;
  const model = JSON.parse(process.env.CADENCE_SCHEDULE_MODEL),
    action = process.env.CADENCE_SCHEDULE_ACTION;
  expect(admitContactSchedule(model)).not.toBeNull();
  const execute = vi.fn().mockRejectedValue(Error("payload captured"));
  const wrapper = mount(OpsContactSchedule, {
    props: { schedule: model, port: { context: model.context, execute, refresh: vi.fn() } },
  });
  if (action === "search") await wrapper.get("#contact-search").trigger("submit");
  if (action === "reserve") {
    execute.mockResolvedValueOnce(completion(JSON.parse(process.env.CADENCE_SCHEDULE_RESULT!)));
    await wrapper.get("#contact-search").trigger("submit");
    await flushPromises();
    const found = JSON.parse(process.env.CADENCE_SCHEDULE_RESULT!);
    await wrapper
      .get(`[id="reserve-${encodeURIComponent(found.opportunities[0].id)}"]`)
      .trigger("click");
  }
  if (action === "cancel") {
    await wrapper
      .get(`[id="cancel-review-${encodeURIComponent(model.reservations.entries[0].id)}"]`)
      .trigger("click");
    await wrapper.get("#contact-cancel-confirm").trigger("click");
  }
  await flushPromises();
  expect(execute.mock.calls.at(-1)?.[0]).toBe(action);
  process.stdout.write(`SCHEDULE_PAYLOAD=${JSON.stringify(execute.mock.calls.at(-1)![1])}\n`);
  wrapper.unmount();
});
test("policy-derived read-only access hides cancellation and disables search", () => {
  const model = scheduleFixture();
  model.permissions = { operate: false, cancel: false };
  const wrapper = mount(OpsContactSchedule, {
    props: {
      schedule: model,
      port: { context: model.context, execute: vi.fn(), refresh: vi.fn() },
    },
  });
  expect(wrapper.find("#cancel-review-reservation-one").exists()).toBe(false);
  expect(wrapper.get("#contact-search-submit").element.closest("fieldset")?.disabled).toBe(true);
  wrapper.unmount();
});
