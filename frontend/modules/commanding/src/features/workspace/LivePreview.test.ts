import { mount, flushPromises } from "@vue/test-utils";
import { afterEach, expect, test, vi } from "vite-plus/test";
import CommandWorkspace from "./CommandWorkspace.vue";
import WorkspaceStagePicker from "./WorkspaceStagePicker.vue";
import {
  workspaceFixture,
  targetsPreviewFixture,
  queuePreviewFixture,
} from "./fixtures.test-support";
import { required } from "../../../../../test-support/required";

const cleanups: (() => void)[] = [];
afterEach(() => {
  for (const cleanup of cleanups.splice(0)) cleanup();
});
function deferred() {
  let resolve: (value: unknown) => void = () => {};
  const promise = new Promise<unknown>((done) => {
    resolve = done;
  });
  return { promise, resolve };
}
function result(amount: number) {
  const original = targetsPreviewFixture();
  const preview = {
    ...original,
    items: original.items.map((item) => ({
      ...item,
      command: {
        ...item.command,
        argument_values_json: `{"amount":${amount},"delay_s":5,"enabled":false}`,
        resolved_argument_values_json: `{"amount":${amount},"delay_s":5,"enabled":false,"channel":"primary"}`,
      },
    })),
  };
  const queue = queuePreviewFixture(preview);
  return {
    status: "previewed",
    preview,
    queue_preview: {
      ...queue,
      token: String(amount).repeat(64),
      requests: queue.requests.map((request) => ({
        ...request,
        request_id: `live_request_${amount}`,
      })),
    },
  };
}

test("creating a stage preserves a name edited while the save was pending", async () => {
  const page = workspaceFixture();
  const request = deferred();
  const createStage = vi.fn(async () => {
    await request.promise;
  });
  const wrapper = mount(WorkspaceStagePicker, {
    attachTo: document.body,
    props: {
      directory: page.directory,
      stage: null,
      operation: null,
      disabled: false,
      actionDisabled: false,
      browseStages: async () => {},
      chooseStage: async () => {},
      createStage,
      follow: () => {},
    },
  });
  cleanups.push(() => wrapper.unmount());
  await wrapper.get(".cw-stage-trigger").trigger("click");
  await flushPromises();
  await wrapper.get(".cw-stage-menu-heading button").trigger("click");
  await wrapper.get("#workspace-stage-name").setValue("First stage");
  await wrapper.get("#workspace-create-stage").trigger("submit");
  expect(createStage).toHaveBeenCalledWith("First stage", "private");
  await wrapper.setProps({ actionDisabled: true });
  expect(wrapper.get("#workspace-stage-name").attributes("disabled")).toBeUndefined();
  await wrapper.get("#workspace-stage-name").setValue("Next stage");
  await wrapper.setProps({
    operation: {
      status: "completed",
      event: "create_stage",
      stage_id: page.new_stage_id,
      write_token: required(page.write_token),
      receipt: { kind: "stage", name: "First stage" },
    },
    actionDisabled: false,
  });
  request.resolve(null);
  await flushPromises();
  expect(wrapper.get<HTMLInputElement>("#workspace-stage-name").element.value).toBe("Next stage");
});
async function setup(defaultAmount?: string) {
  const page = workspaceFixture();
  if (defaultAmount !== undefined)
    required(required(page.catalog?.selected_command).arguments[0]).default_value_json =
      defaultAmount;
  const requests: ReturnType<typeof deferred>[] = [];
  const execute = vi.fn((_event: string, _input: Record<string, unknown>) => {
    const request = deferred();
    requests.push(request);
    return request.promise;
  });
  const read = vi.fn<() => Promise<unknown>>(async () => page);
  const navigate = vi.fn();
  const wrapper = mount(CommandWorkspace, {
    props: {
      page,
      port: { execute, navigate },
      readPort: { read, subscribe: () => () => {} },
    },
  });
  cleanups.push(() => wrapper.unmount());
  await flushPromises();
  await wrapper.get('[data-workspace-target="target_one"]').trigger("click");
  return { wrapper, execute, requests, read, navigate, page };
}

