import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect } from "storybook/test";
import { ref } from "vue";
import CTextField from "./CTextField.vue";

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
  component: CTextField,
  tags: ["generation-02"],
  args: {
    id: "storybook-email",
    label: "Administrator email",
    modelValue: "",
    placeholder: "admin@example.com",
    type: "email",
  },
  render: (args) => ({
    components: { CTextField },
    setup() {
      const value = ref(args.modelValue);
      return { args, value };
    },
    template: `
      <div class="story-column">
        <CTextField
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
