import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect } from "storybook/test";
import { ref } from "vue";
import CadenceCheckbox from "./CadenceCheckbox.vue";

interface CheckboxArgs {
  disabled: boolean;
  modelValue: boolean;
  presentation: "control" | "row";
}

const meta = {
  title: "Components/Forms/Checkbox",
  component: CadenceCheckbox,
  args: {
    disabled: false,
    modelValue: false,
    presentation: "control",
  },
  argTypes: {
    presentation: { control: "inline-radio", options: ["control", "row"] },
  },
  render: (args) => ({
    components: { CadenceCheckbox },
    setup() {
      const checked = ref(args.modelValue);
      return { args, checked };
    },
    template: `
      <div class="story-column">
        <CadenceCheckbox
          id="storybook-packet-checkbox"
          v-model="checked"
          :disabled="args.disabled"
          :presentation="args.presentation"
        >
          Include telemetry packet
        </CadenceCheckbox>
        <p class="story-state">{{ checked ? "Checked" : "Unchecked" }}</p>
      </div>
    `,
  }),
} satisfies Meta<CheckboxArgs>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Interactive: Story = {
  play: async ({ canvas, userEvent }) => {
    const checkbox = canvas.getByRole("checkbox", { name: "Include telemetry packet" });
    await expect(checkbox).not.toBeChecked();
    await userEvent.click(checkbox);
    await expect(checkbox).toBeChecked();
    await expect(canvas.getByText("Checked")).toBeVisible();
  },
};

export const Checked: Story = {
  args: { modelValue: true },
};

export const Disabled: Story = {
  args: { disabled: true },
};
