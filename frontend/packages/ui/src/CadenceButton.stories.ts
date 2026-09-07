import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect } from "storybook/test";
import CadenceButton from "./CadenceButton.vue";

interface ButtonArgs {
  disabled: boolean;
  loading: boolean;
  size: "sm" | "md";
  type: "button" | "submit" | "reset";
  variant: "primary" | "secondary" | "quiet" | "danger";
}

const meta = {
  title: "Components/Actions/Button",
  component: CadenceButton,
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
    components: { CadenceButton },
    setup: () => ({ args }),
    template: '<CadenceButton v-bind="args">Command spacecraft</CadenceButton>',
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
    components: { CadenceButton },
    template: `
      <div class="story-column">
        <div class="story-row">
          <CadenceButton variant="primary">Primary</CadenceButton>
          <CadenceButton variant="secondary">Secondary</CadenceButton>
          <CadenceButton variant="quiet">Quiet</CadenceButton>
          <CadenceButton variant="danger">Danger</CadenceButton>
        </div>
        <div class="story-row">
          <CadenceButton size="sm">Small</CadenceButton>
          <CadenceButton disabled>Disabled</CadenceButton>
          <CadenceButton loading>Loading</CadenceButton>
        </div>
      </div>
    `,
  }),
};
