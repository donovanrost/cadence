import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect } from "storybook/test";
import { ref } from "vue";
import CadenceDateTimeRangeField from "./CadenceDateTimeRangeField.vue";
import type { UtcRange } from "./date-time-range";

interface RangeFieldArgs {
  id: string;
  label: string;
  modelValue: UtcRange | null;
  max?: string;
}

const meta = {
  title: "Components/Forms/Date Time Range Field",
  component: CadenceDateTimeRangeField,
  args: {
    id: "pass-window",
    label: "Absolute range",
    modelValue: { start: "2026-10-08T10:00:00Z", end: "2026-10-08T12:30:00Z" },
    max: "2026-10-31T23:59:59Z",
  },
  render: (args) => ({
    components: { CadenceDateTimeRangeField },
    setup() {
      const value = ref(args.modelValue);
      return { args, value };
    },
    template: `<div class="story-column" style="max-width: 20rem"><CadenceDateTimeRangeField v-bind="args" v-model="value" /><output aria-label="Selected range">{{ value ? value.start + ' → ' + value.end : 'No range' }}</output></div>`,
  }),
  parameters: {
    docs: {
      description: {
        component:
          "Reka's range calendar and segmented date-time fields, in UTC. Picking days keeps the chosen times; typing edits exact seconds. The model is a pair of ISO UTC timestamps, emitted only once both ends exist.",
      },
    },
  },
} satisfies Meta<RangeFieldArgs>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Interactive: Story = {
  play: async ({ canvas }) => {
    await expect(canvas.getByRole("group", { name: "Absolute range" })).toBeVisible();
    await expect(canvas.getByLabelText("Selected range")).toHaveTextContent("2026-10-08T10:00:00Z");
  },
};
