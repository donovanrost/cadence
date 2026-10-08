import { producerFixture } from "../../../../../test-support/producer-fixture";
import { fixtureRecord, jsonFixture } from "../../../../../test-support/json-fixture";
import { required } from "../../../../../test-support/required";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { flushPromises, mount } from "@vue/test-utils";
import { createContactScheduleService } from "./schedule-service";
import { OpsContactSchedule } from "../../contact-scheduling";
import {
  admitContactSchedule,
  admitSearch,
  validScheduleRoute,
  validScheduleSearch,
  scheduleHref,
} from "./contact-schedule";
import { scheduleFixture, searchFixture } from "./contact-schedule.test-support";
afterEach(() => vi.restoreAllMocks());

test("semantic admission binds scope, spacecraft, route evidence and independent bounded ledgers", () => {
  const m = scheduleFixture();
  expect(admitContactSchedule(m, m.context)).toEqual(m);
  for (const change of [
    (v: ReturnType<typeof scheduleFixture>) => (v.context.mission_id = "foreign"),
    (v: ReturnType<typeof scheduleFixture>) =>
      (required(v.routes.entries[0]).spacecraft_id = "foreign"),
    (v: ReturnType<typeof scheduleFixture>) =>
      (required(v.routes.entries[0]).evidence.provider_version = 0),
    (v: ReturnType<typeof scheduleFixture>) =>
      (fixtureRecord(required(v.routes.entries[0]).evidence).extra = "unreviewed"),
    (v: ReturnType<typeof scheduleFixture>) => (v.scheduled.more = true),
    (v: ReturnType<typeof scheduleFixture>) =>
      v.scheduled.entries.push(required(v.scheduled.entries[0])),
    (v: ReturnType<typeof scheduleFixture>) => (v.query.scheduled_page = 2),
    (v: ReturnType<typeof scheduleFixture>) =>
      (required(v.reservations.entries[0]).provider_revision = 0),
    (v: ReturnType<typeof scheduleFixture>) => (v.query.spacecraft_q = "x".repeat(121)),
  ]) {
    const bad = structuredClone(m);
    change(bad);
    expect(admitContactSchedule(bad, m.context)).toBeNull();
  }
  expect(scheduleHref(m, { reservations_page: 2 })).toBe(
    "/missions/mission-one/ops/contacts?spacecraft_id=craft-one&reservations_page=2",
  );
});
test("search rejects cross-scope, stale pins, repeated identities and windows outside the captured search", () => {
  const m = scheduleFixture(),
    found = searchFixture(m);
  for (const change of [
    (v: ReturnType<typeof searchFixture>) => (v.context.mission_id = "other"),
    (v: ReturnType<typeof searchFixture>) => v.route.evidence.transport_version++,
    (v: ReturnType<typeof searchFixture>) => v.opportunities.push(required(v.opportunities[0])),
    (v: ReturnType<typeof searchFixture>) =>
      (required(v.opportunities[0]).starts_at = "2099-09-09T11:00:00Z"),
    (v: ReturnType<typeof searchFixture>) =>
      (required(v.opportunities[0]).token = "x".repeat(8193)),
  ]) {
    const bad = structuredClone(found);
    change(bad);
    expect(admitSearch(bad, m.context, found.search, required(m.routes.entries[0]))).toBeNull();
  }
});
const producer = producerFixture("CADENCE_SCHEDULE_MODEL", import.meta.url);
test.skipIf(!producer.available)("producer-supplied contact scheduling workflow", async () => {
  const model = required(admitContactSchedule(jsonFixture(producer.read()))),
    action = process.env.CADENCE_SCHEDULE_ACTION;
  expect(admitContactSchedule(model)).not.toBeNull();
  const execute = vi.fn().mockRejectedValue(Error("payload captured"));
  const wrapper = mount(OpsContactSchedule, {
    props: {
      schedule: model,
      port: createContactScheduleService({ execute, read: vi.fn() }, model.context),
    },
  });
  if (action === "search") await wrapper.get("#contact-search").trigger("submit");
  if (action === "reserve") {
    execute.mockResolvedValueOnce(jsonFixture(required(process.env.CADENCE_SCHEDULE_RESULT)));
    await wrapper.get("#contact-search").trigger("submit");
    await flushPromises();
    const supplied = jsonFixture(required(process.env.CADENCE_SCHEDULE_RESULT));
    if (
      !validScheduleRoute(supplied.route) ||
      !validScheduleSearch(supplied.search, supplied.route.evidence)
    )
      throw Error("Invalid search fixture");
    const found = required(admitSearch(supplied, model.context, supplied.search, supplied.route));
    await wrapper
      .get(`[id="reserve-${encodeURIComponent(required(found.opportunities[0]).id)}"]`)
      .trigger("click");
  }
  if (action === "cancel") {
    await wrapper
      .get(`[id="cancel-review-${encodeURIComponent(required(model.reservations.entries[0]).id)}"]`)
      .trigger("click");
    await wrapper.get("#contact-cancel-confirm").trigger("click");
  }
  await flushPromises();
  expect(execute.mock.calls.at(-1)?.[0]).toBe(action);
  process.stdout.write(
    `SCHEDULE_PAYLOAD=${JSON.stringify(fixtureRecord(required(execute.mock.calls.at(-1))[1]).payload)}\n`,
  );
  wrapper.unmount();
});
test("policy-derived read-only access hides cancellation and disables search", () => {
  const model = scheduleFixture();
  model.permissions = { operate: false, cancel: false };
  const wrapper = mount(OpsContactSchedule, {
    props: {
      schedule: model,
      port: createContactScheduleService({ execute: vi.fn(), read: vi.fn() }, model.context),
    },
  });
  expect(wrapper.find("#cancel-review-reservation-one").exists()).toBe(false);
  expect(wrapper.get("#contact-search-submit").element.closest("fieldset")?.disabled).toBe(true);
  wrapper.unmount();
});

test("admission checks the serialized schedule and search values it returns", () => {
  const model = scheduleFixture();
  expect(
    admitContactSchedule({ ...model, toJSON: () => ({ ...model, contract_version: 2 }) }),
  ).toBeNull();
  const result = searchFixture(model);
  expect(
    admitSearch(
      { ...result, toJSON: () => ({ ...result, opportunities: [{ token: 42 }] }) },
      model.context,
      result.search,
      result.route,
    ),
  ).toBeNull();
  const admitted = admitContactSchedule(model);
  expect(admitted).toEqual(model);
  expect(admitted).not.toBe(model);
});
