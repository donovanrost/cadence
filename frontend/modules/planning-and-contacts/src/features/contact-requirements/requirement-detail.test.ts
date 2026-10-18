import { required } from "../../../../../test-support/required";
import { jsonFixture } from "../../../../../test-support/json-fixture";
import type { CreatePlanInput } from "./OpsContactRequirementShow.contracts";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { mount } from "@vue/test-utils";
import { pageHeaderHarness } from "@cadence/plugin-sdk/page-header-testing";
import { nextTick } from "vue";
import OpsContactRequirementShow from "./OpsContactRequirementShow.vue";
import { requirementDetailFixture } from "./requirement-detail.test-support";
import { admitRequirementDetail, decision, detailHref, reviewHref } from "./requirement-detail";
import {
  completedSelection,
  persistSelection,
  restoreSelection,
  selectionStorageKey,
} from "./requirement-selection";

afterEach(() => {
  vi.restoreAllMocks();
  window.sessionStorage.clear();
});

test("producer-supplied review emits through the client-compiled Vue controls", async () => {
  const input = process.env.CADENCE_REQUIREMENT_REVIEW_MODEL;
  const props = input
    ? { detail: required(admitRequirementDetail(jsonFixture(input).detail)) }
    : { detail: requirementDetailFixture() };
  const warnings: string[] = [];
  const app = mount(
    pageHeaderHarness("/missions/:mission_id/ops/requirements/:contact_requirement_id").stage(
      OpsContactRequirementShow,
    ),
    {
      props,
      global: { config: { warnHandler: (message) => warnings.push(message) } },
    },
  );
  try {
    const opportunity = required(props.detail.opportunities.entries[0]);
    const checkbox = app.get("#select-" + opportunity.id);
    expect((checkbox.element as HTMLInputElement).type).toBe("checkbox");
    await checkbox.setValue(true);
    await app.get("#create-contact-plan").trigger("click");
    expect(warnings).toEqual([]);
    const events = app
      .findComponent(OpsContactRequirementShow)
      .emitted<[CreatePlanInput]>("create-plan");
    expect(events).toHaveLength(1);
    expect(required(required(events)[0])[0].selected_snapshot_ids).toEqual([opportunity.id]);
    if (input)
      process.stdout.write(
        "REVIEW_PAYLOAD=" + JSON.stringify(required(required(events)[0])[0]) + "\n",
      );
  } finally {
    app.unmount();
  }
});

test("the restored 100-item selection prevents an additional checkbox choice", async () => {
  const d = requirementDetailFixture();
  required(d.opportunities.entries[0]).id = "op-101";
  const ids = Array.from({ length: 100 }, (_, i) => "op-" + i);
  persistSelection(window.sessionStorage, d, ids);
  const app = mount(
    pageHeaderHarness("/missions/:mission_id/ops/requirements/:contact_requirement_id").stage(
      OpsContactRequirementShow,
    ),
    { props: { detail: d } },
  );
  await nextTick();
  expect(app.get("#select-op-101").attributes("disabled")).toBeDefined();
  await app.get("#create-contact-plan").trigger("click");
  expect(
    required(
      required(
        app.findComponent(OpsContactRequirementShow).emitted<[CreatePlanInput]>("create-plan"),
      )[0],
    )[0].selected_snapshot_ids,
  ).toEqual(ids);
  app.unmount();
});

test("failed tab storage blocks pagination until unsaved selections are cleared", async () => {
  const d = requirementDetailFixture();
  d.query.opportunities_page = 2;
  d.opportunities.page = 2;
  const storage = window.sessionStorage;
  vi.spyOn(window, "sessionStorage", "get").mockReturnValue({
    getItem: storage.getItem.bind(storage),
    setItem: () => {
      throw new Error("Storage unavailable");
    },
    removeItem: storage.removeItem.bind(storage),
    clear: storage.clear.bind(storage),
    key: storage.key.bind(storage),
    get length() {
      return storage.length;
    },
  });
  const app = mount(
    pageHeaderHarness("/missions/:mission_id/ops/requirements/:contact_requirement_id").stage(
      OpsContactRequirementShow,
    ),
    { props: { detail: d } },
  );
  await app.get("#select-op-1").setValue(true);
  const event = new MouseEvent("click", { bubbles: true, cancelable: true });
  app.get("#opportunities-previous-page").element.dispatchEvent(event);
  expect(event.defaultPrevented).toBe(true);
  await app.get("#clear-opportunity-selection").trigger("click");
  expect(app.get("#requirement-selected-count").text()).toContain("0 selected");
  app.unmount();
});

