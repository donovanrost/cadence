import { afterEach, expect, test, vi } from "vite-plus/test";
import { flushPromises, mount } from "@vue/test-utils";
import DashboardEditor from "./DashboardEditor.vue";
import EditorLayoutCanvas from "./EditorLayoutCanvas.vue";
import { editorContext, editorFixture } from "./fixtures.test-support";
import { readEditor } from "./validation";
const apps: ReturnType<typeof mount>[] = [];
afterEach(() => {
  for (const app of apps.splice(0)) app.unmount();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});
function render(execute = vi.fn()) {
  let guard: () => boolean = () => true;
  const removeGuard = vi.fn();
  const refresh = vi.fn(async () => {});
  const app = mount(DashboardEditor, {
    props: {
      state: editorFixture(),
      context: editorContext,
      refresh,
      port: {
        execute,
        navigate: vi.fn(),
        guardNavigation(fn) {
          guard = fn;
          return removeGuard;
        },
      },
    },
  });
  apps.push(app);
  return { app, execute, refresh, removeGuard, guard: () => guard() };
}
test("versioned editor DTOs reject foreign resources, duplicate IDs and unsupported shapes", () => {
  expect(readEditor(editorFixture(), editorContext)).toEqual(editorFixture());
  for (const mutate of [
    (s: any) => {
      s.version = 1;
    },
    (s: any) => {
      delete s.revision;
    },
    (s: any) => {
      s.revision = -1;
    },
    (s: any) => {
      s.dirty = "false";
    },
    (s: any) => {
      s.model.dashboard_id = "other";
    },
    (s: any) => {
      s.model.version = 1;
    },
    (s: any) => {
      s.model.version = 2;
    },
    (s: any) => {
      delete s.model.runtime_defaults_json;
    },
    (s: any) => {
      s.model.runtime_defaults_json = "[]";
    },
    (s: any) => {
      s.model.placements.push(s.model.placements[0]);
    },
    (s: any) => {
      s.model.sections = [];
    },
    (s: any) => {
      s.model.defaults.line_width = "thick";
    },
    (s: any) => {
      s.model.secret = "raw";
    },
    (s: any) => {
      s.model.placements[0].fields.title = "wrong";
    },
    (s: any) => {
      s.sequence = -1;
    },
    (s: any) => {
      delete s.model.grid;
    },
    (s: any) => {
      s.model.grid.columns = 0;
    },
    (s: any) => {
      s.model.placements[0].constraints.max_w = 10;
    },
    (s: any) => {
      s.model.placements[0].constraints.min_h = 100;
    },
  ]) {
    const s = editorFixture();
    mutate(s);
    expect(() => readEditor(s, editorContext)).toThrow();
  }
});
test("runtime quick controls preserve other defaults and use explicit revisioned staging", async () => {
  const next = editorFixture();
  next.sequence = 1;
  next.revision = 1;
  next.dirty = true;
  const defaults = JSON.parse(next.model.runtime_defaults_json);
  defaults.time.mode = "archive";
  next.model.runtime_defaults_json = JSON.stringify(defaults);
  const { app, execute, guard } = render(
    vi.fn(async () => ({ status: "ok", code: null, state: next })),
  );
  vi.stubGlobal(
    "confirm",
    vi.fn(() => false),
  );
  await app.get("#editor-runtime").trigger("click");
  expect(execute).not.toHaveBeenCalled();
  const textarea = app.get("#editor-runtime-json").element;
  await app.get("#editor-runtime-time-mode").setValue("archive");
  expect(guard()).toBe(false);
  expect(JSON.parse((textarea as HTMLTextAreaElement).value)).toEqual(defaults);
  await app.get("#dashboard-editor-form").trigger("submit");
  await flushPromises();
  expect(execute).toHaveBeenCalledWith("runtime_defaults", {
    sequence: 1,
    command: {
      expected_version: 1,
      expected_revision: 0,
      defaults_json: JSON.stringify(defaults, null, 2),
    },
  });
  expect(app.get("#editor-runtime-json").element).toBe(textarea);
  expect(app.get("#editor-version").text()).toBe("Draft v1");
  expect(guard()).toBe(false);
});

