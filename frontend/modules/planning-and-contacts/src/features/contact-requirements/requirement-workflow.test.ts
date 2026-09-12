import {
  fixtureRecord,
  fixtureString,
  jsonFixture,
  fixtureContext,
} from "../../../../../test-support/json-fixture";
import { required } from "../../../../../test-support/required";
import { mount, flushPromises } from "@vue/test-utils";
import { decision } from "./requirement-detail";
import { afterEach, expect, test, vi } from "vite-plus/test";
import {
  requirementDirectoryContribution,
  requirementReviewContribution,
} from "../../contact-requirements";
import {
  requirementPageFixture,
  requirementDirectoryFixture,
  requirementOperationFixture,
} from "./requirement-workflow.test-support";
import { admitRequirementDirectory } from "./requirement-directory";
import {
  admitRequirementPage,
  admitRequirementOperation,
  requirementContext,
  type RequirementAction,
} from "./requirement-workflow";
const wrappers: { unmount(): void }[] = [];
afterEach(() => {
  wrappers.splice(0).forEach((w) => w.unmount());
  window.sessionStorage.clear();
});
function harness(initial = requirementPageFixture()) {
  let server = structuredClone(initial);
  const execute = vi.fn(
      async (
        action: RequirementAction,
        input: { sequence: number; payload: unknown },
      ): Promise<unknown> => {
        const op = requirementOperationFixture(server, action, input);
        server = { ...server, sequence: op.sequence, operation: op };
        return op;
      },
    ),
    read = vi.fn(async () => structuredClone(server)),
    navigate = vi.fn();
  const wrapper = mount(requirementReviewContribution.component, {
    props: { page: initial, port: { execute, navigate }, readPort: { read } },
  });
  wrappers.push(wrapper);
  return {
    wrapper,
    execute,
    read,
    navigate,
    get server() {
      return server;
    },
  };
}
test("native creation preserves selection until its exact receipt and opens only the admitted plan", async () => {
  const h = harness();
  await h.wrapper.get("#select-op-1").setValue(true);
  window.dispatchEvent(
    new CustomEvent("cadence:ops-action-result", {
      detail: {
        actionId: "create-plan",
        result: {
          contactPlanId: "untrusted",
          actorId: h.server.detail.context.actor_id,
          planningRunId: required(h.server.detail.selected_run).id,
          requirementEvidence: decision(h.server.detail).requirement_evidence,
        },
      },
    }),
  );
  expect(h.wrapper.get("#requirement-selected-count").text()).toContain("1 selected");
  await h.wrapper.get("#create-contact-plan").trigger("click");
  await flushPromises();
  expect(h.execute).toHaveBeenCalledOnce();
  expect(fixtureRecord(required(h.execute.mock.calls[0])[1].payload).selected_snapshot_ids).toEqual(
    ["op-1"],
  );
  expect(h.wrapper.get("#requirement-selected-count").text()).toContain("0 selected");
  expect(h.wrapper.get("#requirement-review-notice").text()).toContain("refreshed");
  await h.wrapper.get("#requirement-review-open-result").trigger("click");
  expect(h.navigate).toHaveBeenCalledExactlyOnceWith("/missions/mission-1/ops/plans/plan-new");
});
test("lost creation responses recover the matching page receipt without resubmitting or clearing early", async () => {
  const h = harness();
  h.execute.mockImplementationOnce(async (action, input) => {
    const op = requirementOperationFixture(h.server, action, input);
    h.read.mockResolvedValueOnce({ ...h.server, sequence: op.sequence, operation: op });
    throw Error("Lost receipt");
  });
  await h.wrapper.get("#select-op-1").setValue(true);
  await h.wrapper.get("#create-contact-plan").trigger("click");
  await flushPromises();
  expect(h.wrapper.find("#requirement-review-unconfirmed").exists()).toBe(true);
  expect(h.wrapper.get("#requirement-selected-count").text()).toContain("1 selected");
  await h.wrapper.get("#requirement-review-refresh").trigger("click");
  await flushPromises();
  expect(h.wrapper.find("#requirement-review-unconfirmed").exists()).toBe(false);
  expect(h.wrapper.get("#requirement-selected-count").text()).toContain("0 selected");
  expect(h.execute).toHaveBeenCalledOnce();
});
test("unchanged bootstrap copies cannot unlock a pending planning action", async () => {
  const initial = requirementPageFixture(),
    h = harness(initial);
  let settle: ((v: unknown) => void) | undefined;
  h.execute.mockImplementationOnce(
    () =>
      new Promise((resolve) => {
        settle = resolve;
      }),
  );
  await h.wrapper.get("#plan-contact-requirement").trigger("click");
  await h.wrapper.setProps({ page: structuredClone(initial) });
  expect(h.wrapper.get("#plan-contact-requirement").attributes("disabled")).toBeDefined();
  const op = requirementOperationFixture(initial, "plan", required(h.execute.mock.calls[0])[1]);
  h.read.mockResolvedValueOnce({ ...initial, sequence: op.sequence, operation: op });
  required(settle)(op);
  await flushPromises();
  expect(h.wrapper.find("#requirement-review-receipt").exists()).toBe(true);
  expect(h.execute).toHaveBeenCalledOnce();
});
test("failed and foreign reads preserve selected reviewed evidence", async () => {
  const h = harness();
  await h.wrapper.get("#select-op-1").setValue(true);
  h.read.mockResolvedValueOnce({
    ...h.server,
    detail: { ...h.server.detail, context: { ...h.server.detail.context, mission_id: "foreign" } },
  });
  await h.wrapper.get("#requirement-review-refresh").trigger("click");
  await flushPromises();
  expect(h.wrapper.get("#requirement-selected-count").text()).toContain("1 selected");
  expect(h.wrapper.get("#requirement-review-notice").text()).toContain("retained");
});
test("unconfirmed operations and invalid receipt navigation cannot grant further action authority", async () => {
  const h = harness();
  h.execute.mockImplementationOnce(async (action, input) => {
    const op = requirementOperationFixture(h.server, action, input);
    op.receipt.result.navigation.href = "https://foreign.invalid";
    return op;
  });
  await h.wrapper.get("#plan-contact-requirement").trigger("click");
  await flushPromises();
  expect(h.wrapper.find("#requirement-review-unconfirmed").exists()).toBe(true);
  expect(h.wrapper.find("#requirement-review-open-result").exists()).toBe(false);
  expect(h.navigate).not.toHaveBeenCalled();
  await h.wrapper.get("#requirement-review-refresh").trigger("click");
  await flushPromises();
  expect(h.wrapper.get("#plan-contact-requirement").attributes("disabled")).toBeDefined();
});
test("semantic directory data owns native links and captured read recovery", async () => {
  const directory = requirementDirectoryFixture(),
    read = vi.fn().mockResolvedValue({ ...directory, query: { page: 2, state: "all" } });
  const w = mount(requirementDirectoryContribution.component, {
    props: { directory, readPort: { read } },
  });
  wrappers.push(w);
  expect(w.get("#requirements-filter-closed").attributes("href")).toBe(
    "/missions/mission-1/ops/requirements?page=1&state=closed",
  );
  await w.get("#requirement-directory-refresh").trigger("click");
  await flushPromises();
  expect(w.get("#requirement-directory-notice").text()).toContain("retained");
  expect(w.get("#contact-requirements a").attributes("href")).toBe(
    "/missions/mission-1/ops/requirements/requirement-1",
  );
  expect(
    admitRequirementDirectory({
      ...directory,
      requirements: { ...directory.requirements, more: true },
    }),
  ).toBeNull();
});
test("producer supplied native requirement contribution", async () => {
  if (!process.env.CADENCE_REQUIREMENT_WORKFLOW) return;
  const supplied = jsonFixture(process.env.CADENCE_REQUIREMENT_WORKFLOW),
    snapshot = fixtureRecord(supplied.snapshot),
    context = fixtureContext(snapshot.context);
  if (snapshot.id === requirementDirectoryContribution.id) {
    const props = requirementDirectoryContribution.read(snapshot.data, context);
    const w = mount(requirementDirectoryContribution.component, {
      props: { ...props, readPort: { read: vi.fn() } },
    });
    wrappers.push(w);
    expect(w.find("#ops-contact-requirement-list-page").exists()).toBe(true);
    process.stdout.write("REQUIREMENT_CONTRIBUTION_INPUT=null\n");
    return;
  }
  const props = requirementReviewContribution.read(snapshot.data, context),
    page = required(admitRequirementPage(props.page));
  const suppliedOperation =
    supplied.operation === undefined ? undefined : fixtureRecord(supplied.operation);
  const execute = vi.fn(async () => {
    if (supplied.operation) return supplied.operation;
    throw Error("Capture native input");
  });
  const read = vi.fn(async () =>
    supplied.operation
      ? { ...page, sequence: suppliedOperation?.sequence, operation: supplied.operation }
      : page,
  );
  const w = mount(requirementReviewContribution.component, {
    props: { ...props, port: { execute, navigate: vi.fn() }, readPort: { read } },
  });
  wrappers.push(w);
  if (supplied.action === "create-plan") {
    const selection =
      supplied.selected ??
      page.detail.opportunities.entries.filter((o) => o.eligible).map((o) => o.id);
    if (!Array.isArray(selection)) throw Error("Invalid selected fixture ids");
    for (const id of selection.map(fixtureString))
      await w.get(`[id="select-${encodeURIComponent(id)}"]`).setValue(true);
  }
  await w
    .get(supplied.action === "plan" ? "#plan-contact-requirement" : "#create-contact-plan")
    .trigger("click");
  await flushPromises();
  expect(execute).toHaveBeenCalledOnce();
  if (supplied.operation) {
    expect(
      admitRequirementOperation(supplied.operation, requirementContext(page.detail)),
    ).not.toBeNull();
    expect(w.find("#requirement-review-receipt").exists()).toBe(true);
    expect(
      admitRequirementPage({
        ...page,
        sequence: suppliedOperation?.sequence,
        operation: supplied.operation,
      }),
    ).not.toBeNull();
  }
  process.stdout.write(
    "REQUIREMENT_CONTRIBUTION_INPUT=" + JSON.stringify(execute.mock.calls[0]) + "\n",
  );
});
