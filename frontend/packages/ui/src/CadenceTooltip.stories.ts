import type { Meta, StoryObj } from "@storybook/vue3-vite";
import CadenceButton from "./CadenceButton.vue";
import CadenceTooltip from "./CadenceTooltip.vue";

interface TooltipArgs {
  align: "start" | "center" | "end";
  content: string;
  side: "top" | "right" | "bottom" | "left";
}

const meta = {
  title: "Components/Overlays/Tooltip",
  component: CadenceTooltip,
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
    components: { CadenceButton, CadenceTooltip },
    setup: () => ({ args }),
    template: `
      <CadenceTooltip v-bind="args">
        <CadenceButton variant="quiet">Inspect authority</CadenceButton>
      </CadenceTooltip>
    `,
  }),
} satisfies Meta<TooltipArgs>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Playground: Story = {};
