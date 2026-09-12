import { required } from "../../../../../test-support/required";
import { fixtureArrayAt, fixtureRecordAt } from "../../../../../test-support/json-fixture";
import { flushPromises, mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import {
  CommandMonitor,
  readCommandMonitor,
  commandMonitorContribution,
} from "../../mission-commands";
import { commandObservation, monitorFixture, monitorContext } from "./monitor.test-support";
import { monitorHref, readMonitorQuery } from "./monitor-query";

function setup(model = monitorFixture()) {
  const navigate = vi.fn(),
    refresh = vi.fn().mockResolvedValue(undefined);
  const port = { navigate };
  const wrapper = mount(CommandMonitor, {
    props: {
      model: readCommandMonitor(model, monitorContext),
      context: monitorContext,
      port,
      refresh,
    },
  });
  return { wrapper, navigate, refresh, port };
}
test("admission validates the semantic model, bounds, evidence and exact scope", () => {
  const model = monitorFixture();
  expect(readCommandMonitor(model, monitorContext)).toBe(model);
  expect(commandMonitorContribution.navigation).toBe(true);
  expect("actions" in commandMonitorContribution).toBe(false);
  const mutate = [
    (m: unknown) => (fixtureRecordAt(m).version = 2),
    (m: unknown) => (fixtureRecordAt(m).can_review = "true"),
    (m: unknown) => (fixtureRecordAt(m).organization_id = "foreign"),
    (m: unknown) => (fixtureRecordAt(m).page_size = 100),
    (m: unknown) => (fixtureRecordAt(m).status = "empty"),
    (m: unknown) => (fixtureRecordAt(m, "rows", 0).status = ["in_flight"]),
    (m: unknown) => (fixtureRecordAt(m, "rows", 0, "release").encoded_binary_base64 = "secret"),
    (m: unknown) => (fixtureRecordAt(m, "rows", 0, "verifiers", 0).state = "unknown"),
    (m: unknown) => (fixtureRecordAt(m, "rows", 0).verifier_total = 2),
    (m: unknown) => (fixtureRecordAt(m, "query").document = {}),
    (m: unknown) => (fixtureRecordAt(m, "summary").active_count = 0),
    (m: unknown) => (fixtureRecordAt(m).focus = { status: "not_found", row: null }),
    (m: unknown) => fixtureArrayAt(m, "rows").push(fixtureArrayAt(m, "rows")[0]),
    (m: unknown) => (fixtureRecordAt(m, "query").status = "queued"),
    (m: unknown) => (fixtureRecordAt(m, "query").target = "other-endpoint"),
    (m: unknown) => (fixtureRecordAt(m).targets_limited = true),
    (m: unknown) => {
      fixtureRecordAt(m, "query").focus_command_id = "request-a";
      fixtureRecordAt(m).focus = { status: "not_found", row: null };
    },
  ];
  for (const change of mutate) {
    const value = structuredClone(model);
    change(value);
    expect(() => readCommandMonitor(value, monitorContext)).toThrow();
  }
  expect(() => readCommandMonitor(model, { ...monitorContext, resourceId: "request-a" })).toThrow();
  const sorted: unknown = JSON.parse(
    JSON.stringify(model, (_, v: unknown) =>
      v && typeof v === "object" && !Array.isArray(v)
        ? Object.fromEntries(Object.entries(v).reverse())
        : v,
    ),
  );
  expect(readCommandMonitor(sorted, monitorContext)).toEqual(model);
});
test("request evidence is rendered without dropping canonical IDs or timestamp precision", async () => {
  const { wrapper } = setup();
  expect(wrapper.get("#command-monitor-summary").attributes("data-command-active-count")).toBe("1");
  const row = wrapper.get('[data-command-request="request-a"]');
  expect(row.get('[data-command-queue="queue-request-a"]').text()).toContain("endpoint-a");
  expect(row.get('[data-command-release="release-request-a"]').text()).toContain("contact-a");
  expect(row.get('[data-command-verifier="verifier-request-a"]').text()).toContain(
    "release-request-a",
  );
  expect(row.get('time[datetime="2026-09-08T12:00:00.123456Z"]').text()).toBe(
    "2026-09-08T12:00:00.123456Z",
  );
  const details = row.get("details").element as HTMLDetailsElement;
  details.open = true;
  await wrapper.setProps({ model: { ...monitorFixture(), observed_at: "2026-09-08T12:05:00Z" } });
  expect(wrapper.get("details").element).toBe(details);
  expect(details.open).toBe(true);
  wrapper.unmount();
});
test("filters navigate once with canonical query and wait for an admitted replacement", async () => {
  const { wrapper, navigate, port } = setup();
  await wrapper.get("#command-monitor-query").setValue("CMD-NOOP");
  await wrapper.get("#command-monitor-filters").trigger("submit");
  expect(navigate).toHaveBeenCalledExactlyOnceWith(
    "/missions/mission-1/ops/commands?query=CMD-NOOP",
  );
  await wrapper.get("#command-monitor-filters").trigger("submit");
  expect(navigate).toHaveBeenCalledTimes(1);
  expect(wrapper.get("#command-monitor-apply").attributes("disabled")).toBeDefined();
  const next = monitorFixture();
  next.query.query = "CMD-NOOP";
  await wrapper.setProps({ model: next, port: { ...port } });
  expect(wrapper.get("#command-monitor-apply").attributes("disabled")).toBeUndefined();
  await wrapper.get("#command-monitor-reset").trigger("click");
  expect(navigate).toHaveBeenLastCalledWith("/missions/mission-1/ops/commands");
  wrapper.unmount();
});
test("focus is URL navigation, survives filters and has scoped clear and native modified links", async () => {
  const { wrapper, navigate, port } = setup();
  const anchor = wrapper.get('[data-command-follow="request-a"]');
  await anchor.trigger("click", { ctrlKey: true });
  expect(navigate).not.toHaveBeenCalled();
  await anchor.trigger("click");
  expect(navigate).toHaveBeenLastCalledWith(
    "/missions/mission-1/ops/commands?focus_command_id=request-a",
  );
  const next = monitorFixture();
  next.query.focus_command_id = "request-a";
  next.focus = { status: "ready", row: required(next.rows[0]) };
  await wrapper.setProps({ model: next, port: { ...port } });
  expect(wrapper.get("#command-monitor-focus").attributes("data-followed-command")).toBe(
    "request-a",
  );
  await wrapper.get("#command-monitor-clear-focus").trigger("click");
  expect(navigate).toHaveBeenLastCalledWith("/missions/mission-1/ops/commands");
  wrapper.unmount();
});
test("oversized multibyte filters remain editable without navigating or locking the page", async () => {
  const { wrapper, navigate } = setup();
  await wrapper.get("#command-monitor-query").setValue("é".repeat(129));
  await wrapper.get("#command-monitor-filters").trigger("submit");
  expect(navigate).not.toHaveBeenCalled();
  expect(wrapper.get("#command-monitor-filter-error").attributes("role")).toBe("alert");
  expect(wrapper.get("#command-monitor-apply").attributes("disabled")).toBeUndefined();
  await wrapper.get("#command-monitor-query").setValue("NOOP");
  await wrapper.get("#command-monitor-filters").trigger("submit");
  expect(navigate).toHaveBeenCalledExactlyOnceWith("/missions/mission-1/ops/commands?query=NOOP");
  expect(wrapper.find("#command-monitor-filter-error").exists()).toBe(false);
  wrapper.unmount();
});

test("pagination preserves filters and focus and disables terminal page navigation", async () => {
  const model = monitorFixture();
  model.total = 26;
  model.pages = 2;
  model.summary.total_count = 26;
  model.summary.active_count = 26;
  model.summary.in_flight_count = 26;
  model.rows = Array.from({ length: 25 }, (_, i) => commandObservation(`request-${i}`));
  model.query = {
    status: "in_flight",
    target: "endpoint-a",
    query: "NOOP",
    page: "1",
    focus_command_id: "request-25",
  };
  model.focus = { status: "ready", row: commandObservation("request-25") };
  const { wrapper, navigate, port } = setup(model);
  expect(wrapper.get("#command-monitor-previous").attributes("disabled")).toBeDefined();
  expect(wrapper.get("#command-monitor-next").attributes("disabled")).toBeUndefined();
  await wrapper.get("#command-monitor-next").trigger("click");
  expect(navigate).toHaveBeenCalledExactlyOnceWith(
    "/missions/mission-1/ops/commands?status=in_flight&target=endpoint-a&query=NOOP&focus_command_id=request-25&page=2",
  );
  const next = {
    ...model,
    query: { ...model.query, page: "2" },
    rows: [commandObservation("request-25")],
  };
  await wrapper.setProps({ model: readCommandMonitor(next, monitorContext), port: { ...port } });
  expect(wrapper.get("#command-monitor-next").attributes("disabled")).toBeDefined();
  expect(wrapper.get("#command-monitor-focus").attributes("data-followed-command")).toBe(
    "request-25",
  );
  await wrapper.get("#command-monitor-previous").trigger("click");
  expect(navigate).toHaveBeenLastCalledWith(
    "/missions/mission-1/ops/commands?status=in_flight&target=endpoint-a&query=NOOP&focus_command_id=request-25",
  );
  wrapper.unmount();
});

test("empty, unavailable focus and verifier truncation are explicit", () => {
  const model = monitorFixture();
  model.total = 0;
  model.rows = [];
  model.status = "empty";
  model.query.focus_command_id = "missing";
  model.focus = { status: "not_found", row: null };
  const { wrapper } = setup(model);
  expect(wrapper.find("#command-monitor-empty").exists()).toBe(true);
  expect(wrapper.get("#command-monitor-focus").text()).toContain("not available");
  wrapper.unmount();
  const limited = monitorFixture();
  const verifier = required(required(limited.rows[0]).verifiers[0]);
  required(limited.rows[0]).verifiers = Array.from({ length: 20 }, (_, i) => ({
    ...verifier,
    id: `v-${i}`,
  }));
  required(limited.rows[0]).verifier_total = 21;
  const view = setup(limited).wrapper;
  expect(view.text()).toContain("Showing 20 of 21 verifier records");
  view.unmount();
});
test("refresh handles rejected reads and query admission rejects unsupported or malformed values", async () => {
  const { wrapper, refresh } = setup();
  refresh.mockRejectedValueOnce(Error("offline"));
  await wrapper.get("#command-monitor-refresh").trigger("click");
  await flushPromises();
  expect(wrapper.get("#command-monitor-refresh").attributes("disabled")).toBeUndefined();
  wrapper.unmount();
  for (const query of [
    { status: "unknown" },
    { page: "0" },
    { page: "2x" },
    { query: "x\n" },
    { focus_command_id: "" },
    { mission_id: "foreign" },
  ])
    expect(() => readMonitorQuery(query)).toThrow();
  expect(monitorHref("mission/a", readMonitorQuery({ focus_command_id: "request/a?b" }))).toBe(
    "/missions/mission%2Fa/ops/commands?focus_command_id=request%2Fa%3Fb",
  );
});

test("managed request review links preserve native modifier clicks and tolerate legacy IDs", async () => {
  const { wrapper, navigate } = setup();
  try {
    const link = wrapper.get('[data-command-review="request-a"]');
    expect(link.attributes("href")).toBe("/missions/mission-1/ops/commands/requests/request-a");
    await link.trigger("click", { ctrlKey: true });
    expect(navigate).not.toHaveBeenCalled();
    await link.trigger("click");
    expect(navigate).toHaveBeenCalledExactlyOnceWith(link.attributes("href"));
    const legacy = monitorFixture();
    legacy.rows = [commandObservation("legacy/request")];
    await wrapper.setProps({ model: readCommandMonitor(legacy, monitorContext) });
    expect(wrapper.find('[data-command-request="legacy/request"]').exists()).toBe(true);
    expect(wrapper.find("[data-command-review]").exists()).toBe(false);
    expect(wrapper.get('[data-command-follow="legacy/request"]').attributes("href")).toContain(
      "legacy%2Frequest",
    );
  } finally {
    wrapper.unmount();
  }
});

test("monitoring operators keep evidence and focus without privileged review links", () => {
  const model = monitorFixture();
  model.can_review = false;
  const { wrapper } = setup(model);
  try {
    expect(wrapper.find('[data-command-request="request-a"]').exists()).toBe(true);
    expect(wrapper.find('[data-command-follow="request-a"]').exists()).toBe(true);
    expect(wrapper.find("[data-command-review]").exists()).toBe(false);
  } finally {
    wrapper.unmount();
  }
});

test("creation uses the public command authoring route only for admitted managers", async () => {
  const c = setup();
  const link = c.wrapper.get("#command-monitor-create");
  expect(link.attributes("href")).toBe(`/missions/${monitorContext.missionId}/ops/commands/new`);
  await link.trigger("click", { ctrlKey: true });
  expect(c.navigate).not.toHaveBeenCalled();
  await link.trigger("click");
  expect(c.navigate).toHaveBeenCalledWith(link.attributes("href"));
  await c.wrapper.setProps({ model: { ...monitorFixture(), can_review: false } });
  expect(c.wrapper.find("#command-monitor-create").exists()).toBe(false);
  c.wrapper.unmount();
});

test.each(["release_pending", "release_uncertain"] as const)(
  "%s holds the lane and preserves evidence navigation",
  (state) => {
    const model = monitorFixture();
    const row = required(model.rows[0]);
    row.status = state === "release_uncertain" ? "indeterminate" : "release_pending";
    row.request_state = "queued";
    required(row.queue).state = "release_pending";
    required(row.release).state = state;
    required(row.release).released_at = null;
    required(row.release).verification_state = null;
    row.verifiers = [];
    row.verifier_total = 0;
    row.verification_state = null;
    model.summary.in_flight_count = 0;
    model.summary[state === "release_uncertain" ? "indeterminate_count" : "release_pending_count"] =
      1;
    const { wrapper } = setup(model);
    try {
      const held = wrapper.get("[data-command-release-held]");
      expect(held.text()).toContain("may have been transmitted");
      expect(held.text()).toContain("will not be automatically retried");
      expect(wrapper.get("[data-command-history]").attributes("href")).toContain(
        "request-a/history",
      );
      expect(wrapper.get("[data-command-state]").attributes("data-command-state")).toBe(row.status);
      expect(wrapper.find("[data-command-verifier]").exists()).toBe(false);
    } finally {
      wrapper.unmount();
    }
  },
);