test("invalid JSON is local, domain rejection preserves edits, and discard restores saved defaults", async () => {
  const next = editorFixture();
  next.sequence = 1;
  const { app, execute } = render(
    vi.fn(async () => ({ status: "invalid", code: "invalid_defaults", state: next })),
  );
  vi.stubGlobal(
    "confirm",
    vi.fn(() => true),
  );
  await app.get("#editor-runtime").trigger("click");
  await app.get("#editor-runtime-json").setValue("{");
  await app.get("#dashboard-editor-form").trigger("submit");
  expect(execute).not.toHaveBeenCalled();
  expect(app.get("#editor-runtime-json").attributes("aria-invalid")).toBe("true");
  expect(app.get("#editor-runtime-time-mode").attributes("disabled")).toBeDefined();
  const unsupported = '{"time":{"mode":"unknown"},"overlays":{"events":true}}';
  await app.get("#editor-runtime-json").setValue(unsupported);
  expect((app.get("#editor-runtime-time-mode").element as HTMLSelectElement).value).toBe("unknown");
  await app.get("#dashboard-editor-form").trigger("submit");
  await flushPromises();
  expect(execute.mock.calls[0][1].sequence).toBe(1);
  expect((app.get("#editor-runtime-json").element as HTMLTextAreaElement).value).toBe(unsupported);
  expect(app.get("fieldset").attributes("disabled")).toBeUndefined();
  await app.get("#editor-discard").trigger("click");
  expect(
    JSON.parse((app.get("#editor-runtime-json").element as HTMLTextAreaElement).value),
  ).toEqual(JSON.parse(next.model.runtime_defaults_json));
  expect(app.get("#editor-save-state").text()).toBe("Saved");
});
test("arranging is a guarded local draft and stages all changed positions at the observed version", async () => {
  const next = editorFixture();
  next.sequence = 1;
  next.revision = 1;
  next.dirty = true;
  next.model.placements[0].layout.x = 2;
  const { app, execute, guard } = render(
    vi.fn(async () => ({ status: "ok", code: null, state: next })),
  );
  vi.stubGlobal(
    "confirm",
    vi.fn(() => false),
  );
  await app.get("#editor-arrange").trigger("click");
  expect(execute).not.toHaveBeenCalled();
  expect(guard()).toBe(true);
  const layouts = [{ placement_id: "battery", x: 2, y: 0, w: 4, h: 2 }];
  app.getComponent(EditorLayoutCanvas).vm.$emit("update:modelValue", layouts);
  await flushPromises();
  expect(guard()).toBe(false);
  await app.get("#editor-layout-save").trigger("click");
  await flushPromises();
  expect(execute).toHaveBeenCalledWith("layout", {
    sequence: 1,
    command: { expected_version: 1, expected_revision: 0, layouts },
  });
  expect(app.get("#editor-save-state").text()).toBe("Unsaved edits");
  expect(guard()).toBe(false);
});
test("a gesture blocks navigation and a newer saved draft locks an in-flight layout", async () => {
  const { app, execute, guard } = render();
  await app.get("#editor-arrange").trigger("click");
  app.getComponent(EditorLayoutCanvas).vm.$emit("gesture", true);
  await flushPromises();
  expect(guard()).toBe(false);
  const next = editorFixture();
  next.model.document_version = 2;
  await app.setProps({ state: next });
  await flushPromises();
  expect(app.get("#editor-save-state").text()).toBe("Review required");
  expect(app.get("#editor-layout-save").attributes("disabled")).toBeDefined();
  expect(execute).not.toHaveBeenCalled();
});
test("catalog selection becomes a local draft and uses the normal observed-version save", async () => {
  const execute = vi.fn(async (event: string) => {
    if (event !== "search_observables") throw Error("Inspect write only");
    return {
      status: "ok",
      choices: {
        version: 2,
        staging_revision: 0,
        organization_id: editorContext.organizationId,
        mission_id: editorContext.missionId,
        dashboard_id: editorContext.resourceId,
        document_version: 1,
        query: "",
        options: [{ value: "HK.voltage", label: "Voltage", description: "Active telemetry" }],
        more: false,
      },
    };
  });
  const { app } = render(execute);
  await app.get("#editor-add-widget").trigger("click");
  await app.get("#editor-widget-title").setValue("Voltage");
  await app.get("#editor-observable-search").trigger("click");
  await flushPromises();
  await app.get('[data-add-observable="HK.voltage"]').trigger("click");
  expect(execute).toHaveBeenCalledTimes(1);
  await app.get("#dashboard-editor-form").trigger("submit");
  await flushPromises();
  expect(execute).toHaveBeenLastCalledWith(
    "add_widget",
    expect.objectContaining({
      sequence: 1,
      command: expect.objectContaining({ expected_version: 1, observables: ["HK.voltage"] }),
    }),
  );
});

