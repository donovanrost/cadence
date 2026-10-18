import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect, waitFor } from "storybook/test";
import { ref } from "vue";
import {
  CadenceBadge,
  CadenceButton,
  CadenceCard,
  CadenceField,
  CadenceListToolbarFrame,
  CadencePageHeading,
  CadencePopover,
  CadenceStatePanel,
  CadenceTableFrame,
} from "./index";
const meta = { title: "Patterns/Production", parameters: { layout: "padded" } } satisfies Meta;
export default meta;
type Story = StoryObj<typeof meta>;
export const DataTable: Story = {
  render: () => ({
    components: {
      CadenceCard,
      CadenceListToolbarFrame,
      CadenceTableFrame,
      CadenceBadge,
      CadenceButton,
    },
    template: `<CadenceCard body-class="overflow-x-auto"><CadenceListToolbarFrame><h2 class="hud-label">Spacecraft</h2><CadenceButton size="sm" variant="primary">Add spacecraft</CadenceButton></CadenceListToolbarFrame><CadenceTableFrame><caption class="sr-only">Spacecraft availability</caption><thead><tr><th scope="col">Spacecraft</th><th scope="col">Availability</th><th scope="col">Last contact</th></tr></thead><tbody><tr><td>Artemis relay</td><td><CadenceBadge tone="success">Online</CadenceBadge></td><td>2026-09-05 18:42 UTC</td></tr><tr><td>Pathfinder</td><td><CadenceBadge tone="warning">Standby</CadenceBadge></td><td>2026-09-05 18:20 UTC</td></tr></tbody></CadenceTableFrame></CadenceCard>`,
  }),
};
export const NativeForm: Story = {
  render: () => ({
    components: { CadenceCard, CadenceField, CadenceButton },
    setup: () => ({ saved: ref(false) }),
    template: `<CadenceCard><form id="native-form" @submit.prevent="saved = true"><CadenceField label="Display name" control-id="native-name"><input id="native-name" name="display_name" class="input w-full" required /></CadenceField><CadenceField label="Environment" control-id="native-environment"><select id="native-environment" name="environment" class="select w-full"><option>Simulation</option><option>Operations</option></select></CadenceField><CadenceField label="Notes" control-id="native-notes"><textarea id="native-notes" name="notes" class="textarea w-full"></textarea></CadenceField><CadenceButton type="submit" variant="primary">Save configuration</CadenceButton><p v-if="saved" role="status" class="mt-3 text-success">Configuration saved</p></form></CadenceCard>`,
  }),
  play: async ({ canvas, userEvent }) => {
    await userEvent.type(canvas.getByLabelText("Display name"), "Ground station");
    await userEvent.selectOptions(canvas.getByLabelText("Environment"), "Operations");
    await userEvent.click(canvas.getByRole("button", { name: "Save configuration" }));
    await expect(canvas.getByRole("status")).toHaveTextContent("Configuration saved");
  },
};
export const PageStates: Story = {
  render: () => ({
    components: { CadencePageHeading, CadenceStatePanel, CadenceButton },
    template: `<div class="space-y-4"><CadencePageHeading><template #title>Mission telemetry</template></CadencePageHeading><CadenceStatePanel title="Waiting for telemetry" description="The connection is established. No samples have arrived." tone="loading" /><CadenceStatePanel title="No matching packets" description="Change the filters to broaden the results." /><CadenceStatePanel title="Telemetry unavailable" description="The connection was interrupted." tone="error"><template #action><CadenceButton size="sm">Retry connection</CadenceButton></template></CadenceStatePanel></div>`,
  }),
};
export const Popover: Story = {
  render: () => ({
    components: { CadencePopover, CadenceButton },
    template: `<CadencePopover id="story-popover" identity="story-popover" class="cadence-overlay"><template #trigger><CadenceButton data-overlay-trigger variant="outline">Inspect connection</CadenceButton></template><template #content="{ open }"><section v-show="open" data-overlay-panel class="cadence-overlay-panel p-4" role="dialog" aria-label="Connection details"><h2 class="hud-label">Connection</h2><p class="mt-2 text-sm">Telemetry is live.</p></section></template></CadencePopover>`,
  }),
  play: async ({ canvas, userEvent }) => {
    await userEvent.click(canvas.getByRole("button", { name: "Inspect connection" }));
    await expect(canvas.getByRole("dialog", { name: "Inspect connection" })).toBeVisible();
    await userEvent.keyboard("{Escape}");
    await expect(canvas.getByRole("button", { name: "Inspect connection" })).toHaveFocus();
  },
};

export const ThemePropagation: Story = {
  render: () => ({
    components: { CadenceButton, CadenceField },
    template: `<div class="space-y-4"><CadenceButton variant="primary">Theme action</CadenceButton><CadenceField label="Theme field" control-id="theme-field"><input id="theme-field" class="input" /></CadenceField></div>`,
  }),
  play: async ({ canvas, userEvent }) => {
    const root = document.documentElement;
    const button = canvas.getByRole("button", { name: "Theme action" });
    const field = canvas.getByLabelText("Theme field");
    const previous = root.getAttribute("style");
    try {
      root.style.setProperty("--color-action", "rgb(140, 180, 220)");
      root.style.setProperty("--control-radius", "12px");
      await waitFor(() =>
        expect(getComputedStyle(button).backgroundColor).toBe("rgb(140, 180, 220)"),
      );
      await expect(getComputedStyle(button).borderRadius).toBe("12px");
      await expect(getComputedStyle(field).borderRadius).toBe("12px");
      await userEvent.click(button);
      await userEvent.tab();
      await expect(field).toHaveFocus();
    } finally {
      if (previous === null) root.removeAttribute("style");
      else root.setAttribute("style", previous);
    }
  },
};
