import { readFileSync, writeFileSync } from "node:fs";
import { mount, flushPromises } from "@vue/test-utils";
import { afterEach, expect, test, vi } from "vite-plus/test";
import { producerFixture } from "../../../../../test-support/producer-fixture";
import { jsonFixture, fixtureContext } from "../../../../../test-support/json-fixture";
import { required } from "../../../../../test-support/required";
import CommandWorkspace from "./CommandWorkspace.vue";
import CadenceDateTimeField from "@cadence/ui/CadenceDateTimeField.vue";
import {
  workspaceFixture,
  targetsPreviewFixture,
  queuePreviewFixture,
} from "./fixtures.test-support";
import { type TargetsPreview, readWorkspace } from "./contracts";
import { batchPreviewFixture, workbenchFixture } from "../stage-workbench/fixtures.test-support";
import { commandObservation } from "../mission-commands/monitor.test-support";

const cleanups: (() => void)[] = [];
afterEach(() => {
  for (const cleanup of cleanups.splice(0)) cleanup();
  vi.useRealTimers();
});
function setup(
  page = workspaceFixture(),
  execute = vi.fn<(event: string, input: Record<string, unknown>) => Promise<unknown>>(
    async () => ({ status: "rejected", feedback: "Not saved" }),
  ),
  read = vi.fn<() => Promise<unknown>>(async () => page),
) {
  const guardNavigation = vi.fn((_guard: () => boolean) => vi.fn());
  let notify = () => {};
  const unsubscribe = vi.fn();
  const initialRead = vi
    .fn<() => Promise<unknown>>()
    .mockResolvedValueOnce(page)
    .mockImplementation(read);
  const wrapper = mount(CommandWorkspace, {
    props: {
      page,
      port: { execute, navigate: vi.fn(), guardNavigation },
      readPort: {
        read: initialRead,
        subscribe(listener: () => void) {
          notify = listener;
          return unsubscribe;
        },
      },
    },
  });
  cleanups.push(() => wrapper.unmount());
  return { wrapper, execute, read, guardNavigation, notify: () => notify(), unsubscribe };
}
async function prepareOne(c: ReturnType<typeof setup>) {
  await c.wrapper.get('[data-workspace-target="target_one"]').trigger("click");
  await c.wrapper.get("#workspace-shared-argument-0").setValue("2");
  await flushPromises();
}
function previewResult(preview: TargetsPreview) {
  return { status: "previewed", preview, queue_preview: queuePreviewFixture(preview) };
}
function onePreview() {
  const preview = targetsPreviewFixture();
  return {
    ...preview,
    items: preview.items.map((item) => ({
      ...item,
      command: {
        ...item.command,
        argument_values_json: '{"amount":2,"delay_s":5,"enabled":false}',
      },
    })),
  };
}

function directPreview() {
  const queue = queuePreviewFixture(onePreview());
  return {
    ...queue,
    requests: queue.requests.map((request) => ({
      ...request,
      lifecycle_state: "validated" as const,
    })),
  };
}
function queuedOperation(page = workspaceFixture()) {
  return {
    status: "completed",
    event: "enqueue",
    stage_id: null,
    write_token: page.write_token,
    receipt: {
      operation: "commands_submitted",
      actor_id: page.directory.actor_id,
      requests: directPreview().requests.map((request) => ({
        request_id: request.request_id,
        target_id: request.target.id,
        requested_at: request.requested_at,
        state: "queued",
        queue_id: `queue_${request.request_id}`,
      })),
    },
  };
}

