import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect, userEvent, within } from "storybook/test";
import { settingsSections } from "../../host/src/settings/contributions";
import SettingsExample from "./SettingsExample.vue";
const meta = {
  title: "Host/Settings",
  component: SettingsExample,
  loaders: [
    async () => {
      await Promise.all(settingsSections.ids.map((id) => settingsSections.load(id)));
      return {};
    },
  ],
  parameters: {
    layout: "fullscreen",
    docs: {
      description: {
        component:
          "Production Settings screens and shared controls. This preview uses a simulated transport; the application persists settings in Phoenix.",
      },
    },
  },
} satisfies Meta<typeof SettingsExample>;
export default meta;
type Story = StoryObj<typeof meta>;
export const Organization: Story = { args: { scope: "organization" } };
export const Mission: Story = {
  args: { scope: "mission" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(await canvas.findByRole("radio", { name: /^One authorized operator/ }));
    await userEvent.click(canvas.getByRole("button", { name: "Save changes" }));
    await expect(canvas.getByText("Changes saved.")).toBeVisible();
    await expect(canvas.getByRole("navigation", { name: "Primary navigation" })).toBeVisible();
  },
};
export const RequiredByOrganization: Story = { args: { enforced: true } };
export const ViewOnly: Story = { args: { canEdit: false } };
export const Commanding: Story = {
  args: { section: "commanding.defaults" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const expanded = await canvas.findByRole("radio", { name: /^Expanded/ });
    await userEvent.click(expanded);
    await userEvent.keyboard("{ArrowDown}");
    await expect(canvas.getByRole("radio", { name: /^Minimized/ })).toBeChecked();
    await userEvent.click(canvas.getByRole("button", { name: "Save changes" }));
    await expect(canvas.getByText("Changes saved.")).toBeVisible();
  },
};