test("rename submits the observed version and retains native form identity after staging", async () => {
  const next = editorFixture();
  next.sequence = 1;
  next.revision = 1;
  next.dirty = true;
  next.model.name = "Changed";
  const { app, execute } = render(vi.fn(async () => ({ status: "ok", code: null, state: next })));
  const input = app.get("#editor-name").element;
  await app.get("#editor-name").setValue("Changed");
  expect(app.get("#editor-save-state").text()).toBe("Unsaved edits");
  await app.get("#dashboard-editor-form").trigger("submit");
  await flushPromises();
  expect(execute).toHaveBeenCalledWith("rename", {
    sequence: 1,
    command: {
      expected_version: 1,
      expected_revision: 0,
      name: "Changed",
      description: "Operator workspace",
    },
  });
  expect(app.get("#editor-name").element).toBe(input);
  expect(app.get("#editor-version").text()).toBe("Draft v1");
  expect(app.get("#editor-save-state").text()).toBe("Unsaved edits");
});
test("unsaved edits guard navigation and unload and dispose their host registration", async () => {
  const confirm = vi.fn(() => false);
  vi.stubGlobal("confirm", confirm);
  const { app, guard, removeGuard } = render();
  expect(guard()).toBe(true);
  await app.get("#editor-name").setValue("Unsaved");
  expect(guard()).toBe(false);
  expect(confirm).toHaveBeenCalledOnce();
  const unload = new Event("beforeunload", { cancelable: true });
  window.dispatchEvent(unload);
  expect(unload.defaultPrevented).toBe(true);
  confirm.mockReturnValue(true);
  expect(guard()).toBe(true);
  app.unmount();
  expect(removeGuard).toHaveBeenCalledOnce();
});
test("widget forms preserve numeric strings, multi-observable inputs and chart style enums", async () => {
  const { app, execute } = render(
    vi.fn(async () => {
      throw Error("stop after request");
    }),
  );
  await app.get("#editor-add-widget").trigger("click");
  await app.get("#editor-widget-title").setValue("Power trend");
  await app.get("#editor-widget-type").setValue("time_series");
  await app.get("#editor-widget-precision").setValue("3");
  await app.get("#editor-widget-fill").setValue("20");
  await app.get("#editor-widget-legend").setValue("hidden");
  await app.get("#editor-widget-line").setValue("bold");
  await app.get("#editor-observables").setValue("voltage\ncurrent");
  await app.get("#dashboard-editor-form").trigger("submit");
  await flushPromises();
  const [event, input] = execute.mock.calls[0];
  expect(event).toBe("add_widget");
  expect(input.command.observables).toEqual(["voltage", "current"]);
  expect(input.command.fields).toMatchObject({
    precision: "3",
    fill_opacity: "20",
    legend_mode: "hidden",
    line_width: "bold",
  });
});
test("known validation failures keep the draft editable without rewinding the sequence", async () => {
  const state = editorFixture();
  state.sequence = 1;
  const { app, execute } = render(
    vi.fn(async () => ({ status: "invalid", code: "invalid_title", state })),
  );
  await app.get("#editor-name").setValue("Unchanged local draft");
  await app.get("#dashboard-editor-form").trigger("submit");
  await flushPromises();
  expect((app.get("#editor-name").element as HTMLInputElement).value).toBe("Unchanged local draft");
  expect(app.get("fieldset").attributes("disabled")).toBeUndefined();
  await app.get("#dashboard-editor-form").trigger("submit");
  expect(execute.mock.calls[1][1].sequence).toBe(2);
});
test("pending and uncertain commands cannot be repeated or followed by publication", async () => {
  let reject!: (error: Error) => void;
  const { app, execute, guard } = render(
    vi.fn(
      () =>
        new Promise((_resolve, fail) => {
          reject = fail;
        }),
    ),
  );
  await app.get("#editor-name").setValue("Pending");
  await app.get("#dashboard-editor-form").trigger("submit");
  await app.get("#dashboard-editor-form").trigger("submit");
  expect(execute).toHaveBeenCalledOnce();
  expect(guard()).toBe(false);
  reject(Error("timeout"));
  await flushPromises();
  expect(app.get("fieldset").attributes("disabled")).toBeDefined();
  expect(app.get("#editor-review").attributes("disabled")).toBeDefined();
  await app.get("#dashboard-editor-form").trigger("submit");
  expect(execute).toHaveBeenCalledOnce();
});
test("a conflicting refresh preserves the local draft and requires explicit reload", async () => {
  const { app } = render();
  await app.get("#editor-name").setValue("Local draft");
  const next = editorFixture();
  next.model.document_version = 2;
  next.model.name = "Other operator";
  await app.setProps({ state: next });
  expect((app.get("#editor-name").element as HTMLInputElement).value).toBe("Local draft");
  expect(app.get("#editor-save-state").text()).toBe("Review required");
});
test("explicit reload reconciles an uncertain sequence without resending the write", async () => {
  vi.stubGlobal(
    "confirm",
    vi.fn(() => true),
  );
  const next = editorFixture();
  next.sequence = 1;
  const execute = vi
    .fn()
    .mockRejectedValueOnce(Error("request may not have arrived"))
    .mockResolvedValueOnce({ status: "ok", code: null, state: next });
  const { app, refresh } = render(execute);
  refresh.mockImplementation(async () => {
    await app.setProps({ state: editorFixture() });
  });
  await app.get("#editor-name").setValue("Unconfirmed local name");
  await app.get("#dashboard-editor-form").trigger("submit");
  await flushPromises();
  await app.get("#editor-reload").trigger("click");
  await flushPromises();
  expect(execute.mock.calls.map((call) => call[0])).toEqual(["rename", "reload_editor"]);
  expect(execute.mock.calls[1][1]).toEqual({ sequence: 1, command: {} });
  expect((app.get("#editor-name").element as HTMLInputElement).value).toBe("Flight overview");
  expect(app.get("fieldset").attributes("disabled")).toBeUndefined();
});
test("section and layout forms submit domain-specific shapes", async () => {
  const { app, execute } = render(
    vi.fn(async () => {
      throw Error("capture");
    }),
  );
  await app.get("#editor-add-section").trigger("click");
  await app.get("#editor-section-title").setValue("Thermal");
  await app.get("#editor-section-collapsed").setValue(true);
  await app.get("#dashboard-editor-form").trigger("submit");
  expect(execute).toHaveBeenCalledWith("add_section", {
    sequence: 1,
    command: {
      expected_version: 1,
      expected_revision: 0,
      title: "Thermal",
      description: "",
      collapsed_by_default: true,
    },
  });
  const second = render(
    vi.fn(async () => {
      throw Error("capture");
    }),
  );
  await second.app.get('[data-editor-layout="battery"]').trigger("click");
  await second.app.get("#editor-layout-w").setValue("6");
  await second.app.get("#dashboard-editor-form").trigger("submit");
  expect(second.execute).toHaveBeenCalledWith("layout", {
    sequence: 1,
    command: {
      expected_version: 1,
      expected_revision: 0,
      layouts: [{ placement_id: "battery", x: 0, y: 0, w: 6, h: 2 }],
    },
  });
});
test("library definitions retain their read-only boundary while layout remains available", async () => {
  const { app } = render();
  const state = editorFixture();
  state.model.placements[0].editable = false;
  state.model.placements[0].fields = null;
  state.model.placements[0].observables = [];
  await app.setProps({ state });
  await app.get('[data-editor-widget="battery"]').trigger("click");
  expect(app.find("#editor-definition-readonly").exists()).toBe(true);
  expect(app.find("#editor-widget-title").exists()).toBe(false);
  await app.get('[data-editor-layout="battery"]').trigger("click");
  expect(app.find("#editor-layout-w").exists()).toBe(true);
});

