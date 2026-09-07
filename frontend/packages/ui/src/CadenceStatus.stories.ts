import type { Meta, StoryObj } from "@storybook/vue3-vite";
import CadenceStatus from "./CadenceStatus.vue";

interface StatusArgs {
  pulse: boolean;
  tone: "nominal" | "warning" | "danger" | "neutral";
}

const meta = {
  title: "Components/Feedback/Status",
  component: CadenceStatus,
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
    components: { CadenceStatus },
    setup: () => ({ args }),
    template: '<CadenceStatus v-bind="args">Ground link state</CadenceStatus>',
  }),
} satisfies Meta<StatusArgs>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Playground: Story = {};

export const ToneMatrix: Story = {
  parameters: { controls: { disable: true } },
  render: () => ({
    components: { CadenceStatus },
    template: `
      <div class="story-column">
        <CadenceStatus tone="nominal" pulse>Nominal</CadenceStatus>
        <CadenceStatus tone="warning">Degraded</CadenceStatus>
        <CadenceStatus tone="danger">Unavailable</CadenceStatus>
        <CadenceStatus tone="neutral">Unknown</CadenceStatus>
      </div>
    `,
  }),
};