test.each([
  { withStage: false, shelf: "minimized" },
  { withStage: false, shelf: "expanded" },
  { withStage: true, shelf: "minimized" },
  { withStage: true, shelf: "expanded" },
])(
  "enqueues without changing the shelf: stage selected = $withStage, shelf = $shelf",
  async ({ withStage, shelf }) => {
    const fixture = workspaceFixture();
    const page = { ...fixture, workbench: withStage ? fixture.workbench : null };
    const operation = queuedOperation(page);
    const c = setup(
      page,
      vi.fn(async (event) =>
        event === "preview_targets"
          ? {
              status: "previewed",
              preview: withStage ? onePreview() : null,
              queue_preview: directPreview(),
            }
          : operation,
      ),
      vi.fn(async () => ({ ...page, write_token: "f".repeat(64), operation })),
    );
    await prepareOne(c);
    if (shelf === "minimized")
      await c.wrapper.get('[aria-label="Minimize command shelf"]').trigger("click");
    const button = c.wrapper.get("#workspace-enqueue");
    expect(button.text()).toBe("Enqueue command");
    expect(button.attributes("disabled")).toBeUndefined();
    expect(c.wrapper.find("#workspace-save-targets").exists()).toBe(withStage);
    await button.trigger("click");
    await flushPromises();
    expect(c.execute).toHaveBeenLastCalledWith("enqueue", {
      expected_preview: directPreview().token,
      expected_write: page.write_token,
    });
    expect(c.wrapper.get("#workspace-enqueue-result").text()).toBe("Command queued.");
    expect(c.wrapper.find("#workspace-write-result").exists()).toBe(false);
    expect(c.wrapper.find("[data-workspace-request]").exists()).toBe(false);
    expect(c.wrapper.find('[aria-label="Expand command shelf"]').exists()).toBe(
      shelf === "minimized",
    );
    expect(c.wrapper.get(".cw-stage-trigger").text()).toBe(
      page.workbench?.stage.name ?? "Choose a stage",
    );
    expect(c.wrapper.get("#workspace-enqueue").attributes("disabled")).toBeDefined();
    expect(
      c.wrapper.get("#workspace-shared-argument-0").element.closest("fieldset")?.disabled,
    ).toBe(false);
    expect(c.wrapper.get<HTMLInputElement>("#workspace-shared-argument-0").element.value).toBe("2");
    await c.wrapper.get("#workspace-shared-argument-0").setValue("3");
    c.notify();
    await flushPromises();
    expect(c.wrapper.find("#workspace-enqueue-result").exists()).toBe(false);
  },
);

test("approval-required previews label their action and never claim to enqueue", async () => {
  const page = { ...workspaceFixture(), workbench: null };
  const queue = queuePreviewFixture(onePreview());
  const queued = queuedOperation(page);
  const operation = {
    ...queued,
    receipt: {
      ...queued.receipt,
      requests: queued.receipt.requests.map((request) => ({
        ...request,
        state: "approval_pending",
        queue_id: null,
      })),
    },
  };
  const c = setup(
    page,
    vi.fn(async (event) =>
      event === "enqueue"
        ? operation
        : {
            status: "previewed",
            preview: null,
            queue_preview: {
              ...queue,
              requests: queue.requests.map((request) => ({
                ...request,
                lifecycle_state: "approval_pending",
              })),
            },
          },
    ),
    vi.fn(async () => ({ ...page, write_token: "f".repeat(64), operation })),
  );
  await prepareOne(c);
  expect(c.wrapper.get("#workspace-enqueue").text()).toBe("Request approval");
  expect(c.wrapper.get("#workspace-target-preview").text()).toContain(
    "Requires approval before queueing",
  );
  await c.wrapper.get("#workspace-enqueue").trigger("click");
  await flushPromises();
  expect(c.wrapper.get("#workspace-enqueue-result").text()).toBe("Approval requested.");
  expect(c.wrapper.find("#workspace-write-result").exists()).toBe(false);
});

test("an uncertain enqueue cannot repeat and its exact recovered receipt unlocks the builder", async () => {
  const page = { ...workspaceFixture(), workbench: null, initial_shelf: "minimized" as const };
  const operation = queuedOperation(page);
  const execute = vi.fn(async (event: string) => {
    if (event === "preview_targets")
      return { status: "previewed", preview: null, queue_preview: directPreview() };
    throw Error("Lost enqueue response");
  });
  const c = setup(
    page,
    execute,
    vi.fn(async () => ({ ...page, write_token: "f".repeat(64), operation })),
  );
  await prepareOne(c);
  await c.wrapper.get("#workspace-enqueue").trigger("click");
  await flushPromises();
  expect(c.wrapper.get("#workspace-enqueue").attributes("disabled")).toBeDefined();
  await c.wrapper.get("#workspace-enqueue").trigger("click");
  expect(execute.mock.calls.filter(([event]) => event === "enqueue")).toHaveLength(1);
  expect(c.wrapper.find('[aria-label="Expand command shelf"]').exists()).toBe(true);
  expect(c.wrapper.get("#workspace-enqueue-result").text()).toContain("unconfirmed");
  await c.wrapper.get("#workspace-check-enqueue-result").trigger("click");
  await flushPromises();
  expect(c.wrapper.get("#workspace-enqueue-result").text()).toBe("Command queued.");
  expect(c.wrapper.find('[aria-label="Expand command shelf"]').exists()).toBe(true);
  expect(c.wrapper.get("#workspace-shared-argument-0").element.closest("fieldset")?.disabled).toBe(
    false,
  );
});

