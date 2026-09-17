import { producerFixture } from "../../../../../test-support/producer-fixture";
import { containing } from "../../../../../test-support/matchers";
import {
  jsonFixture,
  fixtureContext,
  fixtureString,
} from "../../../../../test-support/json-fixture";
import { required } from "../../../../../test-support/required";
import { fixtureArrayAt, fixtureRecordAt } from "../../../../../test-support/json-fixture";
import { readFileSync, writeFileSync } from "node:fs";
import { mount, flushPromises } from "@vue/test-utils";
import { test, expect, vi } from "vite-plus/test";
import StageWorkbench from "./StageWorkbench.vue";
import { workbenchFixture, itemPreviewFixture, batchPreviewFixture } from "./fixtures.test-support";
import { readWorkbenchPage } from "./contracts";
function setup(page = workbenchFixture(), execute = vi.fn(), read = vi.fn()) {
  const navigate = vi.fn(),
    dispose = vi.fn(),
    guardNavigation = vi.fn((_guard: () => boolean) => dispose);
  return {
    execute,
    read,
    navigate,
    dispose,
    guardNavigation,
    wrapper: mount(StageWorkbench, {
      props: { page, port: { execute, navigate, guardNavigation }, readPort: { read } },
    }),
  };
}
test("an unsupported command definition leaves draft inspection available without offering a preview", () => {
  const page = workbenchFixture();
  required(required(page.catalog).selected_command).supported = false;
  const c = setup(page);
  try {
    expect(c.wrapper.find("#stage-command-unsupported").exists()).toBe(true);
    expect(c.wrapper.find("#stage-command-form").exists()).toBe(false);
    expect(c.wrapper.find("#stage-items").exists()).toBe(true);
    expect(c.execute).not.toHaveBeenCalled();
  } finally {
    c.wrapper.unmount();
  }
});
test("draft controls preserve optional false, defaults and fixed values in finite preview input", async () => {
  const page = workbenchFixture(),
    preview = itemPreviewFixture(),
    c = setup(
      page,
      vi.fn(async () => ({ status: "previewed", preview })),
    );
  try {
    await c.wrapper.get('[data-argument-name="amount"]').setValue("2");
    await c.wrapper.get('[data-argument-name="enabled"]').setValue("false");
    await c.wrapper.get("#stage-command-form").trigger("submit");
    await flushPromises();
    expect(c.execute).toHaveBeenCalledExactlyOnceWith("preview_item", {
      expected_stage: page.workbench.stage.expected_stage,
      expected_item: null,
      command: {
        expected_basis: required(page.catalog).basis.token,
        source_endpoint_ref: "target_one",
        command_id: "command_one",
        argument_values_json: JSON.stringify({ amount: 2, delay_s: 5, enabled: false }),
        priority: 3,
        not_before: null,
        expires_at: null,
      },
    });
    expect(c.wrapper.get("#stage-item-preview").text()).toContain("primary");
    expect(c.wrapper.find('[data-argument-name="channel"]').exists()).toBe(false);
  } finally {
    c.wrapper.unmount();
  }
});
test("unknown draft save is consumed and its exact item receipt is recovered by a read", async () => {
  const page = workbenchFixture();
  page.item_preview = itemPreviewFixture();
  const result = {
    status: "completed",
    event: "save_item",
    write_token: required(page.write_token),
    receipt: {
      operation: "item_created",
      actor_id: "user_one",
      stage_id: "stage_one",
      item_id: "item_new",
      updated_at: "2026-09-10T12:00:00Z",
    },
  };
  const next = { ...page, write_token: "1".repeat(64), item_preview: null, operation: result };
  const c = setup(
    page,
    vi.fn().mockRejectedValueOnce(Error("lost")),
    vi.fn(async () => next),
  );
  try {
    await c.wrapper.get("#stage-item-save").trigger("click");
    await flushPromises();
    expect(c.execute).toHaveBeenCalledOnce();
    expect(c.wrapper.get("#stage-item-save").attributes("disabled")).toBeDefined();
    await c.wrapper.get("#stage-workbench-refresh").trigger("click");
    await flushPromises();
    expect(c.wrapper.get("#stage-workbench-result").text()).toContain("item_new");
    expect(c.wrapper.find("#stage-item-preview").exists()).toBe(false);
    expect(c.execute).toHaveBeenCalledOnce();
  } finally {
    c.wrapper.unmount();
  }
});
test("notes and order remain editable without a current model and advance the write nonce after a known result", async () => {
  const page = workbenchFixture(true);
  page.catalog = null;
  const next = structuredClone(page);
  next.write_token = "1".repeat(64);
  required(next.workbench.selected_item).notes = "Keep for later";
  required(next.workbench.selected_item).order = 7;
  required(next.workbench.selected_item).expected_item = "2".repeat(64);
  next.workbench.items.entries = [
    { ...required(next.workbench.selected_item), argument_values_json: null },
  ];
  const operation = {
    status: "completed" as const,
    event: "edit_details",
    write_token: required(page.write_token),
    receipt: {
      operation: "item_updated",
      actor_id: "user_one",
      stage_id: "stage_one",
      item_id: "item_one",
      updated_at: "2026-09-10T12:00:00Z",
    },
  };
  next.operation = operation;
  const c = setup(
    page,
    vi.fn(async () => operation),
    vi.fn(async () => next),
  );
  try {
    expect(c.wrapper.find("#stage-model-unavailable").exists()).toBe(true);
    await c.wrapper.get("#stage-item-notes").setValue("Keep for later");
    await c.wrapper.get("#stage-item-order").setValue("7");
    await c.wrapper.get("#stage-item-details-form").trigger("submit");
    await flushPromises();
    expect(c.execute).toHaveBeenCalledWith("edit_details", {
      expected_write: page.write_token,
      expected_stage: page.workbench.stage.expected_stage,
      expected_item: required(page.workbench.selected_item).expected_item,
      notes: "Keep for later",
      order: 7,
    });
    await c.wrapper.get("#stage-item-cancel-confirm").setValue(true);
    await c.wrapper.get("#stage-item-cancel").trigger("click");
    await flushPromises();
    expect(required(c.execute.mock.calls[1])[1]).toEqual({
      expected_write: next.write_token,
      expected_stage: next.workbench.stage.expected_stage,
      expected_item: required(next.workbench.selected_item).expected_item,
    });
  } finally {
    c.wrapper.unmount();
  }
});
test("batch submission requires explicit selection and reviewed confirmation, then checks exact reserved receipts", async () => {
  const page = workbenchFixture(),
    preview = batchPreviewFixture();
  const completed = {
    status: "completed" as const,
    event: "submit",
    write_token: required(page.write_token),
    receipt: {
      operation: "requests_created",
      stage_id: "stage_one",
      actor_id: "user_one",
      requests: preview.requests.map((r) => ({
        request_id: r.request_id,
        item_id: r.item_id,
        state: r.lifecycle_state,
        requested_at: r.requested_at,
      })),
    },
  };
  const next = structuredClone(page);
  next.operation = completed;
  next.write_token = "1".repeat(64);
  next.workbench.stage.state = "submitted";
  next.workbench.stage.can_edit_items = false;
  next.workbench.stage.can_edit_stage = false;
  required(next.workbench.items.entries[0]).state = "submitted";
  required(next.workbench.items.entries[0]).request_id = "request_one";
  const execute = vi
      .fn()
      .mockResolvedValueOnce({ status: "previewed", preview })
      .mockResolvedValueOnce(completed),
    c = setup(
      page,
      execute,
      vi.fn(async () => next),
    );
  try {
    expect(c.wrapper.get("#stage-preview-batch").attributes("disabled")).toBeDefined();
    await c.wrapper.get('[data-select-item="item_one"]').setValue(true);
    await c.wrapper.get("#stage-preview-batch").trigger("click");
    await flushPromises();
    expect(execute).toHaveBeenNthCalledWith(1, "preview_batch", {
      expected_stage: page.workbench.stage.expected_stage,
      items: [{ id: "item_one", expected_item: "d".repeat(64) }],
    });
    expect(c.wrapper.get("#stage-batch-submit").attributes("disabled")).toBeDefined();
    await c.wrapper.get("#stage-batch-confirm").setValue(true);
    await c.wrapper.get("#stage-batch-submit").trigger("click");
    await flushPromises();
    expect(execute).toHaveBeenNthCalledWith(2, "submit", {
      expected_write: page.write_token,
      expected_preview: preview.token,
    });
    expect(c.wrapper.get('[data-created-request="request_one"]').attributes("href")).toContain(
      "/requests/request_one",
    );
    expect(c.wrapper.find("#stage-command-editor").exists()).toBe(false);
  } finally {
    c.wrapper.unmount();
  }
});
test("selection edits invalidate the reviewed batch and late previews cannot reach a disposed feature", async () => {
  const page = workbenchFixture(),
    c = setup(
      page,
      vi.fn(async () => ({ status: "previewed", preview: batchPreviewFixture() })),
    );
  try {
    await c.wrapper.get('[data-select-item="item_one"]').setValue(true);
    await c.wrapper.get("#stage-preview-batch").trigger("click");
    await flushPromises();
    expect(c.wrapper.find("#stage-batch-preview").exists()).toBe(true);
    await c.wrapper.get('[data-select-item="item_one"]').setValue(false);
    expect(c.wrapper.find("#stage-batch-preview").exists()).toBe(false);
  } finally {
    c.wrapper.unmount();
  }
  let resolve!: (value: unknown) => void;
  const pending = setup(
    page,
    vi.fn(
      () =>
        new Promise((r) => {
          resolve = r;
        }),
    ),
  );
  await pending.wrapper.get('[data-argument-name="amount"]').setValue("2");
  await pending.wrapper.get("#stage-command-form").trigger("submit");
  expect(required(pending.guardNavigation.mock.calls[0])[0]()).toBe(false);
  pending.wrapper.unmount();
  resolve({ status: "previewed", preview: itemPreviewFixture() });
  await flushPromises();
  expect(pending.dispose).toHaveBeenCalledOnce();
});
test("foreign contexts, privacy claims, cursor ties, forged receipts and malformed argument documents are rejected", () => {
  const p = workbenchFixture(true);
  expect(readWorkbenchPage(p, p.workbench.context)).toEqual(p);
  for (const change of [
    (x: unknown) => (fixtureRecordAt(x, "workbench", "context").missionId = "other"),
    (x: unknown) => (fixtureRecordAt(x, "workbench", "stage").owner_id = "other"),
    (x: unknown) =>
      fixtureArrayAt(x, "workbench", "items", "entries").push(
        fixtureArrayAt(x, "workbench", "items", "entries")[0],
      ),
    (x: unknown) => (fixtureRecordAt(x, "workbench", "query").after_order = "1"),
    (x: unknown) => (fixtureRecordAt(x, "workbench", "selected_item").id = "other"),
    (x: unknown) =>
      (fixtureRecordAt(x, "workbench", "selected_item").argument_values_json = '{"amount":null}'),
    (x: unknown) => (fixtureRecordAt(x, "workbench").version = 1),
    (x: unknown) =>
      (fixtureRecordAt(x, "workbench", "selected_item").argument_values = { amount: 2 }),
    (x: unknown) => (fixtureRecordAt(x, "catalog").actor_id = "other"),
  ]) {
    const next = structuredClone(p);
    change(next);
    expect(() => readWorkbenchPage(next, p.workbench.context)).toThrow();
  }
});
const producer = producerFixture("CADENCE_COMMAND_STAGES_DOCUMENT", import.meta.url);
test.skipIf(!producer.available)(
  "actual producer stage workbench controls yield finite Phoenix actions",
  async () => {
    const source = producer.read();
    const document = jsonFixture(readFileSync(source, "utf8")),
      page = readWorkbenchPage(document.data, fixtureContext(document.context)),
      execute = vi.fn(async (_event: string, _input: Record<string, unknown>) => ({
        status: "rejected",
        feedback: "Probe only",
      })),
      c = setup(page, execute);
    const mode = process.env.CADENCE_COMMAND_STAGES_MODE;
    try {
      if (mode === "save_item") {
        await c.wrapper.get("#stage-item-authoring-notes").setValue("é".repeat(2000));
        await c.wrapper.get("#stage-item-save").trigger("click");
      } else if (mode === "preview_batch") {
        await c.wrapper.get("[data-select-item]").setValue(true);
        await c.wrapper.get("#stage-preview-batch").trigger("click");
      } else if (mode === "submit") {
        await c.wrapper.get("#stage-batch-confirm").setValue(true);
        await c.wrapper.get("#stage-batch-submit").trigger("click");
      } else if (mode === "edit_details") {
        await c.wrapper.get("#stage-item-notes").setValue("Current operator note");
        await c.wrapper.get("#stage-item-order").setValue("9");
        await c.wrapper.get("#stage-item-details-form").trigger("submit");
      } else {
        const inputs = process.env.CADENCE_COMMAND_STAGES_EXACT_INPUT
          ? jsonFixture(process.env.CADENCE_COMMAND_STAGES_EXACT_INPUT)
          : { amount: "2" };
        for (const [name, value] of Object.entries(inputs)) {
          const raw = fixtureString(value);
          await c.wrapper.get(`[data-argument-name="${name}"]`).setValue(raw);
        }
        await c.wrapper.get("#stage-command-form").trigger("submit");
      }
      await flushPromises();
      expect(execute).toHaveBeenCalledOnce();
      writeFileSync(
        required(process.env.CADENCE_COMMAND_STAGES_INPUT_FILE),
        JSON.stringify({
          event: required(execute.mock.calls[0])[0],
          input: required(execute.mock.calls[0])[1],
        }),
      );
    } finally {
      c.wrapper.unmount();
    }
  },
);

test("named draft priorities preserve an existing custom rank when editing", async () => {
  const page = workbenchFixture(true);
  required(page.workbench.selected_item).priority = 17;
  required(page.workbench.items.entries[0]).priority = 17;
  const c = setup(page);
  try {
    const select = c.wrapper.get<HTMLSelectElement>("#stage-command-priority");
    expect(select.element.selectedOptions[0]?.textContent).toBe("Custom (rank 17)");
    await select.setValue("1");
    expect(select.element.selectedOptions[0]?.textContent).toBe("High (rank 1)");
    await select.setValue("17");
    await c.wrapper.get("#stage-command-form").trigger("submit");
    await flushPromises();
    expect(c.execute).toHaveBeenCalledExactlyOnceWith(
      "preview_item",
      containing({
        command: containing({ priority: 17 }),
      }),
    );
  } finally {
    c.wrapper.unmount();
  }
});
