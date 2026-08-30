import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect } from "storybook/test";
import { computed, ref } from "vue";
import MissionMonitoringRail from "./MissionMonitoringRail.vue";
import {
  getMonitoringScenario,
  monitoringScenarioIds,
  monitoringScenarios,
} from "./monitoring-fixtures";
import type { MonitoringScenario, MonitoringScenarioId } from "./monitoring-fixtures";

interface MissionMonitoringRailArgs {
  scenarioId: MonitoringScenarioId;
}

const scenarioOptions: ReadonlyArray<{ id: MonitoringScenarioId; label: string }> = [
  { id: "nominal-live", label: "Nominal live" },
  { id: "planned-standby", label: "Planned standby" },
  { id: "telemetry-caution", label: "Telemetry caution" },
  { id: "link-serious", label: "Link serious" },
  { id: "command-critical", label: "Command critical" },
  { id: "coverage-unknown", label: "Coverage unknown" },
];

const longIdentifierScenario: MonitoringScenario = {
  ...monitoringScenarios["nominal-live"],
  label: "Long identifier verification",
  items: monitoringScenarios["nominal-live"].items.map((item) =>
    item.id === "lunar-relay-02"
      ? {
          ...item,
          identifier: "LUNAR-RELAY-DEMONSTRATOR-02",
          subject: "Cislunar communications technology demonstrator",
        }
      : item,
  ),
};

const meta = {
  title: "Compositions/Mission Operations/Monitoring Rail",
  component: MissionMonitoringRail,
  tags: ["generation-02"],
  args: {
    scenarioId: "nominal-live",
  },
  argTypes: {
    scenarioId: {
      control: "select",
      options: monitoringScenarioIds,
    },
  },
  parameters: {
    layout: "fullscreen",
  },
  render: (args) => ({
    components: { MissionMonitoringRail },
    setup: () => ({ scenario: computed(() => getMonitoringScenario(args.scenarioId)) }),
    template: `
      <main class="monitoring-rail-story">
        <MissionMonitoringRail :scenario="scenario" />
      </main>
    `,
  }),
} satisfies Meta<MissionMonitoringRailArgs>;

export default meta;
type Story = StoryObj<MissionMonitoringRailArgs>;

export const LiveNominal: Story = {};

export const PlannedStandby: Story = {
  args: { scenarioId: "planned-standby" },
};

export const TelemetryCaution: Story = {
  args: { scenarioId: "telemetry-caution" },
  play: async ({ canvas, userEvent }) => {
    const telemetry = canvas.getByRole("button", {
      name: /TM VC-01 Telemetry stream Caution Frames are arriving beyond the 15-second freshness threshold/,
    });

    await expect(telemetry).toHaveAttribute("aria-expanded", "false");
    await userEvent.click(telemetry);
    await expect(telemetry).toHaveAttribute("aria-expanded", "true");
    await expect(
      canvas.getByRole("region", { name: "TM VC-01 monitoring evidence" }),
    ).toBeVisible();
  },
};

export const LinkSerious: Story = {
  args: { scenarioId: "link-serious" },
};

export const CommandCritical: Story = {
  args: { scenarioId: "command-critical" },
};

export const CoverageUnknown: Story = {
  args: { scenarioId: "coverage-unknown" },
};

export const LiveScenarioSwitching: Story = {
  parameters: {
    controls: { disable: true },
  },
  render: () => ({
    components: { MissionMonitoringRail },
    setup: () => {
      const activeScenarioId = ref<MonitoringScenarioId>("nominal-live");
      const scenario = computed(() => getMonitoringScenario(activeScenarioId.value));

      return { activeScenarioId, scenario, scenarioOptions };
    },
    template: `
      <main class="monitoring-rail-story">
        <nav class="monitoring-scenario-switcher" aria-label="Monitoring scenarios">
          <button
            v-for="option in scenarioOptions"
            :key="option.id"
            type="button"
            :aria-pressed="activeScenarioId === option.id"
            @click="activeScenarioId = option.id"
          >
            {{ option.label }}
          </button>
        </nav>
        <MissionMonitoringRail :scenario="scenario" />
      </main>
    `,
  }),
  play: async ({ canvas, userEvent }) => {
    const nominalTelemetry = canvas.getByRole("button", {
      name: /TM VC-01 Telemetry stream Normal Frames are current/,
    });

    await userEvent.click(nominalTelemetry);
    await expect(
      canvas.getByRole("region", { name: "TM VC-01 monitoring evidence" }),
    ).toBeVisible();

    await userEvent.click(canvas.getByRole("button", { name: "Telemetry caution" }));

    const cautionTelemetry = canvas.getByRole("button", {
      name: /TM VC-01 Telemetry stream Caution Frames are arriving/,
    });
    await expect(cautionTelemetry).toHaveAttribute("aria-expanded", "true");
    await expect(canvas.getByText("Artemis relay · Pass 042")).toBeVisible();
    await expect(canvas.getByText("UTC · Live")).toBeVisible();
    await expect(canvas.getByText("18.4 s")).toBeVisible();
  },
};

export const LongCanonicalIdentifier: Story = {
  parameters: {
    controls: { disable: true },
  },
  render: () => ({
    components: { MissionMonitoringRail },
    setup: () => ({ scenario: longIdentifierScenario }),
    template: `
      <main class="monitoring-rail-story">
        <MissionMonitoringRail :scenario="scenario" />
      </main>
    `,
  }),
  play: async ({ canvas }) => {
    await expect(canvas.getByText("LUNAR-RELAY-DEMONSTRATOR-02")).toBeVisible();
    await expect(canvas.getByText("Cislunar communications technology demonstrator")).toBeVisible();
  },
};

export const ScenarioIndex: Story = {
  parameters: {
    controls: { disable: true },
  },
  render: () => ({
    components: { MissionMonitoringRail },
    setup: () => ({ scenarios: Object.values(monitoringScenarios) }),
    template: `
      <main class="monitoring-scenario-index">
        <header>
          <p class="story-state">Cadence / operational monitoring</p>
          <h1>Evidence before inference.</h1>
          <p>
            Each fixture preserves mission scope and UTC context while exercising a distinct
            operational state. Select a subject row to inspect the evidence behind its assessment.
          </p>
        </header>
        <MissionMonitoringRail
          v-for="scenario in scenarios"
          :key="scenario.id"
          :scenario="scenario"
        />
      </main>
    `,
  }),
};
