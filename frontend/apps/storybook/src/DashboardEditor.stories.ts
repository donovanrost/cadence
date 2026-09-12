import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect, userEvent, within } from "storybook/test";
import { ref } from "vue";
import { DashboardEditor, type EditorState } from "@cadence/dashboards-and-exploration/editor";

const widgetDefaults = {
  type: "value_tile",
  title: "",
  mode: "context",
  spacecraft_id: "",
  scope_kind: "",
  scope_id: "",
  section_id: "",
  binding_source: "telemetry",
  precision: "2",
  window_seconds: "300",
  show_unit: "true",
  show_min_max_band: "true",
  legend_mode: "auto",
  line_width: "normal",
  fill_opacity: "0",
  span_gaps: "false",
  show_points: "false",
  axis_mode: "unit",
  shared_tooltip: "true",
  repeat_over: "spacecraft",
  repeat_layout: "wrap_grid",
  repeat_max_instances: "12",
};

const editorContext = {
  organizationId: "org-1",
  missionId: "mission-1",
  resourceId: "dashboard-1",
};
function editorFixture(): EditorState {
  return {
    version: 2,
    revision: 0,
    dirty: false,
    sequence: 0,
    phase: "editing",
    model: {
      version: 3,
      organization_id: "org-1",
      mission_id: "mission-1",
      dashboard_id: "dashboard-1",
      document_version: 1,
      name: "Flight overview",
      description: "Operator workspace",
      defaults: { ...widgetDefaults },
      runtime_defaults_json: JSON.stringify({
        time: { mode: "live", refresh_ms: 1000 },
        data: { realm: "flight" },
        overlays: { quality: true },
      }),
      grid: { columns: 12, row_height_px: 64, gap_px: 8 },
      sections: [{ id: "power", title: "Power", description: "", collapsed_by_default: false }],
      placements: [
        {
          id: "battery",
          section_id: "power",
          title: "Battery voltage",
          editable: true,
          fields: { ...widgetDefaults, title: "Battery voltage", section_id: "power" },
          observables: ["tlm.hk.battery_voltage"],
          layout: { x: 0, y: 0, w: 4, h: 2 },
          constraints: { min_w: 2, min_h: 2, max_w: 12, max_h: 24, max_y: 23 },
        },
      ],
      preview: null,
    },
  };
}

const meta = {
  title: "Modules/Dashboards/Editor",
  component: DashboardEditor,
  parameters: { layout: "fullscreen" },
  args: {
    state: editorFixture(),
    context: editorContext,
    port: { execute: async () => {}, navigate() {}, guardNavigation: () => () => {} },
    refresh: async () => {},
  },
  render: (args, { parameters }) => ({
    components: { DashboardEditor },
    setup() {
      let current: EditorState = JSON.parse(JSON.stringify(args.state));
      let saved = editorFixture().model;
      const destination = ref("");
      const requests = ref<string[]>([]);
      const port = {
        guardNavigation: () => () => {},
        navigate(href: string) {
          destination.value = href;
        },
        async execute(event: string, input: Record<string, unknown>) {
          requests.value.push(event);
          const command = input.command as Record<string, unknown>;
          if (parameters.failSave && event === "save_draft")
            throw Error("Preview save unavailable");
          const next: EditorState = JSON.parse(JSON.stringify(current));
          next.sequence = input.sequence as number;
          next.revision++;
          if (event === "rename") {
            next.model.name = command.name as string;
            next.model.description = command.description as string;
            next.dirty = true;
          } else if (event === "save_draft") {
            if (next.dirty) next.model.document_version++;
            next.dirty = false;
            saved = JSON.parse(JSON.stringify(next.model));
          } else if (event === "discard_draft" || event === "reload_editor") {
            next.model = JSON.parse(JSON.stringify(saved));
            next.dirty = false;
            if (event === "reload_editor") next.revision = 0;
          } else {
            return {
              status: "invalid",
              code: "invalid_input",
              state: { ...current, sequence: next.sequence },
            };
          }
          current = next;
          return { status: "ok", state: next };
        },
      };
      return { args, port, destination, requests };
    },
    template:
      '<div class="p-4 lg:p-6"><DashboardEditor v-bind="args" :port="port" /><p class="mt-6 text-xs text-base-content/60">Preview transport: metadata staging, Save and Discard only. No records are written.</p><output aria-label="Requested actions" class="block font-mono text-xs">{{ requests.join(", ") }}</output><output aria-label="Requested destination" class="block break-all font-mono text-xs">{{ destination }}</output></div>',
  }),
} satisfies Meta<typeof DashboardEditor>;
export default meta;
type Story = StoryObj<typeof meta>;
export const SavedDraft: Story = {};
export const SaveAndReview: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.clear(canvasElement.querySelector("#editor-name")!);
    await userEvent.type(canvasElement.querySelector("#editor-name")!, "Power candidate");
    await userEvent.click(canvas.getByRole("button", { name: "Apply to candidate" }));
    await expect(canvasElement.querySelector("#editor-version")).toHaveTextContent("Draft v1");
    await expect(canvasElement.querySelector("#editor-save-state")).toHaveTextContent(
      "Unsaved edits",
    );
    await userEvent.click(canvas.getByRole("button", { name: "Runtime defaults" }));
    await userEvent.click(canvas.getByRole("button", { name: "Save draft" }));
    await expect(canvasElement.querySelector("#editor-version")).toHaveTextContent("Draft v2");
    await expect(canvasElement.querySelector("#editor-save-state")).toHaveTextContent("Saved");
    await userEvent.click(canvas.getByRole("button", { name: "Review & publish" }));
    await expect(canvas.getByLabelText("Requested destination")).toHaveTextContent(
      "/missions/mission-1/ops/dashboards/dashboard-1/activity?version=2",
    );
    await expect(canvas.getByLabelText("Requested actions")).toHaveTextContent(
      "rename, save_draft, save_draft",
    );
  },
};
export const StagedCandidate: Story = {
  args: { state: { ...editorFixture(), sequence: 3, revision: 3, dirty: true } },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvasElement.querySelector("#editor-staging-state")).toHaveTextContent(
      "Candidate r3",
    );
    await expect(canvas.getByRole("button", { name: "Discard all changes" })).toBeEnabled();
    await expect(canvas.getByRole("button", { name: "Save draft" })).toBeEnabled();
  },
};
export const FailedSave: Story = {
  args: StagedCandidate.args,
  parameters: { failSave: true },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("button", { name: "Save draft" }));
    await expect(canvasElement.querySelector("#editor-save-state")).toHaveTextContent(
      "Review required",
    );
    await expect(canvas.getByRole("button", { name: "Review & publish" })).toBeDisabled();
    await expect(canvas.getByRole("button", { name: "Reload saved draft" })).toBeEnabled();
  },
};
export const PreviewUnavailable: Story = {
  play: async ({ canvasElement }) => {
    await userEvent.click(canvasElement.querySelector("#editor-preview summary")!);
    await expect(within(canvasElement).getByText(/Preview is unavailable/)).toBeVisible();
    await expect(canvasElement.querySelector("#editor-name")).toBeEnabled();
  },
};