test("a mismatched enqueue receipt remains unconfirmed", async () => {
  const page = { ...workspaceFixture(), workbench: null };
  const operation = queuedOperation(page);
  required(operation.receipt.requests[0]).target_id = "target_other";
  const c = setup(
    page,
    vi.fn(async (event) =>
      event === "preview_targets"
        ? { status: "previewed", preview: null, queue_preview: directPreview() }
        : operation,
    ),
  );
  await prepareOne(c);
  await c.wrapper.get("#workspace-enqueue").trigger("click");
  await flushPromises();
  expect(c.wrapper.get("#workspace-enqueue-result").text()).toContain("unconfirmed");
  expect(c.wrapper.get("#workspace-enqueue").attributes("disabled")).toBeDefined();
});

test("queue previews reject foreign actors, repeated targets and mismatched catalog revisions", () => {
  const page = workspaceFixture();
  const queue = directPreview();
  const first = required(queue.requests[0]);
  for (const invalid of [
    { ...queue, actor_id: "another_user" },
    { ...queue, requests: [first, first] },
    { ...queue, requests: [first, { ...first, request_id: "another_request" }] },
    { ...queue, requests: [{ ...first, revision_id: "another_revision" }] },
  ])
    expect(() =>
      readWorkspace({ ...page, queue_preview: invalid }, page.directory.context),
    ).toThrow();
});

test("typing filters both lists without discarding selection, argument text or a held preview", async () => {
  vi.useFakeTimers();
  const page = workspaceFixture();
  const catalog = required(page.catalog);
  const execute = vi.fn<(event: string, input: Record<string, unknown>) => Promise<unknown>>(
    async (event, input) =>
      event === "preview_targets"
        ? previewResult(onePreview())
        : {
            status: "catalog_page",
            catalog: { ...catalog, query: input.query },
            spacecraft: page.spacecraft,
          },
  );
  const c = setup(page, execute);
  await prepareOne(c);
  for (const selector of ["#workspace-command-search", "#workspace-target-search"]) {
    await c.wrapper.get(selector).setValue("power");
    await vi.advanceTimersByTimeAsync(200);
    await flushPromises();
    expect(c.wrapper.get<HTMLInputElement>("#workspace-shared-argument-0").element.value).toBe("2");
    expect(c.wrapper.find("#workspace-save-targets").exists()).toBe(true);
  }
  expect(execute.mock.calls.filter(([event]) => event === "catalog_page")).toHaveLength(2);
  expect(execute.mock.calls.some(([event]) => event === "browse")).toBe(false);
  expect(c.wrapper.get('[data-workspace-target="target_one"]').attributes("aria-pressed")).toBe(
    "true",
  );
  await c.wrapper.get("#workspace-shared-argument-0").setValue("unfinished");
  await c.wrapper.get("#workspace-command-search").setValue("other");
  await vi.advanceTimersByTimeAsync(200);
  expect(c.wrapper.get<HTMLInputElement>("#workspace-shared-argument-0").element.value).toBe(
    "unfinished",
  );
});

test("preparation shows a catalog opcode and sends UTC picker values to preview", async () => {
  const page = workspaceFixture();
  const catalog = required(page.catalog);
  const command = required(catalog.selected_command);
  command.name = "DISABLE_LOAD";
  command.display_name = null;
  command.opcode_json = "34";
  const c = setup(page);
  const preparation = c.wrapper.get('[aria-labelledby="command-workspace-preparation-title"]');
  expect(preparation.findAll("h3").map((heading) => heading.text())).toContain("DISABLE_LOAD");
  expect(preparation.get("#workspace-command-opcode").text()).toBe("Opcode 0x22 · 8 bits");
  expect(preparation.findAll("summary").map((summary) => summary.text())).not.toContain(
    "Command identity",
  );
  expect(preparation.findAll("code").map((code) => code.text())).not.toContain("DISABLE_LOAD");
  await c.wrapper.get("#workspace-not-before").setValue("2027-01-15T13:45:12");
  await c.wrapper.get("#workspace-expires").setValue("2027-01-15T14:45:12");
  await prepareOne(c);
  const input = c.execute.mock.calls.find(([event]) => event === "preview_targets")?.[1];
  expect(input).toMatchObject({
    commands: [
      {
        not_before: "2027-01-15T13:45:12Z",
        expires_at: "2027-01-15T14:45:12Z",
      },
    ],
  });
});

