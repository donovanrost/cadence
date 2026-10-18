import { producerFixture } from "../../../../../test-support/producer-fixture";
import { containing } from "../../../../../test-support/matchers";
import {
  fixtureRecord,
  fixtureString,
  jsonFixture,
  fixtureContext,
} from "../../../../../test-support/json-fixture";
import { required } from "../../../../../test-support/required";
import { mount, flushPromises } from "@vue/test-utils";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { requirementDeclarationContribution as contribution } from "./declaration.contribution";
import { declarationFixture, declarationOperation } from "./declaration.test-support";
import { admitDeclarationPage, type DeclarationAction } from "./declaration";
const wrappers: { unmount(): void }[] = [];
afterEach(() => wrappers.splice(0).forEach((w) => w.unmount()));
function harness(initial = declarationFixture()) {
  let server = structuredClone(initial),
    guard = () => true;
  const execute = vi.fn(
      async (
        action: DeclarationAction,
        input: { sequence: number; payload: unknown },
      ): Promise<unknown> => {
        const op = declarationOperation(server, action, input);
        server = { ...server, sequence: op.sequence, operation: op };
        if (op.action === "spacecraft-page") server.model.spacecraft = op.receipt.result.spacecraft;
        return op;
      },
    ),
    read = vi.fn(async () => structuredClone(server)),
    navigate = vi.fn(),
    dispose = vi.fn();
  const wrapper = mount(contribution.component, {
    props: {
      page: initial,
      port: {
        execute,
        navigate,
        guardNavigation: (next: () => boolean) => {
          guard = next;
          return dispose;
        },
      },
      readPort: { read },
    },
  });
  wrappers.push(wrapper);
  return {
    wrapper,
    execute,
    read,
    navigate,
    dispose,
    canLeave: () => guard(),
    get server() {
      return server;
    },
  };
}
test("queued save uses the latest native draft after domain validation without duplicating creation", async () => {
  const h = harness();
  let finish: ((v: unknown) => void) | undefined;
  h.execute.mockImplementationOnce(
    () =>
      new Promise((r) => {
        finish = r;
      }),
  );
  await h.wrapper.get("#requirement-rationale").setValue("First draft");
  await h.wrapper.get("#requirement-rationale").setValue("Reviewed latest draft");
  await h.wrapper.get("#contact-requirement-form").trigger("submit");
  expect(h.execute).toHaveBeenCalledTimes(1);
  expect(h.canLeave()).toBe(false);
  required(finish)(
    declarationOperation(h.server, "validate", required(h.execute.mock.calls[0])[1]),
  );
  await flushPromises();
  expect(h.execute).toHaveBeenCalledTimes(2);
  expect(h.execute.mock.calls[1]).toEqual([
    "save",
    containing({
      sequence: 2,
      payload: containing({
        contact_requirement: containing({
          rationale: "Reviewed latest draft",
          earliest_start: "2027-01-01T01:00:37",
        }),
      }),
    }),
  ]);
  expect(h.wrapper.find("#requirement-declaration-receipt").exists()).toBe(true);
  expect(h.canLeave()).toBe(true);
  await h.wrapper.get("#contact-requirement-form").trigger("submit");
  expect(h.execute).toHaveBeenCalledTimes(2);
  await h.wrapper.get("#requirement-declaration-open").trigger("click");
  expect(h.navigate).toHaveBeenCalledExactlyOnceWith(
    "/missions/mission-1/ops/requirements/created-need",
  );
  h.wrapper.unmount();
  expect(h.dispose).toHaveBeenCalledOnce();
});
test("spacecraft paging retains selected craft, edited UTC seconds and rationale", async () => {
  const initial = declarationFixture();
  initial.model.spacecraft = {
    page: 1,
    total: 26,
    entries: Array.from({ length: 25 }, (_, i) => ({
      id: `craft-${i + 1}`,
      name: `Craft ${i + 1}`,
    })),
  };
  const h = harness(initial);
  await h.wrapper.get("#requirement-rationale").setValue("Retain this draft");
  await flushPromises();
  await h.wrapper.get("#requirement-earliest-start").setValue("2027-01-01T02:03:47");
  await flushPromises();
  await h.wrapper.get("#requirement-spacecraft-next").trigger("click");
  await flushPromises();
  expect((h.wrapper.get("#requirement-spacecraft").element as HTMLSelectElement).value).toBe(
    "craft-1",
  );
  expect(h.wrapper.get("#requirement-spacecraft").findAll("option")).toHaveLength(2);
  expect((h.wrapper.get("#requirement-rationale").element as HTMLTextAreaElement).value).toBe(
    "Retain this draft",
  );
  expect(
    (h.wrapper.get("#requirement-earliest-start").element as HTMLInputElement).value,
  ).toContain("02:03:47");
  expect(h.wrapper.get("#requirement-earliest-start").attributes("step")).toBe("1");
  await h.wrapper.get("#contact-requirement-form").trigger("submit");
  await flushPromises();
  expect(
    fixtureRecord(
      fixtureRecord(required(h.execute.mock.calls.at(-1))[1].payload).contact_requirement,
    ).spacecraft_id,
  ).toBe("craft-1");
});
test("lost receipt recovery retains the draft and never repeats the save", async () => {
  const h = harness();
  h.execute.mockImplementationOnce(async (action, input) => {
    const op = declarationOperation(h.server, action, input);
    h.read.mockResolvedValueOnce({ ...h.server, sequence: op.sequence, operation: op });
    throw Error("Lost response");
  });
  await h.wrapper.get("#contact-requirement-form").trigger("submit");
  await flushPromises();
  expect(h.wrapper.find("#requirement-declaration-unconfirmed").exists()).toBe(true);
  await h.wrapper.get("#requirement-declaration-refresh").trigger("click");
  await flushPromises();
  expect(h.wrapper.find("#requirement-declaration-unconfirmed").exists()).toBe(false);
  expect(h.wrapper.find("#requirement-declaration-receipt").exists()).toBe(true);
  expect(h.execute).toHaveBeenCalledOnce();
  h.read.mockRejectedValueOnce(Error("Unavailable"));
  await h.wrapper.get("#requirement-declaration-refresh").trigger("click");
  await flushPromises();
  expect(h.wrapper.find("#requirement-declaration-open").exists()).toBe(true);
});
test("known invalid input can be corrected and stale validation feedback cannot overwrite newer typing", async () => {
  const h = harness();
  h.execute.mockImplementationOnce(async (action, input) => ({
    ...declarationOperation(h.server, action, input),
    status: "rejected",
    receipt: null,
    feedback: ["horizon_order"],
  }));
  await h.wrapper.get("#requirement-rationale").setValue("Bad horizon");
  await flushPromises();
  expect(h.wrapper.get("#contact-requirement-form-error").text()).toContain("end time after");
  await h.wrapper.get("#requirement-rationale").setValue("Corrected draft");
  await flushPromises();
  expect(h.wrapper.find("#contact-requirement-form-error").exists()).toBe(false);
  await h.wrapper.get("#contact-requirement-form").trigger("submit");
  await flushPromises();
  expect(h.wrapper.find("#requirement-declaration-receipt").exists()).toBe(true);
});
test("foreign reads and changed defaults retain the draft and prior context", async () => {
  const h = harness();
  await h.wrapper.get("#requirement-rationale").setValue("Retained");
  await flushPromises();
  for (const change of [
    { context: { ...h.server.model.context, mission_id: "foreign" } },
    { horizon: { ...h.server.model.horizon, earliest_start: "2027-01-01T02:00:00Z" } },
  ]) {
    h.read.mockResolvedValueOnce({ ...h.server, model: { ...h.server.model, ...change } });
    await h.wrapper.get("#requirement-declaration-refresh").trigger("click");
    await flushPromises();
    expect(h.wrapper.get("#requirement-declaration-notice").text()).toContain("Refresh failed");
    expect((h.wrapper.get("#requirement-rationale").element as HTMLTextAreaElement).value).toBe(
      "Retained",
    );
  }
});
test("empty spacecraft context is admitted without enabling declaration", async () => {
  const initial = declarationFixture();
  initial.model.spacecraft = { page: 1, total: 0, entries: [] };
  initial.model.can_declare = false;
  expect(admitDeclarationPage(initial)).not.toBeNull();
  const h = harness(initial);
  expect(h.wrapper.find("#requirement-declaration-empty").exists()).toBe(true);
  await h.wrapper.get("#contact-requirement-form").trigger("submit");
  expect(h.execute).not.toHaveBeenCalled();
});
test("receipt admission rejects other actors, inconsistent choices and malformed fields", () => {
  const page = declarationFixture();
  for (const data of [
    { ...page, sequence: 1 },
    { ...page, model: { ...page.model, spacecraft: { page: 1, total: 26, entries: [] } } },
  ])
    expect(admitDeclarationPage(data)).toBeNull();
  expect(() =>
    contribution.read(page, { organizationId: "foreign", missionId: "mission-1" }),
  ).toThrow();
});
const producer = producerFixture("CADENCE_DECLARATION", import.meta.url);
test.skipIf(!producer.available)("producer supplied native declaration contribution", async () => {
  const supplied = jsonFixture(producer.read()),
    snapshot = fixtureRecord(supplied.snapshot),
    props = contribution.read(snapshot.data, fixtureContext(snapshot.context)),
    page = required(admitDeclarationPage(props.page));
  const operations = supplied.operations;
  if (operations !== undefined && !Array.isArray(operations))
    throw Error("Invalid producer operations");
  const execute = vi.fn(
    async (
      action: DeclarationAction,
      input: { sequence: number; payload: unknown },
    ): Promise<unknown> =>
      operations?.map(fixtureRecord).find((o) => o.sequence === input.sequence) ??
      declarationOperation(page, action, input),
  );
  const w = mount(contribution.component, {
    props: { ...props, port: { execute, navigate: vi.fn() }, readPort: { read: vi.fn() } },
  });
  wrappers.push(w);
  await w
    .get("#requirement-rationale")
    .setValue(
      supplied.rationale === undefined
        ? "Native declaration rationale"
        : fixtureString(supplied.rationale),
    );
  await flushPromises();
  if (supplied.save !== false) {
    await w.get("#contact-requirement-form").trigger("submit");
    await flushPromises();
  }
  if (supplied.operations) {
    expect(w.find("#requirement-declaration-unconfirmed").exists()).toBe(false);
    if (supplied.save !== false)
      expect(w.find("#requirement-declaration-receipt").exists()).toBe(true);
  }
  process.stdout.write("DECLARATION_INPUT=" + JSON.stringify(execute.mock.calls) + "\n");
});

test("oversized Unicode fields remain editable and recover without an unconfirmed operation", async () => {
  const h = harness();
  await h.wrapper.get("#requirement-rationale").setValue("界".repeat(1500));
  await flushPromises();
  expect(h.execute).not.toHaveBeenCalled();
  expect(h.wrapper.get("#contact-requirement-form-error").text()).toContain("Shorten");
  await h.wrapper.get("#requirement-rationale").setValue("Repaired draft");
  await flushPromises();
  expect(h.execute).toHaveBeenCalledOnce();
  expect(h.wrapper.find("#contact-requirement-form-error").exists()).toBe(false);
});
