import type { Meta, StoryObj } from "@storybook/vue3-vite";
import CSpinner from "./CSpinner.vue";

interface SpinnerArgs {
  label?: string;
  size: "sm" | "md";
}

const meta = {
  title: "Components/Feedback/Spinner",
  component: CSpinner,
  tags: ["generation-02"],
  args: {
    label: "Loading telemetry",
    size: "md",
  },
  argTypes: {
    size: { control: "inline-radio", options: ["sm", "md"] },
  },
} satisfies Meta<SpinnerArgs>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Playground: Story = {};

export const Sizes: Story = {
  parameters: { controls: { disable: true } },
  render: () => ({
    components: { CSpinner },
    template: `
      <div class="story-row">
        <CSpinner size="sm" label="Loading compact content" />
        <CSpinner size="md" label="Loading content" />
      </div>
    `,
  }),
};