test("an incomplete timing edit invalidates an already prepared action", async () => {
  const c = setup(
    workspaceFixture(),
    vi.fn(async () => previewResult(onePreview())),
  );
  await prepareOne(c);
  expect(c.wrapper.find("#workspace-save-targets").exists()).toBe(true);
  const input = c.wrapper.get<HTMLInputElement>("#workspace-not-before");
  // A partially edited date is badInput in Chrome; happy-dom has no segmented date UI.
  Object.defineProperty(input.element.validity, "badInput", { get: () => true });
  await input.trigger("input");
  await flushPromises();
  expect(c.wrapper.find("#workspace-save-targets").exists()).toBe(false);
});

test("enum selection survives a catalog refresh and changing it invalidates a preview", async () => {
  const page = workspaceFixture();
  const arg = required(required(required(page.catalog).selected_command).arguments[0]);
  arg.type = "enumerated";
  arg.choices = [
    { label: "Primary", value_json: "1" },
    { label: "Backup", value_json: "2" },
  ];
  const c = setup(
    page,
    vi.fn(async () => previewResult(onePreview())),
  );
  await c.wrapper.get('[data-workspace-target="target_one"]').trigger("click");
  await c.wrapper.get("#workspace-shared-argument-0-1").setValue(true);
  c.notify();
  await flushPromises();
  expect(c.wrapper.get<HTMLInputElement>("#workspace-shared-argument-0-1").element.checked).toBe(
    true,
  );
  await flushPromises();
  expect(c.execute).toHaveBeenCalledWith(
    "preview_targets",
    expect.objectContaining({
      commands: [
        expect.objectContaining({
          argument_values_json: '{"amount":2,"delay_s":5,"enabled":false}',
        }),
      ],
    }),
  );
  expect(c.wrapper.find("#workspace-save-targets").exists()).toBe(true);
  await c.wrapper.get("#workspace-shared-argument-0-0").setValue(true);
  expect(c.wrapper.find("#workspace-save-targets").exists()).toBe(false);
});

test("per-spacecraft mode starts with shared values and retains exact edits through deselection", async () => {
  const page = workspaceFixture(),
    catalog = required(page.catalog),
    first = required(catalog.targets.entries[0]);
  catalog.targets.entries.push({
    ...first,
    id: "target_two",
    name: "Second endpoint",
    spacecraft_id: "craft_two",
  });
  const c = setup(page);
  await c.wrapper.get('[data-workspace-target="target_one"]').trigger("click");
  await c.wrapper.get('[data-workspace-target="target_two"]').trigger("click");
  await c.wrapper.get("#workspace-shared-argument-0").setValue("18446744073709551615");
  await c.wrapper.get('#workspace-value-mode input[value="individual"]').setValue(true);
  expect(c.wrapper.get<HTMLInputElement>("#workspace-target_two-argument-0").element.value).toBe(
    "18446744073709551615",
  );
  await c.wrapper.get("#workspace-target_two-argument-0").setValue("9007199254740993");
  await c.wrapper.get('[data-workspace-target="target_one"]').trigger("click");
  await flushPromises();
  expect(c.execute).toHaveBeenCalledWith("preview_targets", {
    expected_stage: page.workbench?.stage.expected_stage,
    notes: null,
    commands: [
      {
        expected_basis: catalog.basis.token,
        source_endpoint_ref: "target_two",
        command_id: "command_one",
        argument_values_json: '{"amount":9007199254740993,"delay_s":5,"enabled":false}',
        priority: 3,
        not_before: null,
        expires_at: null,
      },
    ],
  });
  await c.wrapper.get('[data-workspace-target="target_two"]').trigger("click");
  await c.wrapper.get('[data-workspace-target="target_two"]').trigger("click");
  expect(c.wrapper.get<HTMLInputElement>("#workspace-target_two-argument-0").element.value).toBe(
    "9007199254740993",
  );
});

