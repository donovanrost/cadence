import type { Meta, StoryObj } from "@storybook/vue3-vite";
import CadenceSpinner from "./CadenceSpinner.vue";

interface SpinnerArgs {
  label?: string;
  size: "sm" | "md";
}

const meta = {
  title: "Components/Feedback/Spinner",
  component: CadenceSpinner,
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
    components: { CadenceSpinner },
    template: `
      <div class="story-row">
        <CadenceSpinner size="sm" label="Loading compact content" />
        <CadenceSpinner size="md" label="Loading content" />
      </div>
    `,
  }),
};
