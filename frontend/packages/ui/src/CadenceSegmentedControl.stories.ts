import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect, userEvent } from "storybook/test";
import { ref } from "vue";
import CadenceSegmentedControl from "./CadenceSegmentedControl.vue";

interface SegmentedArgs {
  label: string;
  modelValue: string;
  options: readonly { value: string; label: string; disabled?: boolean }[];
  disabled?: boolean;
  size?: "xs" | "sm";
}

const meta = {
  title: "Components/Controls/Segmented Control",
  component: CadenceSegmentedControl,
  args: {
    label: "Argument values",
    modelValue: "shared",
    size: "xs",
    options: [
      { label: "All spacecraft", value: "shared" },
      { label: "Per spacecraft", value: "individual" },
    ],
  },
  render: (args) => ({
    components: { CadenceSegmentedControl },
    setup() {
      const value = ref(args.modelValue);
      return { args, value };
    },
    template: `<div class="story-column"><CadenceSegmentedControl v-bind="args" v-model="value" /><output aria-label="Selected mode">{{ value }}</output></div>`,
  }),
  parameters: {
    docs: {
      description: {
        component:
          "A mutually exclusive mode selector with short labels. Native radios provide arrow-key navigation and preserve the current selection. Use the compact size in panel headers; the caller owns the meaning and persistence of each mode.",
      },
    },
  },
} satisfies Meta<SegmentedArgs>;
export default meta;
type Story = StoryObj<typeof meta>;

export const PanelModes: Story = {
  play: async ({ canvas }) => {
    await userEvent.click(canvas.getByRole("radio", { name: "All spacecraft" }));
    await userEvent.keyboard("{ArrowRight}");
    await expect(canvas.getByRole("radio", { name: "Per spacecraft" })).toBeChecked();
    await expect(canvas.getByRole("radio", { name: "Per spacecraft" })).toHaveFocus();
    await expect(canvas.getByRole("status", { name: "Selected mode" })).toHaveTextContent(
      "individual",
    );
    await userEvent.keyboard("{ArrowLeft}");
    await expect(canvas.getByRole("radio", { name: "All spacecraft" })).toBeChecked();
  },
};
export const ThreeModes: Story = {
  args: {
    label: "Display mode",
    size: "sm",
    modelValue: "list",
    options: [
      { label: "List", value: "list" },
      { label: "Map", value: "map", disabled: true },
      { label: "Timeline", value: "timeline" },
    ],
  },
  play: async ({ canvas }) => {
    await expect(canvas.getByRole("radio", { name: "Map" })).toBeDisabled();
    await userEvent.click(canvas.getByRole("radio", { name: "List" }));
    await userEvent.keyboard("{ArrowRight}");
    await expect(canvas.getByRole("radio", { name: "Timeline" })).toBeChecked();
  },
};
export const Disabled: Story = {
  args: { disabled: true },
  play: async ({ canvas }) => {
    for (const radio of canvas.getAllByRole("radio")) await expect(radio).toBeDisabled();
    await expect(canvas.getByRole("radio", { name: "All spacecraft" })).toBeChecked();
  },
};