test("switching value modes invalidates preview, keeps edits and only validates the active mode", async () => {
  const c = setup(
    workspaceFixture(),
    vi.fn(async () => previewResult(onePreview())),
  );
  await prepareOne(c);
  expect(c.wrapper.find("#workspace-save-targets").exists()).toBe(true);
  await c.wrapper.get('#workspace-value-mode input[value="individual"]').setValue(true);
  await flushPromises();
  expect(c.wrapper.find("#workspace-save-targets").exists()).toBe(true);
  expect(c.wrapper.find("#workspace-shared-argument-0").exists()).toBe(false);
  expect(c.wrapper.get<HTMLInputElement>("#workspace-target_one-argument-0").element.value).toBe(
    "2",
  );
  await c.wrapper.get("#workspace-target_one-argument-0").setValue("unfinished");
  await c.wrapper.get('#workspace-value-mode input[value="shared"]').setValue(true);
  expect(c.wrapper.get<HTMLInputElement>("#workspace-shared-argument-0").element.value).toBe("2");
  await flushPromises();
  expect(c.wrapper.find("#workspace-save-targets").exists()).toBe(true);
  await c.wrapper.get("#workspace-shared-argument-0").setValue("incomplete shared value");
  await c.wrapper.get('#workspace-value-mode input[value="individual"]').setValue(true);
  expect(c.wrapper.get<HTMLInputElement>("#workspace-target_one-argument-0").element.value).toBe(
    "unfinished",
  );
  c.execute.mockClear();
  expect(c.execute).not.toHaveBeenCalled();
  expect(c.wrapper.get("#workspace-argument-error").text()).toContain("valid integer");
  await c.wrapper.get("#workspace-target_one-argument-0").setValue("7");
  await flushPromises();
  expect(c.execute).toHaveBeenCalledWith(
    "preview_targets",
    expect.objectContaining({
      commands: [
        expect.objectContaining({
          argument_values_json: '{"amount":7,"delay_s":5,"enabled":false}',
        }),
      ],
    }),
  );
});

test("preview mismatch, changed spacecraft mapping and microsecond timing substitutions cannot enable saving", async () => {
  for (const change of [
    { argument_values_json: '{"amount":3,"delay_s":5,"enabled":false}' },
    { target: { ...required(onePreview().items[0]).command.target, spacecraft_id: "other_craft" } },
    { not_before: "2027-01-01T00:00:00.000002Z" },
  ]) {
    const preview = onePreview();
    const c = setup(
      workspaceFixture(),
      vi.fn(async () =>
        previewResult({
          ...preview,
          items: preview.items.map((item) => ({
            ...item,
            command: { ...item.command, ...change },
          })),
        }),
      ),
    );
    if ("not_before" in change)
      // oxlint-disable-next-line typescript/no-unsafe-call, typescript/no-unsafe-member-access -- vue-tsc checks this SFC's typed emit; the lint service cannot resolve imported Vue instances.
      required(c.wrapper.findAllComponents(CadenceDateTimeField)[0]).vm.$emit(
        "update:modelValue",
        "2027-01-01T00:00:00.000001Z",
      );
    await prepareOne(c);
    expect(c.wrapper.find("#workspace-save-targets").exists()).toBe(false);
    expect(c.wrapper.get("#workspace-feedback").text()).toContain("could not be completed");
  }
});

test("refresh cannot restore a target preview invalidated by an argument edit", async () => {
  const page = workspaceFixture(),
    preview = onePreview();
  const c = setup(
    page,
    vi.fn(async () => previewResult(preview)),
    vi.fn(async () => ({
      ...page,
      draft_preview: preview,
      queue_preview: queuePreviewFixture(preview),
    })),
  );
  await prepareOne(c);
  expect(c.wrapper.find("#workspace-save-targets").exists()).toBe(true);
  await c.wrapper.get("#workspace-shared-argument-0").setValue("7");
  c.notify();
  await flushPromises();
  expect(c.wrapper.find("#workspace-save-targets").exists()).toBe(false);
  expect(c.wrapper.get<HTMLInputElement>("#workspace-shared-argument-0").element.value).toBe("7");
});

