import { required } from "../../../test-support/required";
import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect, userEvent, within } from "storybook/test";
import { ref } from "vue";
import {
  ExplorationPanel,
  readExploration,
  type ExplorationModel,
} from "@cadence/dashboards-and-exploration/exploration";

const model: ExplorationModel = {
  version: 3,
  organization_id: "story-org",
  mission_id: "story-mission",
  query: {
    point_id: "EPS.battery_voltage",
    time_mode: "last_1h",
    source_binding_id: "flight-telemetry-v3",
    source_dashboard_id: "power-overview",
  },
  loaded_at: "2026-09-07T12:00:00.123456Z",
  origin: { status: "ready", dashboard: { id: "power-overview", name: "Power overview" } },
  status: "ready",
  effective_time: {
    mode: "range",
    axis: "receipt_time",
    from: "2026-09-07T11:00:00.123456Z",
    to: "2026-09-07T12:00:00.123456Z",
  },
  rows: [
    {
      key: "a".repeat(64),
      point_id: "EPS.battery_voltage",
      sample_id: "sample/one",
      time: "2026-09-07T11:59:59.654321Z",
      axis: "receipt_time",
      value: 28.42,
      value_kind: "number",
      unit: "V",
      source: {
        data_source_id: "spacecraft-telemetry",
        source_binding_id: "flight-telemetry-v3",
        dataset: "flight",
        realm: "flight",
      },
    },
  ],
  limited: false,
  warnings: [],
  warnings_limited: false,
  inspection: { status: "not_selected", sample: null },
};
const inspected: ExplorationModel = {
  ...model,
  query: { ...model.query, sample_id: "sample/one" },
  inspection: {
    status: "ready",
    sample: {
      point_id: "EPS.battery_voltage",
      point_name: "Battery voltage",
      sample_id: "sample/one",
      spacecraft_id: "cadence-01",
      receipt_time: "2026-09-07T11:59:59.654321Z",
      generation_time: "2026-09-07T11:59:58.123456Z",
      quality: "suspect",
      raw_value: { state: "ready", text: '{"adc":2842}', format: "json" },
      engineering_value: { state: "ready", text: "28.42", format: "json" },
      source: {
        data_source_id: "spacecraft-telemetry",
        source_binding_id: "flight-telemetry-v3",
        realm: "flight",
        source_endpoint_id: "downlink-primary",
        replay_run_id: null,
      },
      record: {
        packet_id: "packet-782",
        evidence_id: "evidence-782",
        packet_definition_id: "EPS-housekeeping",
        packet_definition_version: 3,
        validity_state: "superseded",
      },
    },
  },
};
const meta = {
  title: "Modules/Dashboards/Exploration",
  component: ExplorationPanel,
  parameters: { layout: "fullscreen" },
  args: {
    model,
    context: { organizationId: model.organization_id, missionId: model.mission_id },
    port: { navigate() {} },
    refresh: async () => {},
  },
  render: (args) => ({
    components: { ExplorationPanel },
    setup() {
      const current = ref<ExplorationModel>(
        readExploration(JSON.parse(JSON.stringify(args.model)), {
          organizationId: model.organization_id,
          missionId: model.mission_id,
        }),
      );
      const destination = ref("");
      const port = {
        navigate(href: string) {
          destination.value = href;
          if (!new URL(href, "https://cadence.test").pathname.endsWith("/ops/explore")) return;
          const query = Object.fromEntries(new URL(href, "https://cadence.test").searchParams);
          current.value = {
            ...current.value,
            query,
            inspection: query.sample_id
              ? { status: "not_found", sample: null }
              : { status: "not_selected", sample: null },
          };
        },
      };
      async function refresh() {
        const action: unknown = args.refresh;
        if (typeof action !== "function") throw Error("Expected the story refresh action");
        await Reflect.apply(action, undefined, []);
        current.value = { ...current.value, loaded_at: "2026-09-07T12:01:00.123456Z" };
      }
      return { args, current, destination, port, refresh };
    },
    template:
      '<ExplorationPanel v-bind="args" :model="current" :port="port" :refresh="refresh" /><output aria-label="Requested destination" class="block break-all p-4 font-mono text-xs">{{ destination }}</output>',
  }),
} satisfies Meta<typeof ExplorationPanel>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Observations: Story = {
  name: "Production observations",
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("table")).toHaveTextContent("28.42");
    await userEvent.click(canvas.getByRole("button", { name: "sample/one" }));
    const selected = new URL(
      required(canvas.getByLabelText("Requested destination").textContent),
      "https://cadence.test",
    );
    await expect(selected.searchParams.get("selected_time")).toBe("2026-09-07T11:59:59.654321Z");
    await expect(selected.searchParams.get("from")).toBe("2026-09-07T11:00:00.123456Z");
    await expect(selected.searchParams.get("source_binding_id")).toBe("flight-telemetry-v3");
    await userEvent.click(canvas.getByRole("button", { name: "Clear selection" }));
    await expect(canvasElement.querySelector("#exploration-selection")).not.toBeInTheDocument();
    await userEvent.click(canvas.getByRole("button", { name: "Read again" }));
    await expect(canvasElement.querySelector("#exploration-loaded-at")).toHaveAttribute(
      "datetime",
      "2026-09-07T12:01:00.123456Z",
    );
  },
};
export const NoObservations: Story = {
  args: { model: { ...model, rows: [], status: "empty" } },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(
      canvas.getByText("The selected source returned no observations for this query."),
    ).toBeVisible();
    await expect(canvas.queryByRole("table")).not.toBeInTheDocument();
    await expect(canvas.getByRole("button", { name: "Run query" })).toBeEnabled();
  },
};
export const SourceDashboard: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const link = canvas.getByRole("link", { name: "Open source dashboard" });
    await expect(link).toHaveAttribute(
      "href",
      "/missions/story-mission/ops/dashboards/power-overview",
    );
    await userEvent.click(link);
    await expect(canvas.getByLabelText("Requested destination")).toHaveTextContent(
      "/missions/story-mission/ops/dashboards/power-overview",
    );
  },
};
export const UnavailableOrigin: Story = {
  args: { model: { ...model, origin: { status: "unavailable", dashboard: null } } },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByText(/The source dashboard is unavailable/)).toBeVisible();
    await expect(
      canvas.queryByRole("link", { name: "Open source dashboard" }),
    ).not.toBeInTheDocument();
    await expect(canvas.getByRole("table")).toBeVisible();
  },
};
export const UnsupportedScope: Story = {
  args: {
    model: {
      ...model,
      rows: [],
      effective_time: null,
      status: "unsupported_exploration_scope",
      query: { ...model.query, scope_kind: "transport", scope_id: "transport-one" },
    },
  },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByText("Source and scope", { exact: true }));
    await expect(canvas.getByLabelText("Scope kind", { exact: true })).toHaveValue("transport");
    await expect(canvas.getByLabelText("Scope ID", { exact: true })).toHaveValue("transport-one");
    await expect(canvas.getByText(/No broader query was executed/)).toBeVisible();
  },
};
export const FailedRefresh: Story = {
  args: {
    model: inspected,
    refresh: async () => {
      throw Error("Fixture read unavailable");
    },
  },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("button", { name: "Read again" }));
    await expect(canvas.getByRole("alert")).toHaveTextContent("could not be confirmed");
    await expect(canvas.queryByRole("table")).not.toBeInTheDocument();
    await expect(
      canvasElement.querySelector("#exploration-sample-details"),
    ).not.toBeInTheDocument();
    await expect(canvas.getByRole("button", { name: "Read again" })).toBeEnabled();
  },
};
export const SampleDetails: Story = {
  args: { model: inspected },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvasElement.querySelector("#exploration-sample-raw_value")).toHaveTextContent(
      '{"adc":2842}',
    );
    await expect(canvasElement.querySelector("#exploration-sample-receipt")).toHaveAttribute(
      "datetime",
      "2026-09-07T11:59:59.654321Z",
    );
    await userEvent.click(canvas.getByText("Record provenance", { exact: true }));
    await expect(canvasElement.querySelector("#exploration-sample-validity")).toBeVisible();
    await expect(canvas.getByText("evidence-782", { exact: true })).toBeVisible();
  },
};
export const AmbiguousSample: Story = {
  args: { model: { ...inspected, inspection: { status: "ambiguous", sample: null } } },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvasElement.querySelector("#exploration-sample-state")).toHaveTextContent(
      "More than one physical record",
    );
    await expect(canvas.getByRole("table")).toBeVisible();
  },
};
export const LimitedSampleValue: Story = {
  args: {
    model: {
      ...inspected,
      inspection:
        inspected.inspection.status === "ready"
          ? {
              status: "ready",
              sample: {
                ...inspected.inspection.sample,
                raw_value: { state: "limited", text: null, format: null },
                generation_time: null,
              },
            }
          : inspected.inspection,
    },
  },
  play: async ({ canvasElement }) => {
    await expect(within(canvasElement).getByText("Value exceeds display limits")).toBeVisible();
    await expect(
      canvasElement.querySelector("#exploration-sample-generation"),
    ).not.toBeInTheDocument();
  },
};
