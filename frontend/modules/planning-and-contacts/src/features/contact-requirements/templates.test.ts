import {
  fixtureRecord,
  fixtureString,
  jsonFixture,
  fixtureContext,
} from "../../../../../test-support/json-fixture";
import { required } from "../../../../../test-support/required";
import { mount, flushPromises } from "@vue/test-utils";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { requirementTemplateContribution as contribution } from "./template.contribution";
import { templateFixture, templateEntry, templateOperation } from "./templates.test-support";
import { admitTemplatePage, admitTemplateOperation, type TemplateAction } from "./templates";
import { requirementSegment } from "./requirement-directory";
const wrappers: { unmount(): void }[] = [];
afterEach(() => wrappers.splice(0).forEach((w) => w.unmount()));
function harness(initial = templateFixture()) {
  let server = structuredClone(initial),
    guard = () => true;
  const execute = vi.fn(
      async (
        action: TemplateAction,
        input: { sequence: number; payload: unknown },
      ): Promise<unknown> => {
        const op = templateOperation(server, action, input);
        server = { ...server, sequence: op.sequence, operation: op };
        if (op.action === "create-template")
          server.model.templates.entries.push({
            ...templateEntry(server),
            reference: op.receipt.result.reference,
          });
        else if (op.action === "templates-page")
          server.model.templates = { page: op.input.page, more: false, entries: [] };
        else if (op.action === "spacecraft-page")
          server.model.spacecraft = {
            page: op.input.page,
            total: 26,
            entries: [{ id: "craft-26", name: "Last spacecraft" }],
          };
        else if (
          op.action === "pause-template" ||
          op.action === "activate-template" ||
          op.action === "close-template"
        ) {
          const reference = op.input.reference;
          const row = server.model.templates.entries.find(
            (e) => e.reference.template_id === reference.template_id,
          );
          if (row) row.reference = op.receipt.result.reference;
        }
        return op;
      },
    ),
    read = vi.fn(async () => structuredClone(server)),
    dispose = vi.fn();
  const wrapper = mount(contribution.component, {
    props: {
      page: initial,
      port: {
        execute,
        navigate: vi.fn(),
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
    dispose,
    canLeave: () => guard(),
    get server() {
      return server;
    },
  };
}
test("native creation queues behind validation, preserves UTC seconds and resets only the confirmed draft", async () => {
  const h = harness();
  let finish: ((v: unknown) => void) | undefined;
  await h.wrapper.get("#template-spacecraft").setValue("craft-1");
  await flushPromises();
  h.execute.mockImplementationOnce(
    () =>
      new Promise((r) => {
        finish = r;
      }),
  );
  await h.wrapper.get("#template-rationale").setValue("First draft");
  await h.wrapper.get("#template-rationale").setValue("Reviewed latest draft");
  await h.wrapper.get("#requirement-template-form").trigger("submit");
  expect(h.canLeave()).toBe(false);
  expect(h.execute).toHaveBeenCalledTimes(2);
  required(finish)(
    templateOperation(h.server, "validate-template", required(h.execute.mock.calls[1])[1]),
  );
  await flushPromises();
  expect(h.execute).toHaveBeenCalledTimes(3);
  const [event, input] = required(h.execute.mock.calls[2]);
  expect(event).toBe("create-template");
  expect(fixtureRecord(input.payload).template).toMatchObject({
    rationale: "Reviewed latest draft",
    anchor_at: "2027-01-01T01:00:37",
  });
  expect(h.wrapper.get("#template-anchor-at").attributes("step")).toBe("1");
  expect(h.wrapper.find("#requirement-template-receipt").exists()).toBe(true);
  expect((h.wrapper.get("#template-rationale").element as HTMLTextAreaElement).value).toBe("");
  expect(h.canLeave()).toBe(true);
});
test("lifecycle actions carry the displayed version, hash and lifecycle evidence and refresh before another change", async () => {
  const initial = templateFixture();
  initial.model.templates.entries = [templateEntry(initial)];
  const h = harness(initial);
  await h.wrapper.get("#template-rationale").setValue("Unsaved separate template");
  await flushPromises();
  await h.wrapper.get("#pause-template-template-1").trigger("click");
  await flushPromises();
  expect(h.execute.mock.calls[1]).toEqual([
    "pause-template",
    { sequence: 2, payload: { reference: required(initial.model.templates.entries[0]).reference } },
  ]);
  expect(h.wrapper.find("#activate-template-template-1").exists()).toBe(true);
  expect((h.wrapper.get("#template-rationale").element as HTMLTextAreaElement).value).toBe(
    "Unsaved separate template",
  );
  await h.wrapper.get("#activate-template-template-1").trigger("click");
  await flushPromises();
  await h.wrapper.get("#close-template-template-1").trigger("click");
  await flushPromises();
  expect(h.wrapper.find("#close-template-template-1").exists()).toBe(false);
  expect(h.wrapper.get("#requirement-template-receipt").text()).toContain("closed");
});
test("lost lifecycle response recovers the matching receipt without replaying the action", async () => {
  const initial = templateFixture();
  initial.model.templates.entries = [templateEntry(initial)];
  const h = harness(initial);
  h.execute.mockImplementationOnce(async (action, input) => {
    const op = templateOperation(h.server, action, input);
    const recovered = structuredClone(h.server);
    recovered.sequence = op.sequence;
    recovered.operation = op;
    if (op.action !== "pause-template") throw Error("Expected the pause receipt");
    required(recovered.model.templates.entries[0]).reference = op.receipt.result.reference;
    h.read.mockResolvedValueOnce(recovered);
    throw Error("Lost response");
  });
  await h.wrapper.get("#pause-template-template-1").trigger("click");
  await flushPromises();
  expect(h.wrapper.find("#requirement-template-unconfirmed").exists()).toBe(true);
  await h.wrapper.get("#requirement-template-refresh").trigger("click");
  await flushPromises();
  expect(h.wrapper.find("#requirement-template-unconfirmed").exists()).toBe(false);
  expect(h.wrapper.find("#activate-template-template-1").exists()).toBe(true);
  expect(h.execute).toHaveBeenCalledOnce();
});
test("stale lifecycle rejection requires a fresh ledger while failed reads retain dirty inputs", async () => {
  const initial = templateFixture();
  initial.model.templates.entries = [templateEntry(initial)];
  const h = harness(initial);
  await h.wrapper.get("#template-rationale").setValue("Retained draft");
  await flushPromises();
  h.execute.mockImplementationOnce(async (action, input) => {
    const op = {
      ...templateOperation(h.server, action, input),
      status: "rejected" as const,
      receipt: null,
      feedback: ["stale_evidence" as const],
    };
    h.read.mockResolvedValueOnce({ ...h.server, sequence: op.sequence, operation: op });
    return op;
  });
  await h.wrapper.get("#pause-template-template-1").trigger("click");
  await flushPromises();
  expect(h.wrapper.get("fieldset").attributes("disabled")).toBeDefined();
  await h.wrapper.get("#requirement-template-refresh").trigger("click");
  await flushPromises();
  expect(h.wrapper.get("fieldset").attributes("disabled")).toBeUndefined();
  h.read.mockRejectedValueOnce(Error("Unavailable"));
  await h.wrapper.get("#requirement-template-refresh").trigger("click");
  await flushPromises();
  expect((h.wrapper.get("#template-rationale").element as HTMLTextAreaElement).value).toBe(
    "Retained draft",
  );
});
test("template and spacecraft paging retain the selected spacecraft and unsaved recurrence", async () => {
  const initial = templateFixture();
  initial.model.templates = {
    page: 1,
    more: true,
    entries: Array.from({ length: 25 }, (_, i) => templateEntry(initial, `template-${i}`)),
  };
  initial.model.spacecraft = {
    page: 1,
    total: 26,
    entries: Array.from({ length: 25 }, (_, i) => ({
      id: `craft-${i + 1}`,
      name: `Craft ${i + 1}`,
    })),
  };
  const h = harness(initial);
  await h.wrapper.get("#template-spacecraft").setValue("craft-1");
  await flushPromises();
  await h.wrapper.get("#template-rationale").setValue("Preserved recurrence");
  await flushPromises();
  await h.wrapper.get("#template-spacecraft-next").trigger("click");
  await flushPromises();
  expect((h.wrapper.get("#template-spacecraft").element as HTMLSelectElement).value).toBe(
    "craft-1",
  );
  expect(h.wrapper.get("#template-spacecraft").findAll("option")).toHaveLength(3);
  await h.wrapper.get("#requirement-templates-next").trigger("click");
  await flushPromises();
  expect((h.wrapper.get("#template-rationale").element as HTMLTextAreaElement).value).toBe(
    "Preserved recurrence",
  );
  expect(h.wrapper.find("#requirement-templates-previous").exists()).toBe(true);
});
test("non-administrators receive the ledger without creation or lifecycle actions", () => {
  const initial = templateFixture();
  initial.model.can_manage = false;
  initial.model.templates.entries = [templateEntry(initial)];
  const h = harness(initial);
  expect(h.wrapper.find("#requirement-template-form").exists()).toBe(false);
  expect(h.wrapper.find("#pause-template-template-1").exists()).toBe(false);
  expect(h.wrapper.find("#requirement-template-admin-required").exists()).toBe(true);
});
test("contracts reject foreign receipts, changed defaults and malformed ledgers", () => {
  const initial = templateFixture();
  expect(
    admitTemplatePage({
      ...initial,
      model: { ...initial.model, templates: { page: 1, more: true, entries: [] } },
    }),
  ).toBeNull();
  expect(admitTemplatePage(initial, { mission_id: "foreign" })).toBeNull();
  expect(
    admitTemplatePage(initial, initial.model.context, {
      ...initial.model.defaults,
      time_utc: "00:00:00",
    }),
  ).toBeNull();
  const op = templateOperation(initial, "pause-template", {
    sequence: 1,
    payload: { reference: templateEntry(initial).reference },
  });
  op.receipt.result.reference.version = 2;
  expect(admitTemplateOperation(op, initial.model.context)).toBeNull();
});
test("producer supplied native template contribution", async () => {
  if (!process.env.CADENCE_TEMPLATE_WORKFLOW) return;
  const supplied = jsonFixture(process.env.CADENCE_TEMPLATE_WORKFLOW),
    snapshot = fixtureRecord(supplied.snapshot),
    props = contribution.read(snapshot.data, fixtureContext(snapshot.context)),
    page = required(admitTemplatePage(props.page));
  const operations = supplied.operations;
  if (operations !== undefined && !Array.isArray(operations))
    throw Error("Invalid producer operations");
  let last: Record<string, unknown> | null = null;
  const execute = vi.fn(
    async (
      action: TemplateAction,
      input: { sequence: number; payload: unknown },
    ): Promise<unknown> => {
      last =
        operations?.map(fixtureRecord).find((o) => o.sequence === input.sequence) ??
        templateOperation(page, action, input);
      return last;
    },
  );
  const w = mount(contribution.component, {
    props: {
      ...props,
      port: { execute, navigate: vi.fn() },
      readPort: {
        read: vi.fn(async () =>
          last ? { ...page, sequence: last.sequence, operation: last } : page,
        ),
      },
    },
  });
  wrappers.push(w);
  if (supplied.action === "create-template") {
    await w.get("#template-spacecraft").setValue(required(page.model.spacecraft.entries[0]).id);
    await flushPromises();
    await w.get("#template-rationale").setValue("Native recurring requirement");
    await flushPromises();
    await w.get("#requirement-template-form").trigger("submit");
    await flushPromises();
  } else if (supplied.action) {
    const id =
      supplied.id === undefined
        ? required(page.model.templates.entries[0]).reference.template_id
        : fixtureString(supplied.id);
    await w
      .get(`[id="${fixtureString(supplied.action)}-${requirementSegment(id)}"]`)
      .trigger("click");
    await flushPromises();
  }
  if (supplied.operations) {
    expect(w.find("#requirement-template-unconfirmed").exists()).toBe(false);
    expect(w.find("#requirement-template-receipt").exists()).toBe(true);
  }
  process.stdout.write("TEMPLATE_CONTRIBUTION_INPUT=" + JSON.stringify(execute.mock.calls) + "\n");
});

test("oversized Unicode fields remain editable and recover without an unconfirmed operation", async () => {
  const h = harness();
  await h.wrapper.get("#template-rationale").setValue("界".repeat(1500));
  await flushPromises();
  expect(h.execute).not.toHaveBeenCalled();
  expect(h.wrapper.get("#requirement-template-feedback").text()).toContain("Shorten");
  await h.wrapper.get("#template-rationale").setValue("Repaired draft");
  await flushPromises();
  expect(h.execute).toHaveBeenCalledOnce();
  expect(h.wrapper.find("#requirement-template-feedback").exists()).toBe(false);
});
