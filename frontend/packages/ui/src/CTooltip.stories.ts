import type { Meta, StoryObj } from "@storybook/vue3-vite";
import CButton from "./CButton.vue";
import CTooltip from "./CTooltip.vue";

interface TooltipArgs {
  align: "start" | "center" | "end";
  content: string;
  side: "top" | "right" | "bottom" | "left";
}

const meta = {
  title: "Components/Overlays/Tooltip",
  component: CTooltip,
  tags: ["baseline"],
  args: {
    align: "center",
    content: "Current operator has application configuration authority.",
    side: "bottom",
  },
  argTypes: {
    align: { control: "inline-radio", options: ["start", "center", "end"] },
    side: { control: "select", options: ["top", "right", "bottom", "left"] },
  },
  render: (args) => ({
    components: { CButton, CTooltip },
    setup: () => ({ args }),
    template: `
      <CTooltip v-bind="args">
        <CButton variant="quiet">Inspect authority</CButton>
      </CTooltip>
    `,
  }),
} satisfies Meta<TooltipArgs>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Playground: Story = {};
