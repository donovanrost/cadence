import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect, within } from "storybook/test";
import { ref } from "vue";
import HostPage from "../../host/src/shell/HostPage.vue";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceCard from "@cadence/ui/CadenceCard.vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceBadge from "@cadence/ui/CadenceBadge.vue";

const meta = {
  title: "Patterns/Page Composition",
  parameters: { layout: "fullscreen" },
} satisfies Meta;
export default meta;
type Story = StoryObj<typeof meta>;
const components = { HostPage, CadencePageHeading, CadenceCard, CadenceButton, CadenceBadge };

export const ProductionList: Story = {
  render: () => ({
    components,
    template: `
    <HostPage title="Spacecraft">
      <CadencePageHeading :breadcrumbs="[{ label: 'Artemis', href: '#mission' }, { label: 'Spacecraft' }]">
        <template #title>Spacecraft</template>
        <template #metadata>12 vehicles</template>
        <template #description>Configure vehicles, profiles, and flight readiness for this mission.</template>
        <template #actions><CadenceButton variant="primary">New spacecraft</CadenceButton></template>
      </CadencePageHeading>
      <CadenceCard><h2 class="text-base font-semibold">Vehicles</h2><p class="mt-2 text-sm text-muted">The content and heading share the same alignment and background across applications.</p></CadenceCard>
    </HostPage>`,
  }),
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getAllByRole("heading", { level: 1 })).toHaveLength(1);
    const header = within(canvasElement.querySelector("#host-page-heading")! as HTMLElement);
    await expect(header.getByRole("button", { name: "New spacecraft" })).toBeVisible();
    await expect(header.getByRole("navigation", { name: "Breadcrumb" })).toBeVisible();
  },
};
export const ProductionDetail: Story = {
  render: () => ({
    components,
    setup: () => ({ saved: ref(false) }),
    template: `
    <HostPage title="Spacecraft details">
      <CadencePageHeading :breadcrumbs="[{ label: 'Artemis', href: '#mission' }, { label: 'Spacecraft', href: '#spacecraft' }, { label: 'Lunar Pathfinder' }]">
        <template #title>Lunar Pathfinder</template>
        <template #metadata><CadenceBadge tone="success">Ready</CadenceBadge></template>
        <template #description>SC-104 · Lunar communications relay</template>
        <template #actions><CadenceButton :disabled="saved" variant="primary" @click="saved = true">{{ saved ? 'Saved' : 'Save changes' }}</CadenceButton></template>
      </CadencePageHeading>
      <CadenceCard><h2 class="text-base font-semibold">Configuration</h2><p v-if="saved" role="status" class="mt-2">Changes saved.</p></CadenceCard>
    </HostPage>`,
  }),
  play: async ({ canvas, userEvent }) => {
    await userEvent.click(canvas.getByRole("button", { name: "Save changes" }));
    await expect(canvas.getByRole("status")).toHaveTextContent("Changes saved.");
    await expect(canvas.getByRole("button", { name: "Saved" })).toBeDisabled();
  },
};
export const ProductionNarrow: Story = {
  render: () => ({
    components,
    template: `
    <div style="max-width: 390px">
    <HostPage title="New ground station">
      <CadencePageHeading :breadcrumbs="[{ label: 'Artemis', href: '#mission' }, { label: 'Ground stations', href: '#stations' }, { label: 'New station' }]">
        <template #title>Register a ground station for the Artemis mission</template>
        <template #description>Long titles wrap naturally while actions remain reachable on smaller screens.</template>
        <template #actions><CadenceButton variant="outline">Cancel</CadenceButton><CadenceButton variant="primary">Create station</CadenceButton></template>
      </CadencePageHeading>
      <CadenceCard><h2 class="text-base font-semibold">Station details</h2></CadenceCard>
    </HostPage></div>`,
  }),
};
export const ProductionLoading: Story = {
  render: () => ({
    components,
    template: `<HostPage title="Applications" :breadcrumbs="[{ label: 'Artemis', href: '#mission' }, { label: 'Applications' }]"><p role="status">Loading applications…</p></HostPage>`,
  }),
};
