import { flushPromises, mount } from "@vue/test-utils";
import { expect, test, vi } from "vite-plus/test";
import { OpsFleetPlanningRun } from "../../fleet-planning";
import { admitFleetRun } from "./fleet-run";
import { runFixture, repairFixture, runReceipt } from "./fleet-run.test-support";
import { startCompletion } from "./fleet-start.test-support";
function harness(model = runFixture()) {
  const execute = vi
      .fn()
      .mockImplementation(async (action: "continue" | "repair") =>
        startCompletion(runReceipt(model, action)),
      ),
    refresh = vi.fn().mockResolvedValue(model);
  const wrapper = mount(OpsFleetPlanningRun, {
    props: { run: model, port: { context: model.context, execute, refresh } },
  });
  return { model, wrapper, execute, refresh };
}
test("refresh is read-only and continuation carries exact observed run evidence", async () => {
  const h = harness();
  await h.wrapper.get("#fleet-run-refresh").trigger("click");
  await flushPromises();
  expect(h.execute).not.toHaveBeenCalled();
  await h.wrapper.get("#fleet-run-continue").trigger("click");
  await flushPromises();
  expect(h.execute).toHaveBeenCalledExactlyOnceWith("continue", {
    fleet_planning_run_id: h.model.id,
    evidence: h.model.evidence,
  });
  expect(h.wrapper.get("#fleet-run-receipt-link").attributes("href")).toBe(
    "/missions/mission-one/ops/planning/runs/run-one",
  );
  expect((h.wrapper.get("#fleet-run-continue").element as HTMLButtonElement).disabled).toBe(true);
  h.wrapper.unmount();
});
test("native repair pins the reviewed Plan, policy and locked commitments", async () => {
  const h = harness(repairFixture());
  expect(h.wrapper.get("#fleet-run-candidate").attributes("href")).toBe(
    "/missions/mission-one/ops/plans/plan-one?version=2",
  );
  await h.wrapper.get("#fleet-run-repair-start").setValue("2026-09-09T05:00:00");
  await h.wrapper.get("#fleet-run-repair-form").trigger("submit");
  await flushPromises();
  expect(h.execute).toHaveBeenCalledExactlyOnceWith("repair", {
    fleet_planning_run_id: h.model.id,
    evidence: h.model.repair.evidence,
    repair: { horizon_start: "2026-09-09T05:00:00.000Z", horizon_end: "2026-09-09T08:00:00.000Z" },
  });
  expect(h.wrapper.get("#fleet-run-receipt-link").attributes("href")).toContain("/runs/repair-one");
  h.wrapper.unmount();
});
test("repair horizons and terminal continuation are disabled before effects", async () => {
  const h = harness(repairFixture());
  expect(h.wrapper.find("#fleet-run-continue").exists()).toBe(false);
  await h.wrapper.get("#fleet-run-repair-end").setValue("2026-09-10T08:00:00");
  expect((h.wrapper.get("#fleet-run-repair-submit").element as HTMLButtonElement).disabled).toBe(
    true,
  );
  await h.wrapper.get("#fleet-run-repair-form").trigger("submit");
  expect(h.execute).not.toHaveBeenCalled();
  h.wrapper.unmount();
});
test("unknown outcomes stay locked through successful read recovery", async () => {
  const h = harness();
  h.execute.mockRejectedValueOnce(Error("lost"));
  await h.wrapper.get("#fleet-run-continue").trigger("click");
  await flushPromises();
  expect(h.wrapper.find("#fleet-run-uncertain").exists()).toBe(true);
  await h.wrapper.get("#fleet-run-refresh").trigger("click");
  await flushPromises();
  expect((h.wrapper.get("#fleet-run-continue").element as HTMLButtonElement).disabled).toBe(true);
  expect(h.execute).toHaveBeenCalledTimes(1);
  h.wrapper.unmount();
});
test("failed reads retain confirmed receipts and input evidence", async () => {
  const h = harness();
  await h.wrapper.get("#fleet-run-continue").trigger("click");
  await flushPromises();
  h.refresh.mockRejectedValueOnce(Error("lost"));
  await h.wrapper.get("#fleet-run-refresh").trigger("click");
  await flushPromises();
  expect(h.wrapper.find("#fleet-run-receipt").exists()).toBe(true);
  expect(h.wrapper.find("#fleet-run-input-ref-one").exists()).toBe(true);
  h.wrapper.unmount();
});
test("paged native links preserve independent evidence selectors", () => {
  const m = runFixture();
  m.query.decisions_page = 2;
  m.decisions.page = 2;
  m.requirements.total = 11;
  m.requirements.more = true;
  m.requirements.entries = Array.from({ length: 10 }, (_, i) => ({
    ...m.requirements.entries[0]!,
    id: `ref-${i}`,
    requirement_id: `req-${i}`,
  }));
  const h = harness(m);
  expect(h.wrapper.get("#fleet-run-requirements_page-next").attributes("href")).toBe(
    "/missions/mission-one/ops/planning/runs/run-one?requirements_page=2&decisions_page=2",
  );
  h.wrapper.unmount();
});
test("foreign, inconsistent and malformed evidence fail admission", () => {
  const original = repairFixture();
  for (const change of [
    (m: any) => (m.context.mission_id = "foreign"),
    (m: any) => (m.evidence.sha256 = "short"),
    (m: any) => m.repair.evidence.plan_version++,
    (m: any) => (m.repair.evidence.run_sha256 = "a".repeat(64)),
    (m: any) => (m.policy = null),
    (m: any) => delete m.requirements.total,
    (m: any) => delete m.resources.total,
    (m: any) => delete m.repair.commitments.total,
    (m: any) => (m.algorithm.key = "\ud800"),
    (m: any) => (m.requirements.more = true),
    (m: any) => (m.decisions.entries[0].disposition = "invented"),
    (m: any) => (m.resources.entries[0].over_capacity = true),
    (m: any) => (m.query.requirements_page = 0),
  ]) {
    const m = structuredClone(original);
    change(m);
    expect(admitFleetRun(m, original.context)).toBeNull();
  }
});
test("a policy allowing zero repairs remains a readable terminal review", () => {
  const model = repairFixture();
  model.repair.policy!.max_attempts = 0;
  model.repair.available = false;
  expect(admitFleetRun(model)).not.toBeNull();
  const h = harness(model);
  expect(h.wrapper.find("#fleet-run-repair-submit").exists()).toBe(false);
  h.wrapper.unmount();
});
test("departed actions cannot apply a late receipt", async () => {
  const h = harness();
  let resolve!: (v: unknown) => void;
  h.execute.mockImplementationOnce(
    () =>
      new Promise((r) => {
        resolve = r;
      }),
  );
  await h.wrapper.get("#fleet-run-continue").trigger("click");
  const next = runFixture();
  next.evidence.sha256 = "f".repeat(64);
  await h.wrapper.setProps({ run: next });
  resolve(startCompletion(runReceipt(h.model, "continue")));
  await flushPromises();
  expect(h.wrapper.find("#fleet-run-receipt").exists()).toBe(false);
  expect(h.wrapper.find("#fleet-run-uncertain").exists()).toBe(true);
  h.wrapper.unmount();
});
test("producer-supplied fleet run workflow", async () => {
  if (!process.env.CADENCE_FLEET_RUN) return;
  const supplied = JSON.parse(process.env.CADENCE_FLEET_RUN);
  expect(admitFleetRun(supplied.model)).not.toBeNull();
  const h = harness(supplied.model);
  if (supplied.action === "render") {
    expect(h.wrapper.find("#ops-fleet-planning-run-page").exists()).toBe(true);
    h.wrapper.unmount();
    return;
  }
  h.execute.mockRejectedValueOnce(Error("Captured"));
  if (supplied.action === "continue") await h.wrapper.get("#fleet-run-continue").trigger("click");
  else {
    await h.wrapper
      .get("#fleet-run-repair-start")
      .setValue(supplied.window.horizon_start.slice(0, 19));
    await h.wrapper.get("#fleet-run-repair-end").setValue(supplied.window.horizon_end.slice(0, 19));
    await h.wrapper.get("#fleet-run-repair-form").trigger("submit");
  }
  await flushPromises();
  expect(h.execute.mock.calls[0]?.[0]).toBe(supplied.action);
  process.stdout.write(`FLEET_RUN_PAYLOAD=${JSON.stringify(h.execute.mock.calls[0]![1])}\n`);
  h.wrapper.unmount();
});

test("fresh evidence after continuation enables repair without unlocking a later uncertain action", async () => {
  const h = harness();
  await h.wrapper.get("#fleet-run-continue").trigger("click");
  await flushPromises();
  const next = repairFixture();
  next.evidence.sha256 = "f".repeat(64);
  next.repair.evidence!.run_sha256 = next.evidence.sha256;
  h.refresh.mockResolvedValue(next);
  await h.wrapper.get("#fleet-run-refresh").trigger("click");
  await flushPromises();
  expect((h.wrapper.get("#fleet-run-repair-submit").element as HTMLButtonElement).disabled).toBe(
    false,
  );
  h.execute.mockRejectedValueOnce(Error("Unconfirmed repair"));
  await h.wrapper.get("#fleet-run-repair-form").trigger("submit");
  await flushPromises();
  await h.wrapper.get("#fleet-run-refresh").trigger("click");
  await flushPromises();
  expect((h.wrapper.get("#fleet-run-repair-submit").element as HTMLButtonElement).disabled).toBe(
    true,
  );
  expect(h.wrapper.find("#fleet-run-uncertain").exists()).toBe(true);
  h.wrapper.unmount();
});
