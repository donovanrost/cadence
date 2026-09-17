import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect, fireEvent } from "storybook/test";
import { ref } from "vue";
import CadenceDateTimeField from "./CadenceDateTimeField.vue";

interface DateTimeFieldArgs {
  id: string;
  label: string;
  modelValue: string;
  error?: string;
}

const meta = {
  title: "Components/Forms/Date Time Field",
  component: CadenceDateTimeField,
  args: { id: "not-before", label: "Not before", modelValue: "" },
  render: (args) => ({
    components: { CadenceDateTimeField },
    setup() {
      const value = ref(args.modelValue);
      return { args, value };
    },
    template: `<div class="story-column"><CadenceDateTimeField v-bind="args" v-model="value" /><output aria-label="Selected UTC time">{{ value || 'No time restriction' }}</output></div>`,
  }),
  parameters: {
    docs: {
      description: {
        component:
          "A native calendar and time picker displaying UTC. The model uses an ISO UTC timestamp or an empty string. Existing microseconds survive date edits; native selection supports milliseconds. Min and max use the same UTC format. Handle invalid to invalidate a prepared action during incomplete edits.",
      },
    },
  },
} satisfies Meta<DateTimeFieldArgs>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Interactive: Story = {
  play: async ({ canvas }) => {
    const field = canvas.getByLabelText("Not before (UTC)");
    await fireEvent.input(field, { target: { value: "2027-01-15T13:45:12" } });
    await expect(canvas.getByRole("status", { name: "Selected UTC time" })).toHaveTextContent(
      "2027-01-15T13:45:12Z",
    );
    await fireEvent.input(field, { target: { value: "" } });
    await expect(canvas.getByRole("status", { name: "Selected UTC time" })).toHaveTextContent(
      "No time restriction",
    );
  },
};
export const PreciseTime: Story = { args: { modelValue: "2027-01-15T13:45:12.123456Z" } };
export const Invalid: Story = {
  args: { modelValue: "2027-01-15T13:45:12Z", error: "Choose a time within the available window." },
};
