import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect } from "storybook/test";
import { ref } from "vue";
import CadenceTextField from "./CadenceTextField.vue";

interface TextFieldArgs {
  error?: string;
  id: string;
  label: string;
  modelValue: string;
  placeholder?: string;
  type: "email" | "password" | "text";
}

const meta = {
  title: "Components/Forms/Text Field",
  component: CadenceTextField,
  args: {
    id: "storybook-email",
    label: "Administrator email",
    modelValue: "",
    placeholder: "admin@example.com",
    type: "email",
  },
  render: (args) => ({
    components: { CadenceTextField },
    setup() {
      const value = ref(args.modelValue);
      return { args, value };
    },
    template: `
      <div class="story-column">
        <CadenceTextField
          v-model="value"
          :id="args.id"
          :label="args.label"
          :placeholder="args.placeholder"
          :type="args.type"
        />
        <p class="story-state">{{ value || "No value" }}</p>
      </div>
    `,
  }),
} satisfies Meta<TextFieldArgs>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Interactive: Story = {
  play: async ({ canvas, userEvent }) => {
    const input = canvas.getByRole("textbox", { name: "Administrator email" });
    await userEvent.type(input, "admin@example.com");
    await expect(input).toHaveValue("admin@example.com");
  },
};

export const Invalid: Story = {
  args: { error: "The supplied email or password was rejected." },
};
