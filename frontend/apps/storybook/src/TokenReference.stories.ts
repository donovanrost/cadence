import type { Meta, StoryObj } from "@storybook/vue3-vite";
import TokenReference from "./TokenReference.vue";

const meta = {
  title: "Foundations/Design Tokens",
  component: TokenReference,
  tags: ["baseline"],
  parameters: {
    layout: "fullscreen",
    controls: { disable: true },
  },
} satisfies Meta<typeof TokenReference>;

export default meta;
type Story = StoryObj<typeof meta>;

export const CurrentTheme: Story = {};