test("real controls emit exact reviewed requirement and run references", async () => {
  const d = requirementDetailFixture(),
    app = mount(
      pageHeaderHarness("/missions/:mission_id/ops/requirements/:contact_requirement_id").stage(
        OpsContactRequirementShow,
      ),
      { props: { detail: d } },
    );
  expect(admitRequirementDetail(d)).toEqual(d);
  expect(app.get("#create-contact-plan").attributes("disabled")).toBeDefined();
  await app.get("#select-op-1").setValue(true);
  await app.get("#create-contact-plan").trigger("click");
  expect(
    app.findComponent(OpsContactRequirementShow).emitted<[CreatePlanInput]>("create-plan"),
  ).toEqual([[{ ...decision(d), planning_run_id: "run-1", selected_snapshot_ids: ["op-1"] }]]);
  app.unmount();
  const search = mount(
    pageHeaderHarness("/missions/:mission_id/ops/requirements/:contact_requirement_id").stage(
      OpsContactRequirementShow,
    ),
    { props: { detail: d } },
  );
  await search.get("#plan-contact-requirement").trigger("click");
  expect(search.findComponent(OpsContactRequirementShow).emitted("plan")).toEqual([[decision(d)]]);
  search.unmount();
});

test("off-page selections survive a same-run remount and page navigation retains review identity", async () => {
  const d = requirementDetailFixture();
  const app = mount(
    pageHeaderHarness("/missions/:mission_id/ops/requirements/:contact_requirement_id").stage(
      OpsContactRequirementShow,
    ),
    { props: { detail: d } },
  );
  await app.get("#select-op-1").setValue(true);
  app.unmount();
  const next = requirementDetailFixture();
  next.query.opportunities_page = 2;
  next.opportunities.page = 2;
  required(next.opportunities.entries[0]).id = "op-2";
  const second = mount(
    pageHeaderHarness("/missions/:mission_id/ops/requirements/:contact_requirement_id").stage(
      OpsContactRequirementShow,
    ),
    { props: { detail: next } },
  );
  await nextTick();
  expect(second.get("#requirement-selected-count").text()).toContain("1 selected across pages");
  expect(second.get("#opportunities-previous-page").attributes("href")).toBe(
    detailHref(next, { opportunities_page: 1 }),
  );
  await second.get("#select-op-2").setValue(true);
  await second.get("#create-contact-plan").trigger("click");
  expect(
    required(
      required(
        second.findComponent(OpsContactRequirementShow).emitted<[CreatePlanInput]>("create-plan"),
      )[0],
    )[0].selected_snapshot_ids,
  ).toEqual(["op-1", "op-2"]);
  second.unmount();
});

test("changing actor or reviewed run clears the tab-local selection", () => {
  const d = requirementDetailFixture();
  for (const change of [
    (v: typeof d) => {
      v.context.actor_id = "another-actor";
    },
    (v: typeof d) => {
      required(v.selected_run).id = "run-2";
      v.query.planning_run_id = "run-2";
    },
  ]) {
    persistSelection(window.sessionStorage, d, ["op-1"]);
    const changed = requirementDetailFixture();
    change(changed);
    expect(restoreSelection(window.sessionStorage, changed)).toEqual({ ids: [], changed: true });
  }
});