test("live validation keeps editing responsive and skips superseded inputs without a timer", async () => {
  const { wrapper, execute, requests } = await setup();
  const input = wrapper.get<HTMLInputElement>("#workspace-shared-argument-0");
  const enqueue = () => wrapper.get("#workspace-enqueue");
  expect(wrapper.find("#workspace-preview-targets").exists()).toBe(false);
  expect(enqueue().attributes("disabled")).toBeDefined();
  await input.setValue("2");
  expect(execute).toHaveBeenCalledTimes(1);
  expect(input.element.closest("fieldset")?.disabled).toBe(false);
  expect(wrapper.find("#workspace-validation-pending").exists()).toBe(true);
  await input.setValue("3");
  await input.setValue("4");
  expect(execute).toHaveBeenCalledTimes(1);
  required(requests[0]).resolve(result(2));
  await flushPromises();
  expect(execute).toHaveBeenCalledTimes(2);
  expect(execute.mock.calls[1]?.[1]).toMatchObject({
    commands: [{ argument_values_json: '{"amount":4,"delay_s":5,"enabled":false}' }],
  });
  expect(wrapper.find("#workspace-target-preview").exists()).toBe(false);
  expect(enqueue().attributes("disabled")).toBeDefined();
  required(requests[1]).resolve(result(4));
  await flushPromises();
  expect(enqueue().attributes("disabled")).toBeUndefined();
  expect(wrapper.get("#workspace-target-preview").text()).toContain("4");
  await input.setValue("unfinished");
  expect(enqueue().attributes("disabled")).toBeDefined();
  expect(wrapper.get("#workspace-argument-error").text()).toContain("valid integer");
  expect(execute).toHaveBeenCalledTimes(2);
});

test("defaults validate automatically and clearing targets discards an in-flight response", async () => {
  const { wrapper, execute, requests } = await setup("2");
  expect(execute).toHaveBeenCalledTimes(1);
  await wrapper.get('[data-workspace-target="target_one"]').trigger("click");
  required(requests[0]).resolve(result(2));
  await flushPromises();
  expect(wrapper.find("#workspace-target-preview").exists()).toBe(false);
  expect(wrapper.get("#workspace-enqueue").attributes("disabled")).toBeDefined();
  expect(execute).toHaveBeenCalledTimes(1);
});

test("a server rejection keeps enqueue disabled and supports an explicit retry", async () => {
  const { wrapper, requests } = await setup("2");
  required(requests[0]).resolve({ status: "rejected", feedback: "The selected model changed." });
  await flushPromises();
  expect(wrapper.get("#workspace-feedback").text()).toContain("model changed");
  expect(wrapper.get("#workspace-enqueue").attributes("disabled")).toBeDefined();
  await wrapper.get("#workspace-retry-validation").trigger("click");
  required(requests[1]).resolve(result(2));
  await flushPromises();
  expect(wrapper.get("#workspace-enqueue").attributes("disabled")).toBeUndefined();
});

test("incomplete UTC edits cannot restore a stale valid preview and recover without a model change", async () => {
  const { wrapper, execute, requests } = await setup("2");
  required(requests[0]).resolve(result(2));
  await flushPromises();
  const time = wrapper.get<HTMLInputElement>("#workspace-not-before");
  let badInput = true;
  Object.defineProperty(time.element.validity, "badInput", { get: () => badInput });
  await time.trigger("input");
  await flushPromises();
  expect(wrapper.get("#workspace-enqueue").attributes("disabled")).toBeDefined();
  expect(execute).toHaveBeenCalledTimes(1);
  badInput = false;
  await time.trigger("input");
  expect(execute).toHaveBeenCalledTimes(2);
  required(requests[1]).resolve(result(2));
  await flushPromises();
  expect(wrapper.get("#workspace-enqueue").attributes("disabled")).toBeUndefined();
});

