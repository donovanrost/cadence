import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect } from "storybook/test";
import MissionOperationsSpecimen from "./MissionOperationsSpecimen.vue";
import { monitoringScenarioIds } from "./monitoring-fixtures";
import type { MonitoringScenarioId } from "./monitoring-fixtures";

interface MissionOperationsSpecimenArgs {
  monitoringScenario: MonitoringScenarioId;
}

const meta = {
  title: "Compositions/Mission Operations/Pass Overview",
  component: MissionOperationsSpecimen,
  tags: ["generation-02"],
  args: {
    monitoringScenario: "nominal-live",
  },
  argTypes: {
    monitoringScenario: {
      control: "select",
      options: monitoringScenarioIds,
    },
  },
  parameters: {
    layout: "fullscreen",
  },
} satisfies Meta<MissionOperationsSpecimenArgs>;

export default meta;
type Story = StoryObj<MissionOperationsSpecimenArgs>;

export const WorkingDirection: Story = {};

export const TelemetryFreshnessCaution: Story = {
  args: {
    monitoringScenario: "telemetry-caution",
  },
  play: async ({ canvas, userEvent }) => {
    const telemetry = canvas.getByRole("button", {
      name: /TM VC-01 Telemetry stream Caution Frames are arriving beyond the 15-second freshness threshold/,
    });

    await expect(canvas.getByText("Artemis relay · Pass 042")).toBeVisible();
    await expect(canvas.getByText("UTC · Live")).toBeVisible();
    await expect(telemetry).toHaveAttribute("aria-expanded", "false");

    await userEvent.click(telemetry);

    await expect(telemetry).toHaveAttribute("aria-expanded", "true");
    await expect(
      canvas.getByRole("region", { name: "TM VC-01 monitoring evidence" }),
    ).toBeVisible();
    await expect(canvas.getByText("18.4 s")).toBeVisible();
  },
};

export const CommandReadiness: Story = {
  play: async ({ canvas, userEvent }) => {
    const approvalButton = canvas.getByRole("button", { name: "Request approval" });
    const readiness = canvas.getByRole("checkbox", {
      name: "I verified the command parameters against procedure OPS-214.",
    });

    await expect(approvalButton).toBeDisabled();
    await userEvent.click(readiness);
    await expect(readiness).toBeChecked();
    await expect(approvalButton).toBeEnabled();
  },
};