test("unconfirmed save is consumed and cannot replay; current receipt refresh unlocks preparation", async () => {
  const page = workspaceFixture(),
    preview = onePreview();
  const execute = vi.fn<(event: string, input: Record<string, unknown>) => Promise<unknown>>(
    async (event) => {
      if (event === "preview_targets") return previewResult(preview);
      throw Error("Lost response");
    },
  );
  const operation = {
    status: "completed",
    event: "save_targets",
    stage_id: "stage_one",
    write_token: page.write_token,
    receipt: {
      operation: "items_created",
      stage_id: "stage_one",
      actor_id: "user_one",
      items: [{ item_id: "item_reserved", updated_at: "2026-09-12T00:00:00Z" }],
    },
  };
  const c = setup(
    page,
    execute,
    vi.fn(async () => ({ ...page, write_token: "f".repeat(64), operation })),
  );
  await prepareOne(c);
  await c.wrapper.get("#workspace-save-targets").trigger("click");
  await flushPromises();
  expect(c.wrapper.get("#workspace-write-result").text()).toContain("unconfirmed");
  expect(c.wrapper.find("#workspace-save-targets").exists()).toBe(false);
  expect(execute.mock.calls.filter(([event]) => event === "save_targets")).toHaveLength(1);
  await c.wrapper.get("#workspace-check-result").trigger("click");
  await flushPromises();
  expect(c.wrapper.get("#workspace-write-result").text()).toContain("1 drafts saved");
  expect(c.wrapper.get("#workspace-shared-argument-0").element.closest("fieldset")?.disabled).toBe(
    false,
  );
});

test("request receipt recovery retains exact submitted identities across repeated unconfirmed reads", async () => {
  const batch = batchPreviewFixture();
  const page = { ...workspaceFixture(), batch_preview: batch };
  const attempt = {
    status: "unconfirmed",
    event: "submit",
    stage_id: "stage_one",
    write_token: page.write_token,
  };
  const completed = {
    ...attempt,
    status: "completed",
    receipt: {
      operation: "requests_created",
      stage_id: "stage_one",
      actor_id: "user_one",
      requests: batch.requests.map((request) => ({
        request_id: request.request_id,
        item_id: request.item_id,
        requested_at: request.requested_at,
        state: request.lifecycle_state,
      })),
    },
  };
  const read = vi
    .fn<() => Promise<unknown>>()
    .mockResolvedValueOnce({ ...page, write_token: null, operation: attempt })
    .mockResolvedValueOnce({
      ...page,
      write_token: "f".repeat(64),
      batch_preview: null,
      operation: completed,
    });
  const c = setup(
    page,
    vi.fn(async () => {
      throw Error("Lost response");
    }),
    read,
  );
  await c.wrapper.get("#stage-batch-confirm").setValue(true);
  await c.wrapper.get("#stage-batch-submit").trigger("click");
  await flushPromises();
  await c.wrapper.get("#workspace-check-result").trigger("click");
  await flushPromises();
  expect(c.wrapper.get("#workspace-write-result").text()).toContain("unconfirmed");
  await c.wrapper.get("#workspace-check-result").trigger("click");
  await flushPromises();
  expect(c.wrapper.get("#workspace-write-result").text()).toContain("formal requests created");
  expect(c.execute).toHaveBeenCalledOnce();
});

test("pending validation allows navigation and ignores completions after unmount", async () => {
  let finish: (value: unknown) => void = () => {};
  const c = setup(
    workspaceFixture(),
    vi.fn(
      () =>
        new Promise<unknown>((resolve) => {
          finish = resolve;
        }),
    ),
  );
  await prepareOne(c);
  expect(c.guardNavigation).not.toHaveBeenCalled();
  c.wrapper.unmount();
  finish(previewResult(onePreview()));
  await flushPromises();
  expect(c.read).not.toHaveBeenCalled();
  expect(c.unsubscribe).toHaveBeenCalledOnce();
  c.notify();
  await flushPromises();
  expect(c.read).not.toHaveBeenCalled();
});

