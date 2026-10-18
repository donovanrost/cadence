import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect, userEvent } from "storybook/test";
import { ref } from "vue";
import CadenceChoiceField from "./CadenceChoiceField.vue";

interface ChoiceArgs {
  id: string;
  label: string;
  modelValue: string | null;
  options: { label: string; value: string }[];
  disabled?: boolean;
}
const meta = {
  title: "Components/Forms/Choice Field",
  component: CadenceChoiceField,
  args: {
    id: "heater",
    label: "Heater ID",
    modelValue: null,
    options: [
      { label: "1", value: "1" },
      { label: "2", value: "2" },
    ],
  },
  render: (args) => ({
    components: { CadenceChoiceField },
    setup() {
      const value = ref(args.modelValue);
      return { args, value };
    },
    template: `<div class="story-column" style="max-width: 300px"><CadenceChoiceField v-bind="args" v-model="value" /><output aria-label="Selected choice">{{ value ?? 'No selection' }}</output></div>`,
  }),
  parameters: {
    docs: {
      description: {
        component:
          "Single-choice buttons for up to six options, a native select for larger sets. Button choices wrap within narrow panels and use native radio keyboard behavior. Values are nonempty strings; null means no selection.",
      },
    },
  },
} satisfies Meta<ChoiceArgs>;
export default meta;
type Story = StoryObj<typeof meta>;

export const TwoChoices: Story = {
  play: async ({ canvas }) => {
    await expect(canvas.getByRole("radiogroup", { name: "Heater ID" })).toBeVisible();
    await userEvent.click(canvas.getByRole("radio", { name: "2" }));
    await expect(canvas.getByRole("radio", { name: "2" })).toBeChecked();
    await expect(canvas.getByRole("status", { name: "Selected choice" })).toHaveTextContent("2");
  },
};
export const SixChoices: Story = {
  args: {
    label: "Mode",
    options: ["Off", "Safe", "Standby", "Nominal", "Boost", "Test"].map((label, value) => ({
      label,
      value: String(value),
    })),
  },
  play: async ({ canvas }) => {
    await expect(canvas.getAllByRole("radio")).toHaveLength(6);
    await userEvent.click(canvas.getByRole("radio", { name: "Nominal" }));
    await expect(canvas.getByRole("status", { name: "Selected choice" })).toHaveTextContent("3");
  },
};
export const SevenChoices: Story = {
  args: {
    label: "Channel",
    options: Array.from({ length: 7 }, (_, i) => ({ label: `Channel ${i + 1}`, value: String(i) })),
  },
  play: async ({ canvas }) => {
    const select = canvas.getByRole("combobox", { name: "Channel" });
    await userEvent.selectOptions(select, "6");
    await expect(canvas.getByRole("status", { name: "Selected choice" })).toHaveTextContent("6");
  },
};
export const LongLabels: Story = {
  args: {
    label: "Pointing mode",
    modelValue: "2",
    options: ["Ground station tracking", "Sun pointing", "Inertial hold", "Nadir pointing"].map(
      (label, value) => ({ label, value: String(value) }),
    ),
  },
};
export const Disabled: Story = {
  args: { disabled: true, modelValue: "1" },
  play: async ({ canvas }) => {
    for (const radio of canvas.getAllByRole("radio")) await expect(radio).toBeDisabled();
  },
};
