import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect, userEvent, within } from "storybook/test";
import { ref } from "vue";
import {
  ExecutionDiagnosticsView,
  collectionIds,
  initialSelection,
  type ExecutionDiagnostics,
  type DiagnosticSelection,
} from "@cadence/dashboards-and-exploration/execution-diagnostics";

const model: ExecutionDiagnostics = {
  version: 2,
  organization_id: "story-org",
  mission_id: "story-mission",
  dashboard_id: "power-overview",
  name: "Power overview",
  document_version: 12,
  loaded_at: "2026-09-07T18:42:09.000Z",
  collections: collectionIds.map((id, index) => ({
    id,
    state: "ready",
    source: index < 5 ? "inspection" : "durable",
    limited: false,
    rows:
      id === "plan"
        ? [
            {
              kind: "plan",
              id: "a".repeat(64),
              identity: "power-overview",
              title: "Resolve plan",
              status: "degraded",
              details: [
                { key: "resolve_mode", value: "initial" },
                { key: "requests", value: 6 },
                { key: "executed_requests", value: 5 },
                { key: "skipped_requests", value: 1 },
                { key: "returned_frames", value: 5 },
                { key: "warnings", value: 1 },
                { key: "live_append_eligible", value: false },
                { key: "snapshot", value: false },
              ],
            },
            {
              kind: "plan_warning",
              id: "c".repeat(64),
              identity: "d".repeat(64),
              title: "unsupported_source_capability",
              status: "warning",
              details: [
                { key: "warning_code", value: "unsupported_source_capability" },
                { key: "scope", value: "placement" },
                { key: "placement_id", value: "battery-voltage" },
                { key: "frame_id", value: null },
                { key: "field_name", value: null },
                { key: "source_request_id", value: "telemetry-battery-voltage" },
                { key: "logical_source", value: "telemetry" },
              ],
            },
          ]
        : [],
  })),
};
const meta = {
  title: "Modules/Dashboards/Execution Diagnostics",
  component: ExecutionDiagnosticsView,
  parameters: { layout: "fullscreen" },
  args: {
    model,
    context: {
      organizationId: model.organization_id,
      missionId: model.mission_id,
      resourceId: model.dashboard_id,
    },
    selection: { ...initialSelection(), row: "a".repeat(64) },
  },
  render: (args) => ({
    components: { ExecutionDiagnosticsView },
    setup() {
      const selection = ref<DiagnosticSelection>(args.selection);
      return { args, selection };
    },
    template:
      '<ExecutionDiagnosticsView v-bind="args" :selection="selection" @select="selection = $event" />',
  }),
} satisfies Meta<typeof ExecutionDiagnosticsView>;
export default meta;
type Story = StoryObj<typeof meta>;
export const PlanWarning: Story = {
  args: { selection: { ...initialSelection(), row: "c".repeat(64) } },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByLabelText("Diagnostic identity")).toHaveValue("d".repeat(64));
    await expect(
      canvasElement.querySelector('[data-diagnostic-field="warning_code"]'),
    ).toHaveTextContent("unsupported_source_capability");
    await expect(
      canvasElement.querySelector('[data-diagnostic-field="placement_id"]'),
    ).toHaveTextContent("battery-voltage");
    await userEvent.type(canvas.getByLabelText("Filter loaded rows"), "battery-voltage");
    await userEvent.click(canvas.getByRole("button", { name: "Apply filter" }));
    await expect(canvasElement.querySelectorAll("#diagnostics-rows li")).toHaveLength(1);
    await expect(canvas.getByLabelText("Diagnostic identity")).toHaveValue("d".repeat(64));
  },
};
export const Inspection: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByLabelText("Diagnostic identity")).toHaveValue("power-overview");
    await userEvent.type(canvas.getByLabelText("Filter loaded rows"), "not-present");
    await userEvent.click(canvas.getByRole("button", { name: "Apply filter" }));
    await expect(canvas.getByText(/selected row is outside the current filter/)).toBeVisible();
    await expect(canvas.getByLabelText("Diagnostic identity")).toHaveValue("power-overview");
    await userEvent.click(canvas.getByRole("button", { name: /^Clear$/ }));
    await userEvent.click(canvas.getByRole("button", { name: /^Refresh/ }));
    await expect(canvas.getByText("Durable decision history")).toBeVisible();
    await userEvent.click(canvas.getByRole("button", { name: /^Plan/ }));
    await userEvent.click(
      canvas.getByRole("button", { name: /Resolve plan power-overview degraded/ }),
    );
    await expect(canvas.getByLabelText("Diagnostic identity")).toHaveValue("power-overview");
  },
};
const partial = structuredClone(model);
partial.collections[1] = {
  id: "requests",
  state: "unavailable",
  source: null,
  limited: false,
  rows: [],
};
partial.collections[5].source = "process_local";
export const PartialEvidence: Story = {
  args: { model: partial, selection: { collection: "requests", row: null, filter: "" } },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByText(/This evidence could not be loaded/)).toBeVisible();
    await userEvent.click(canvas.getByRole("button", { name: /^Refresh/ }));
    await expect(canvas.getByText(/No durable decisions were found/)).toBeVisible();
    await userEvent.click(canvas.getByRole("button", { name: /^Requests/ }));
  },
};
export const MissingSelection: Story = {
  args: { selection: { ...initialSelection(), row: "b".repeat(64) } },
  play: async ({ canvasElement }) => {
    await expect(
      within(canvasElement).getByText(/no replacement row has been selected/),
    ).toBeVisible();
  },
};
