import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect, fn } from "storybook/test";
import { MissionNew } from "@cadence/plugin-host/missions";

const args = {
  page: {
    id: "mission-new-page",
    heading: "Create mission",
    breadcrumbs: [{ label: "Missions", href: null }],
  },
  form: {
    id: "mission-new-form",
    fields: {
      display_name: {
        id: "mission-display-name",
        name: "mission[display_name]",
        type: "text" as const,
        label: "Mission name",
        required: true,
        value: "",
      },
      slug: {
        id: "mission-slug",
        name: "mission[slug]",
        type: "text" as const,
        label: "Slug",
        required: true,
        value: "",
      },
    },
    actions: {
      submit: { id: "mission-save", label: "Create mission" },
      cancel: { id: "mission-cancel", label: "Cancel", href: "#" },
    },
  },
  onSave: fn(),
  onValidate: fn(),
};

const meta = {
  title: "Applications/Mission Catalog/New Mission",
  component: MissionNew,
  parameters: { layout: "fullscreen" },
  args,
} satisfies Meta<typeof args>;
export default meta;
type Story = StoryObj<typeof args>;
export const Production: Story = {};
export const Submit: Story = {
  play: async ({ canvas, userEvent, args }) => {
    await userEvent.type(canvas.getByLabelText("Mission name"), "Artemis relay");
    await userEvent.type(canvas.getByLabelText("Slug"), "artemis-relay");
    await userEvent.click(canvas.getByRole("button", { name: "Create mission" }));
    await expect(args.onSave).toHaveBeenCalledWith({
      mission: { display_name: "Artemis relay", slug: "artemis-relay" },
    });
  },
};
