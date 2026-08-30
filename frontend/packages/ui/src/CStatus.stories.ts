import type { Meta, StoryObj } from "@storybook/vue3-vite";
import CStatus from "./CStatus.vue";

interface StatusArgs {
  pulse: boolean;
  tone: "nominal" | "warning" | "danger" | "neutral";
}

const meta = {
  title: "Components/Feedback/Status",
  component: CStatus,
  tags: ["generation-02"],
  args: {
    pulse: false,
    tone: "neutral",
  },
  argTypes: {
    tone: {
      control: "inline-radio",
      options: ["nominal", "warning", "danger", "neutral"],
    },
  },
  render: (args) => ({
    components: { CStatus },
    setup: () => ({ args }),
    template: '<CStatus v-bind="args">Ground link state</CStatus>',
  }),
} satisfies Meta<StatusArgs>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Playground: Story = {};

export const ToneMatrix: Story = {
  parameters: { controls: { disable: true } },
  render: () => ({
    components: { CStatus },
    template: `
      <div class="story-column">
        <CStatus tone="nominal" pulse>Nominal</CStatus>
        <CStatus tone="warning">Degraded</CStatus>
        <CStatus tone="danger">Unavailable</CStatus>
        <CStatus tone="neutral">Unknown</CStatus>
      </div>
    `,
  }),
};
