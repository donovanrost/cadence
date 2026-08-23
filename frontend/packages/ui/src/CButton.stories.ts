import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect } from "storybook/test";
import CButton from "./CButton.vue";

interface ButtonArgs {
  disabled: boolean;
  loading: boolean;
  size: "sm" | "md";
  type: "button" | "submit" | "reset";
  variant: "primary" | "secondary" | "quiet" | "danger";
}

const meta = {
  title: "Components/Actions/Button",
  component: CButton,
  tags: ["baseline"],
  args: {
    disabled: false,
    loading: false,
    size: "md",
    type: "button",
    variant: "secondary",
  },
  argTypes: {
    size: { control: "inline-radio", options: ["sm", "md"] },
    type: { control: "select", options: ["button", "submit", "reset"] },
    variant: {
      control: "select",
      options: ["primary", "secondary", "quiet", "danger"],
    },
  },
  render: (args) => ({
    components: { CButton },
    setup: () => ({ args }),
    template: '<CButton v-bind="args">Command spacecraft</CButton>',
  }),
} satisfies Meta<ButtonArgs>;

export default meta;
type Story = StoryObj<typeof meta>;

export const Playground: Story = {};

export const Primary: Story = {
  args: { variant: "primary" },
};

export const Danger: Story = {
  args: { variant: "danger" },
};

export const Disabled: Story = {
  args: { disabled: true },
};

export const Loading: Story = {
  args: { loading: true, variant: "primary" },
  play: async ({ canvas }) => {
    const button = canvas.getByRole("button", { name: "Command spacecraft" });
    await expect(button).toBeDisabled();
    await expect(button).toHaveAttribute("aria-busy", "true");
  },
};

export const VariantMatrix: Story = {
  parameters: { controls: { disable: true } },
  render: () => ({
    components: { CButton },
    template: `
      <div class="story-column">
        <div class="story-row">
          <CButton variant="primary">Primary</CButton>
          <CButton variant="secondary">Secondary</CButton>
          <CButton variant="quiet">Quiet</CButton>
          <CButton variant="danger">Danger</CButton>
        </div>
        <div class="story-row">
          <CButton size="sm">Small</CButton>
          <CButton disabled>Disabled</CButton>
          <CButton loading>Loading</CButton>
        </div>
      </div>
    `,
  }),
};