test("staged edits survive inspector changes and Save creates one durable version", async () => {
  const staged = editorFixture();
  Object.assign(staged, { sequence: 1, revision: 1, dirty: true });
  staged.model.name = "Candidate";
  const saved = structuredClone(staged);
  Object.assign(saved, { sequence: 2, revision: 2, dirty: false });
  saved.model.document_version = 2;
  const execute = vi
    .fn()
    .mockResolvedValueOnce({ status: "ok", state: staged })
    .mockResolvedValueOnce({ status: "ok", state: saved });
  const { app, guard } = render(execute);
  const confirm = vi.fn(() => false);
  vi.stubGlobal("confirm", confirm);
  await app.get("#editor-name").setValue("Candidate");
  await app.get("#dashboard-editor-form").trigger("submit");
  await flushPromises();
  await app.get("#editor-runtime").trigger("click");
  expect(confirm).not.toHaveBeenCalled();
  expect(app.find("#editor-runtime-json").exists()).toBe(true);
  expect(guard()).toBe(false);
  const unload = new Event("beforeunload", { cancelable: true });
  window.dispatchEvent(unload);
  expect(unload.defaultPrevented).toBe(true);
  expect(app.get("#editor-staging-state").text()).toContain("Candidate r1");
  await app.get("#editor-save-draft").trigger("click");
  await flushPromises();
  expect(execute.mock.calls.map(([event]) => event)).toEqual(["rename", "save_draft"]);
  expect(execute.mock.calls[1][1]).toEqual({
    sequence: 2,
    command: { expected_version: 1, expected_revision: 1 },
  });
  expect(app.get("#editor-version").text()).toBe("Draft v2");
  expect(app.get("#editor-save-state").text()).toBe("Saved");
  expect(guard()).toBe(true);
});