test("history, inactive requirements, running runs and ineligible evidence cannot create proposals", async () => {
  for (const change of [
    (d: ReturnType<typeof requirementDetailFixture>) => {
      d.requirement.current_version = 2;
    },
    (d: ReturnType<typeof requirementDetailFixture>) => {
      d.requirement.lifecycle_state = "closed";
    },
    (d: ReturnType<typeof requirementDetailFixture>) => {
      required(d.selected_run).state = "running";
    },
    (d: ReturnType<typeof requirementDetailFixture>) => {
      required(d.opportunities.entries[0]).eligible = false;
    },
  ]) {
    const d = requirementDetailFixture();
    change(d);
    const app = mount(
      pageHeaderHarness("/missions/:mission_id/ops/requirements/:contact_requirement_id").stage(
        OpsContactRequirementShow,
      ),
      { props: { detail: d } },
    );
    expect(app.get("#select-op-1").attributes("disabled")).toBeDefined();
    expect(app.get("#create-contact-plan").attributes("disabled")).toBeDefined();
    expect(
      app.findComponent(OpsContactRequirementShow).emitted<[CreatePlanInput]>("create-plan"),
    ).toBeUndefined();
    app.unmount();
  }
});

test("a lifecycle refresh clears selections without substituting another run", async () => {
  const d = requirementDetailFixture(),
    app = mount(
      pageHeaderHarness("/missions/:mission_id/ops/requirements/:contact_requirement_id").stage(
        OpsContactRequirementShow,
      ),
      { props: { detail: d } },
    );
  await app.get("#select-op-1").setValue(true);
  const next = requirementDetailFixture();
  next.requirement.current_version = 2;
  await app.setProps({ detail: next });
  expect(app.get("#requirement-selected-count").text()).toContain("0 selected");
  expect(app.get("#requirement-selected-run").text()).toContain("run-1");
  expect(app.get("#review-current-requirement").attributes("href")).toBe(reviewHref(next, 2));
  app.unmount();
});

test("malformed and cross-run models render no actions or links", () => {
  const invalid: unknown[] = [null, {}, { ...requirementDetailFixture(), contract_version: 2 }];
  for (const mutate of [
    (d: ReturnType<typeof requirementDetailFixture>) => {
      required(d.opportunities.entries[0]).run_id = "other";
    },
    (d: ReturnType<typeof requirementDetailFixture>) => {
      d.query.version = 2;
    },
    (d: ReturnType<typeof requirementDetailFixture>) => {
      d.opportunities.entries.push(required(d.opportunities.entries[0]));
    },
    (d: ReturnType<typeof requirementDetailFixture>) => {
      d.searches.entries = Array.from({ length: 26 }, () => required(d.searches.entries[0]));
    },
    (d: ReturnType<typeof requirementDetailFixture>) => {
      d.requirement.rationale = "x".repeat(4097);
    },
  ]) {
    const d = requirementDetailFixture();
    mutate(d);
    invalid.push(d);
  }
  for (const detail of invalid) {
    expect(admitRequirementDetail(detail)).toBeNull();
    const app = mount(
      pageHeaderHarness("/missions/:mission_id/ops/requirements/:contact_requirement_id").stage(
        OpsContactRequirementShow,
      ),
      { props: { detail } },
    );
    expect(app.find("#requirement-detail-unavailable").exists()).toBe(true);
    expect(app.find("a,button,input").exists()).toBe(false);
    app.unmount();
  }
});

test("only a matching completed receipt clears selection; storage is bounded and validated", async () => {
  const d = requirementDetailFixture(),
    app = mount(
      pageHeaderHarness("/missions/:mission_id/ops/requirements/:contact_requirement_id").stage(
        OpsContactRequirementShow,
      ),
      { props: { detail: d } },
    );
  await app.get("#select-op-1").setValue(true);
  const result = {
    actorId: "actor-1",
    planningRunId: "run-1",
    contactPlanId: "plan-1",
    requirementEvidence: decision(d).requirement_evidence,
  };
  expect(
    completedSelection(d, { actionId: "create-plan", result: { ...result, actorId: "other" } }),
  ).toBe(false);
  window.dispatchEvent(
    new CustomEvent("cadence:ops-action-result", { detail: { actionId: "create-plan", result } }),
  );
  await nextTick();
  expect(app.get("#requirement-selected-count").text()).toContain("0 selected");
  expect(window.sessionStorage.getItem(selectionStorageKey)).toBeNull();
  expect(() =>
    persistSelection(
      window.sessionStorage,
      d,
      Array.from({ length: 101 }, (_, i) => "op-" + i),
    ),
  ).toThrow();
  window.sessionStorage.setItem(selectionStorageKey, "not json");
  expect(restoreSelection(window.sessionStorage, d)).toEqual({ ids: [], changed: true });
  app.unmount();
});
