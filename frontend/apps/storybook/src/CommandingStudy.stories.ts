import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect, userEvent, within } from "storybook/test";
import CommandingStudy from "./commanding-study/CommandingStudy.vue";

const meta = {
  title: "Design Studies/Commanding/Workspace",
  component: CommandingStudy,
  parameters: {
    layout: "fullscreen",
    docs: {
      description: {
        component:
          "Interactive design study using sample spacecraft and local draft state. No mission reads, command APIs, approvals, or real releases. Reka-backed Cadence splitters provide pane resizing; selection controls contextual disclosure.",
      },
    },
  },
} satisfies Meta<typeof CommandingStudy>;
export default meta;
type Story = StoryObj<typeof meta>;
export const Explore: Story = { args: { initial: "empty" } };
export const Prepare: Story = { args: { initial: "preparing" } };
export const Staged: Story = { args: { initial: "staged" } };
export const IncompatibleTargets: Story = { args: { initial: "incompatible" } };
export const ProgressiveWorkflow: Story = {
  args: { initial: "empty" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(
      canvas.queryByRole("heading", { name: "Prepare command" }),
    ).not.toBeInTheDocument();
    await userEvent.click(canvas.getByRole("button", { name: "Select KESTREL-01" }));
    await userEvent.click(canvas.getByRole("button", { name: "Select KESTREL-02" }));
    await userEvent.click(canvas.getByRole("button", { name: /SET_TLM_RATE/ }));
    await userEvent.click(canvas.getByRole("button", { name: "Adjust per spacecraft" }));
    await userEvent.selectOptions(
      canvas.getByRole("combobox", { name: "Packet interval for KESTREL-02" }),
      "10 s",
    );
    await userEvent.click(canvas.getByRole("button", { name: "Stage for 2 spacecraft" }));
    const table = within(canvas.getByRole("table", { name: "Staged commands" }));
    await expect(table.getByText("5 s", { exact: true })).toBeVisible();
    await expect(table.getByText("10 s", { exact: true })).toBeVisible();
    await userEvent.click(canvas.getByRole("button", { name: "30 s" }));
    await expect(table.queryByText("30 s", { exact: true })).not.toBeInTheDocument();
    await userEvent.click(canvas.getByRole("button", { name: "Review 2 commands" }));
    await expect(canvas.getByRole("button", { name: "Queue in simulation" })).toBeDisabled();
    await userEvent.click(canvas.getByLabelText("I reviewed these 2 target / command pairs."));
    await userEvent.click(canvas.getByRole("button", { name: "Queue in simulation" }));
    await userEvent.click(canvas.getByRole("button", { name: "Advance simulation" }));
    await expect(canvas.getAllByText("Awaiting verification", { exact: true })).toHaveLength(2);
    await userEvent.click(canvas.getByRole("button", { name: "Advance simulation" }));
    await expect(canvas.getAllByText("Verified", { exact: true })).toHaveLength(2);
  },
};
export const PartialCompatibility: Story = {
  args: { initial: "incompatible" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("button", { name: "Stage for 2 spacecraft" })).toBeDisabled();
    await userEvent.click(canvas.getByRole("button", { name: "Remove KESTREL-07 from selection" }));
    await expect(canvas.getByRole("button", { name: "Stage for 1 spacecraft" })).toBeEnabled();
  },
};
export const ResizeWithKeyboard: Story = {
  args: { initial: "preparing" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const handle = canvas.getByRole("separator", { name: "Resize spacecraft and command catalog" });
    const initial = handle.getAttribute("aria-valuenow");
    handle.focus();
    await userEvent.keyboard("{ArrowRight}");
    await expect(handle).not.toHaveAttribute("aria-valuenow", initial);
    await userEvent.click(canvas.getByRole("button", { name: "Stage for 3 spacecraft" }));
    await expect(
      canvas.getByRole("separator", { name: "Resize preparation and command shelf" }),
    ).toBeVisible();
    await expect(canvas.getByRole("heading", { name: "Prepare command" })).toBeVisible();
  },
};
export const ContextPreservesDrafts: Story = {
  args: { initial: "preparing" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("button", { name: "Adjust per spacecraft" }));
    await userEvent.selectOptions(
      canvas.getByRole("combobox", { name: "Packet interval for KESTREL-02" }),
      "10 s",
    );
    await userEvent.click(canvas.getByRole("button", { name: "Remove KESTREL-01 from selection" }));
    await userEvent.click(canvas.getByRole("button", { name: "Remove KESTREL-05 from selection" }));
    await expect(canvas.getByRole("button", { name: "10 s" })).toHaveAttribute(
      "aria-pressed",
      "true",
    );
    await userEvent.click(canvas.getByRole("button", { name: "Clear" }));
    await expect(canvas.getByRole("button", { name: "Stage for 0 spacecraft" })).toBeDisabled();
    await userEvent.click(canvas.getByRole("button", { name: "Select KESTREL-02" }));
    await expect(canvas.getByRole("button", { name: "10 s" })).toHaveAttribute(
      "aria-pressed",
      "true",
    );
    await userEvent.click(canvas.getByRole("button", { name: "30 s" }));
    await userEvent.click(canvas.getByRole("button", { name: "Stage for 1 spacecraft" }));
    await expect(
      within(canvas.getByRole("table", { name: "Staged commands" })).getByText("30 s"),
    ).toBeVisible();
  },
};
