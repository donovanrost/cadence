import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect, userEvent, waitFor, within } from "storybook/test";
import { ref } from "vue";
import CadenceSheet from "./CadenceSheet.vue";
import CadenceButton from "./CadenceButton.vue";

const meta = {
  title: "Components/Sheet",
  component: CadenceSheet,
  args: { open: false, title: "Edit details" },
  render: (args: { open: boolean; title: string }) => ({
    components: { CadenceSheet, CadenceButton },
    setup() {
      const open = ref(args.open);
      const showOpener = ref(true);
      return { args, open, showOpener };
    },
    template: `<div>
      <CadenceButton v-if="showOpener" @click="open = true">Edit details</CadenceButton>
      <CadenceButton @click="showOpener = true">Restore opener</CadenceButton>
      <CadenceSheet v-bind="args" v-model:open="open">
        <p>The opener may disappear while this sheet is open.</p>
        <CadenceButton @click="showOpener = false">Remove opener</CadenceButton>
      </CadenceSheet>
    </div>`,
  }),
} satisfies Meta<typeof CadenceSheet>;
export default meta;
type Story = StoryObj<typeof meta>;

export const RemovedOpener: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const body = within(canvasElement.ownerDocument.body);
    await userEvent.click(canvas.getByRole("button", { name: "Edit details" }));
    const dialog = await body.findByRole("dialog", { name: "Edit details" });
    await userEvent.click(within(dialog).getByRole("button", { name: "Remove opener" }));
    await userEvent.keyboard("{Escape}");
    await waitFor(() => expect(dialog).not.toBeInTheDocument());
    // Closing with a detached opener still releases the page for keyboard and pointer use.
    await userEvent.click(canvas.getByRole("button", { name: "Restore opener" }));
    const opener = canvas.getByRole("button", { name: "Edit details" });
    await userEvent.click(opener);
    await userEvent.keyboard("{Escape}");
    await waitFor(() => expect(opener).toHaveFocus());
    await userEvent.keyboard("{Enter}");
    await waitFor(() => expect(body.getByRole("heading", { name: "Edit details" })).toHaveFocus());
  },
};
