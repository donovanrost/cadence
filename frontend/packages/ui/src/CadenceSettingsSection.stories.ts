import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { ref } from "vue";
import { expect, userEvent, within } from "storybook/test";
import CadenceSettingsSection from "./CadenceSettingsSection.vue";
import CadenceSettingRow from "./CadenceSettingRow.vue";
import CadenceCheckbox from "./CadenceCheckbox.vue";
import CadenceButton from "./CadenceButton.vue";
const meta = {
  title: "Components/Forms/Settings section",
  component: CadenceSettingsSection,
  args: { title: "Display" },
  render: (args) => ({
    components: { CadenceSettingsSection, CadenceSettingRow, CadenceCheckbox, CadenceButton },
    setup() {
      return { args, enabled: ref(false), locked: ref(false) };
    },
    template: `<div style="width: min(680px, 85vw)"><h2 class="mb-4">Workspace settings</h2><CadenceSettingsSection v-bind="args" description="A shared section and row with caller-owned controls."><CadenceSettingRow label="Compact density" description="Fit more items in the workspace."><template #source>Inherited from organization</template><CadenceCheckbox id="density-control" v-model="enabled" :disabled="locked">Use compact density</CadenceCheckbox></CadenceSettingRow><template #footer><span role="status">{{ enabled ? 'Compact' : 'Comfortable' }}</span><CadenceButton size="sm" @click="locked = !locked">{{ locked ? 'Enable editing' : 'Make read only' }}</CadenceButton></template></CadenceSettingsSection></div>`,
  }),
} satisfies Meta<typeof CadenceSettingsSection>;
export default meta;
type Story = StoryObj<typeof meta>;
export const EditableAndReadOnly: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const group = canvas.getByRole("group", { name: "Compact density" });
    const checkbox = within(group).getByRole("checkbox", { name: "Use compact density" });
    checkbox.focus();
    await userEvent.keyboard(" ");
    await expect(checkbox).toBeChecked();
    await expect(canvas.getByRole("status")).toHaveTextContent("Compact");
    await userEvent.click(canvas.getByRole("button", { name: "Make read only" }));
    await expect(checkbox).toBeDisabled();
    await expect(checkbox).toBeChecked();
  },
};
