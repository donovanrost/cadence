import type { Meta, StoryObj } from "@storybook/vue3-vite";
import CButton from "./CButton.vue";
import CStatePanel from "./CStatePanel.vue";

interface StatePanelArgs {
  description: string;
  title: string;
  tone: "loading" | "error" | "neutral";
}

const meta = {
  title: "Components/Feedback/State Panel",
  component: CStatePanel,
  tags: ["generation-02"],
  args: {
    description: "The host is resolving the application release and its compatibility contract.",
    title: "Loading application",
    tone: "loading",
  },
  argTypes: {
    tone: { control: "inline-radio", options: ["loading", "error", "neutral"] },
  },
} satisfies Meta<StatePanelArgs>;

export default meta;
type Story = StoryObj<StatePanelArgs>;

export const Loading: Story = {};

export const ErrorWithAction: Story = {
  args: {
    description: "The approved release could not be loaded. The host shell remains available.",
    title: "Application unavailable",
    tone: "error",
  },
  render: (args) => ({
    components: { CButton, CStatePanel },
    setup: () => ({ args }),
    template: `
      <CStatePanel v-bind="args">
        <template #action><CButton size="sm">Retry release</CButton></template>
      </CStatePanel>
    `,
  }),
};