test("live execution changes preserve argument edits, draft selection and an unchanged confirmed review", async () => {
  const page = workspaceFixture(),
    batch = batchPreviewFixture();
  const next = {
    ...page,
    batch_preview: batch,
    monitor: {
      ...page.monitor,
      summary: { ...page.monitor.summary, active_count: 7, total_count: 7, in_flight_count: 7 },
      total: 7,
      rows: Array.from({ length: 7 }, (_, index) => commandObservation(`request-${index}`)),
    },
  };
  const c = setup(
    page,
    vi.fn(async () => ({ status: "previewed", preview: batch })),
    vi.fn(async () => next),
  );
  await c.wrapper.get('[data-workspace-target="target_one"]').trigger("click");
  await c.wrapper.get("#workspace-shared-argument-0").setValue("unfinished");
  await c.wrapper.get('.cw-table input[type="checkbox"]').setValue(true);
  await c.wrapper.get("#workspace-review-stage").trigger("click");
  await flushPromises();
  await c.wrapper.get("#stage-batch-confirm").setValue(true);
  c.read.mockClear();
  c.notify();
  await flushPromises();
  expect(c.read).toHaveBeenCalledOnce();
  expect(c.wrapper.get<HTMLInputElement>("#workspace-shared-argument-0").element.value).toBe(
    "unfinished",
  );
  expect(c.wrapper.get<HTMLInputElement>('.cw-table input[type="checkbox"]').element.checked).toBe(
    true,
  );
  expect(c.wrapper.get<HTMLInputElement>("#stage-batch-confirm").element.checked).toBe(true);
  expect(c.wrapper.get("#stage-batch-submit").attributes("disabled")).toBeUndefined();
  expect(c.wrapper.find("#workspace-refresh").exists()).toBe(false);
  expect(c.wrapper.find(".cadence-workspace-layout__toolbar").exists()).toBe(false);
});

test("a collaborator changing selected draft evidence invalidates review without clearing command arguments", async () => {
  const page = workspaceFixture(),
    batch = batchPreviewFixture(),
    workbench = required(page.workbench);
  const next = {
    ...page,
    workbench: {
      ...workbench,
      items: {
        ...workbench.items,
        entries: workbench.items.entries.map((item) => ({
          ...item,
          expected_item: "9".repeat(64),
        })),
      },
    },
  };
  const c = setup(
    page,
    vi.fn(async () => ({ status: "previewed", preview: batch })),
    vi.fn(async () => next),
  );
  await c.wrapper.get("#workspace-shared-argument-0").setValue("7");
  await c.wrapper.get('.cw-table input[type="checkbox"]').setValue(true);
  await c.wrapper.get("#workspace-review-stage").trigger("click");
  await flushPromises();
  await c.wrapper.get("#stage-batch-confirm").setValue(true);
  c.notify();
  await flushPromises();
  expect(c.wrapper.find("#stage-batch-submit").exists()).toBe(false);
  expect(c.wrapper.get<HTMLInputElement>('.cw-table input[type="checkbox"]').element.checked).toBe(
    false,
  );
  expect(c.wrapper.get<HTMLInputElement>("#workspace-shared-argument-0").element.value).toBe("7");
  expect(c.wrapper.get("#workspace-feedback").text()).toContain("evidence changed");
});

test.each([true, false])("live order updates preserve local edits: %s", async (edited) => {
  const workbench = workbenchFixture(true).workbench,
    page = { ...workspaceFixture(), workbench };
  let next = structuredClone(page);
  const c = setup(
    page,
    vi.fn(),
    vi.fn(async () => next),
  );
  await flushPromises();
  if (edited) await c.wrapper.get("#workspace-draft-order").setValue("17");
  c.notify();
  await flushPromises();
  expect(c.wrapper.get<HTMLInputElement>("#workspace-draft-order").element.value).toBe(
    edited ? "17" : String(required(workbench.selected_item).order),
  );
  const item = required(workbench.selected_item);
  next = {
    ...page,
    workbench: {
      ...workbench,
      selected_item: { ...item, order: 4 },
      items: { ...workbench.items, entries: [{ ...item, order: 4, argument_values_json: null }] },
    },
  };
  c.notify();
  await flushPromises();
  expect(c.wrapper.get<HTMLInputElement>("#workspace-draft-order").element.value).toBe(
    edited ? "17" : "4",
  );
});