test("submission captures its own values while editing continues and duplicate writes stay disabled", async () => {
  const { wrapper, execute, requests, read, navigate, page } = await setup("2");
  const original = result(2);
  required(requests[0]).resolve(original);
  await flushPromises();
  await wrapper.get("#workspace-enqueue").trigger("click");
  await flushPromises();
  expect(execute.mock.calls[1]?.[0]).toBe("enqueue");
  const input = wrapper.get<HTMLInputElement>("#workspace-shared-argument-0");
  expect(input.element.closest("fieldset")?.disabled).toBe(false);
  expect(wrapper.get("#workspace-target-search").attributes("disabled")).toBeUndefined();
  await input.setValue("7");
  await wrapper.get("#workspace-enqueue").trigger("click");
  expect(execute.mock.calls.filter(([event]) => event === "enqueue")).toHaveLength(1);
  await wrapper
    .get('a[href="/missions/mission_one/ops/commands/stages/stage_one"]')
    .trigger("click");
  expect(navigate).toHaveBeenCalled();
  // An unreadable response leaves the original attempt uncertain, but not the editor locked.
  required(requests[1]).resolve({});
  await flushPromises();
  expect(execute.mock.calls[2]?.[0]).toBe("preview_targets");
  const newer = result(7);
  required(requests[2]).resolve(newer);
  await flushPromises();
  expect(wrapper.get("#workspace-enqueue").attributes("disabled")).toBeDefined();
  expect(wrapper.get("#workspace-target-preview").text()).toContain("7");
  expect(input.element.value).toBe("7");
  read.mockResolvedValue({
    ...page,
    write_token: "f".repeat(64),
    draft_preview: newer.preview,
    queue_preview: newer.queue_preview,
    operation: {
      status: "completed",
      event: "enqueue",
      stage_id: null,
      write_token: page.write_token,
      receipt: {
        operation: "commands_submitted",
        actor_id: page.directory.actor_id,
        requests: original.queue_preview.requests.map((request) => ({
          request_id: request.request_id,
          target_id: request.target.id,
          requested_at: request.requested_at,
          state: "approval_pending",
          queue_id: null,
        })),
      },
    },
  });
  await wrapper.get("#workspace-check-enqueue-result").trigger("click");
  await flushPromises();
  expect(wrapper.get("#workspace-enqueue-result").text()).toContain("Approval requested");
  expect(wrapper.get("#workspace-enqueue").attributes("disabled")).toBeUndefined();
  expect(input.element.value).toBe("7");
});

test("catalog browsing leaves inputs editable and validates the latest edits when it resolves", async () => {
  const { wrapper, requests, execute, page } = await setup("2");
  required(requests[0]).resolve(result(2));
  await flushPromises();
  await wrapper.get('[data-workspace-command="command_one"]').trigger("click");
  await flushPromises();
  expect(execute.mock.calls[1]?.[0]).toBe("browse");
  const input = wrapper.get<HTMLInputElement>("#workspace-shared-argument-0");
  expect(input.element.closest("fieldset")?.disabled).toBe(false);
  expect(
    wrapper.get('[data-workspace-target="target_one"]').attributes("disabled"),
  ).toBeUndefined();
  await input.setValue("7");
  expect(wrapper.get("#workspace-enqueue").attributes("disabled")).toBeDefined();
  required(requests[1]).resolve({ status: "browsed", data: page });
  await flushPromises();
  expect(execute.mock.calls[2]?.[1]).toMatchObject({
    commands: [{ argument_values_json: '{"amount":7,"delay_s":5,"enabled":false}' }],
  });
  required(requests[2]).resolve(result(7));
  await flushPromises();
  expect(input.element.value).toBe("7");
  expect(wrapper.get("#workspace-enqueue").attributes("disabled")).toBeUndefined();
});