test("Save includes unapplied fields and Review navigates only after the saved acknowledgement", async () => {
  const staged = editorFixture();
  Object.assign(staged, { sequence: 1, revision: 1, dirty: true });
  staged.model.name = "Review candidate";
  const saved = structuredClone(staged);
  Object.assign(saved, { sequence: 2, revision: 2, dirty: false });
  saved.model.document_version = 2;
  let acknowledge!: (value: unknown) => void;
  const execute = vi
    .fn()
    .mockResolvedValueOnce({ status: "ok", state: staged })
    .mockImplementationOnce(
      () =>
        new Promise((resolve) => {
          acknowledge = resolve;
        }),
    );
  const { app, guard } = render(execute);
  await app.get("#editor-name").setValue("Review candidate");
  await app.get("#editor-review").trigger("click");
  await flushPromises();
  expect(execute.mock.calls.map(([event]) => event)).toEqual(["rename", "save_draft"]);
  expect(app.props("port").navigate).not.toHaveBeenCalled();
  expect(guard()).toBe(false);
  acknowledge({ status: "ok", state: saved });
  await flushPromises();
  expect(app.props("port").navigate).toHaveBeenCalledWith(
    "/missions/mission-1/ops/dashboards/dashboard-1/activity?version=2",
  );
  expect(guard()).toBe(true);
});

test("Discard confirms the entire candidate and does not stage unapplied fields", async () => {
  const discarded = editorFixture();
  Object.assign(discarded, { sequence: 2, revision: 2 });
  const { app, execute, guard } = render(vi.fn(async () => ({ status: "ok", state: discarded })));
  const staged = editorFixture();
  Object.assign(staged, { sequence: 1, revision: 1, dirty: true });
  staged.model.name = "Staged";
  await app.setProps({ state: staged });
  await app.get("#editor-name").setValue("Unapplied");
  const confirm = vi.fn(() => false);
  vi.stubGlobal("confirm", confirm);
  await app.get("#editor-discard-draft").trigger("click");
  expect(execute).not.toHaveBeenCalled();
  confirm.mockReturnValue(true);
  await app.get("#editor-discard-draft").trigger("click");
  await flushPromises();
  expect(execute).toHaveBeenCalledExactlyOnceWith("discard_draft", {
    sequence: 2,
    command: { expected_version: 1, expected_revision: 1 },
  });
  expect((app.get("#editor-name").element as HTMLInputElement).value).toBe("Flight overview");
  expect(app.get("#editor-version").text()).toBe("Draft v1");
  expect(guard()).toBe(true);
});

test("failed or stale Save replies retain unsaved work and cannot open publication review", async () => {
  for (const outcome of ["unknown", "stale", "dirty", "version"]) {
    const staged = editorFixture();
    Object.assign(staged, { sequence: 1, revision: 1, dirty: true });
    staged.model.name = "Candidate";
    const reply = structuredClone(staged);
    Object.assign(reply, { sequence: 2, revision: 2, dirty: false });
    reply.model.document_version = 2;
    if (outcome === "stale") reply.revision = 1;
    if (outcome === "dirty") reply.dirty = true;
    if (outcome === "version") reply.model.document_version = 1;
    const { app } = render(
      vi.fn(async () => ({ status: outcome === "unknown" ? "unknown" : "ok", state: reply })),
    );
    await app.setProps({ state: staged });
    await app.get("#editor-review").trigger("click");
    await flushPromises();
    expect(app.props("port").navigate).not.toHaveBeenCalled();
    expect(app.get("#editor-save-state").text()).toBe("Review required");
    expect((app.get("#editor-name").element as HTMLInputElement).value).toBe("Candidate");
  }
});

test("a replacement host port retains the current dirty navigation guard", async () => {
  const { app, removeGuard } = render();
  vi.stubGlobal(
    "confirm",
    vi.fn(() => false),
  );
  const state = editorFixture();
  state.dirty = true;
  state.revision = 1;
  await app.setProps({ state });
  let guard!: () => boolean;
  const dispose = vi.fn();
  await app.setProps({
    port: {
      execute: vi.fn(),
      navigate: vi.fn(),
      guardNavigation(fn) {
        guard = fn;
        return dispose;
      },
    },
  });
  expect(removeGuard).toHaveBeenCalledOnce();
  expect(guard()).toBe(false);
  app.unmount();
  expect(dispose).toHaveBeenCalledOnce();
});