test("live notices coalesce behind an action and never apply a read overtaken by that action", async () => {
  const page = workspaceFixture(),
    preview = onePreview();
  let finishRead: (value: unknown) => void = () => {};
  let finishAction: (value: unknown) => void = () => {};
  const read = vi
    .fn<() => Promise<unknown>>()
    .mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          finishRead = resolve;
        }),
    )
    .mockResolvedValue({
      ...page,
      draft_preview: preview,
      queue_preview: queuePreviewFixture(preview),
    });
  const c = setup(
    page,
    vi.fn(
      () =>
        new Promise((resolve) => {
          finishAction = resolve;
        }),
    ),
    read,
  );
  await flushPromises();
  c.notify();
  await prepareOne(c);
  c.notify();
  c.notify();
  expect(read).toHaveBeenCalledOnce();
  finishRead({ ...page, catalog: null });
  await flushPromises();
  expect(c.wrapper.find("#workspace-preparation-form").exists()).toBe(true);
  finishAction(previewResult(preview));
  await flushPromises();
  expect(read).toHaveBeenCalledTimes(2);
  expect(c.wrapper.find("#workspace-save-targets").exists()).toBe(true);
});

test("workspace decoding rejects foreign identity, duplicate spacecraft labels and malformed batch receipts", () => {
  const page = workspaceFixture(),
    context = page.directory.context;
  expect(readWorkspace(page, context).state).toBe("prepare");
  for (const invalid of [
    { ...page, spacecraft: [...page.spacecraft, ...page.spacecraft] },
    { ...page, catalog: { ...page.catalog, actor_id: "user_other" } },
    {
      ...page,
      workbench: { ...page.workbench, context: { ...context, missionId: "mission_other" } },
    },
    {
      ...page,
      operation: {
        status: "unconfirmed",
        event: "submit",
        stage_id: "stage_one",
        write_token: page.write_token,
      },
    },
  ])
    expect(() => readWorkspace(invalid, context)).toThrow();
});

const producer = producerFixture("CADENCE_COMMAND_WORKSPACE_DOCUMENT", import.meta.url);
test.skipIf(!producer.available)(
  "actual producer workspace controls preserve multi-endpoint stage intent",
  async () => {
    const envelope = jsonFixture(readFileSync(producer.read(), "utf8"));
    const page = readWorkspace(envelope.data, fixtureContext(envelope.context));
    if (page.state !== "prepare") throw Error("Expected command preparation");
    const c = setup(page);
    const mode = process.env.CADENCE_COMMAND_WORKSPACE_MODE;
    if (mode === "enqueue") await c.wrapper.get("#workspace-enqueue").trigger("click");
    else if (mode === "save_targets")
      await c.wrapper.get("#workspace-save-targets").trigger("click");
    else if (mode === "preview_batch") {
      for (const checkbox of c.wrapper.findAll('.cw-table input[type="checkbox"]'))
        await checkbox.setValue(true);
      await c.wrapper.get("#workspace-review-stage").trigger("click");
    } else if (mode === "submit") {
      await c.wrapper.get("#stage-batch-confirm").setValue(true);
      await c.wrapper.get("#stage-batch-submit").trigger("click");
    } else {
      for (const tile of c.wrapper.findAll("[data-workspace-target]")) await tile.trigger("click");
      await c.wrapper.get("#workspace-shared-argument-0").setValue("2");
    }
    await flushPromises();
    expect(c.execute).toHaveBeenCalledOnce();
    const [event, input] = required(c.execute.mock.calls[0]);
    writeFileSync(
      required(process.env.CADENCE_COMMAND_WORKSPACE_INPUT_FILE),
      JSON.stringify({ event, input }),
    );
  },
);

test("the saved shelf default sets its opening state while a selected stage remains visible", async () => {
  const initial = workspaceFixture();
  const minimized = setup({ ...initial, workbench: null, initial_shelf: "minimized" });
  await flushPromises();
  expect(minimized.wrapper.find('button[aria-label="Expand command shelf"]').exists()).toBe(true);
  const expanded = setup({ ...initial, workbench: null, initial_shelf: "expanded" });
  await flushPromises();
  expect(expanded.wrapper.find('button[aria-label="Expand command shelf"]').exists()).toBe(false);
  const selected = setup({ ...initial, initial_shelf: "minimized" });
  await flushPromises();
  expect(selected.wrapper.find('button[aria-label="Expand command shelf"]').exists()).toBe(false);
});
