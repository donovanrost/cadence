import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect, userEvent, within } from "storybook/test";
import CadenceTechnicalDetails from "./CadenceTechnicalDetails.vue";

const meta = {
  title: "Components/Presentation/Technical details",
  component: CadenceTechnicalDetails,
  args: {
    id: "technical-details",
    context: "Kestrel",
    items: [
      { label: "Spacecraft ID", value: "spacecraft_kestrel_01" },
      { label: "Runtime identity", value: "spacecraft_runtime:spacecraft_kestrel_01" },
      { label: "Content SHA-256", value: "0123456789abcdef".repeat(4) },
    ],
  },
} satisfies Meta<typeof CadenceTechnicalDetails>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Disclosure: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const summary = canvas.getByText("Technical details");
    await expect(summary.closest("details")).not.toHaveAttribute("open");
    summary.focus();
    await userEvent.click(summary);
    await expect(
      canvas.getByRole("button", { name: "Copy Spacecraft ID for Kestrel" }),
    ).toBeVisible();
    await userEvent.tab();
    await expect(
      canvas.getByRole("button", { name: "Copy Spacecraft ID for Kestrel" }),
    ).toHaveFocus();
    summary.focus();
    await userEvent.click(summary);
    await expect(summary.closest("details")).not.toHaveAttribute("open");
  },
};

export const MissingValue: Story = {
  args: { items: [{ label: "Runtime identity", value: null }] },
};
