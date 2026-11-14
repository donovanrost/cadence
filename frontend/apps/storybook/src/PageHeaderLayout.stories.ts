import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect, within } from "storybook/test";
// The browser runner virtualizes this module; a re-export loads a second context.
// oxlint-disable-next-line vite-plus/prefer-vite-plus-imports
import { page } from "@vitest/browser/context";
import { defineComponent, h } from "vue";
import { useOpsHeader } from "@cadence/plugin-sdk/page-header";
import { href } from "@cadence/plugin-sdk/routes";
import HostPage from "../../host/src/shell/HostPage.vue";
import { required } from "../../../test-support/required";

const meta = {
  title: "Host/Page header layout",
  parameters: { layout: "fullscreen" },
} satisfies Meta;
export default meta;
type Story = StoryObj<typeof meta>;

const mission = { mission_id: "sre-telemetry-exercise" };
const breadcrumbs = [
  { label: "SRE Observability Demo", href: "/" },
  { label: "SRE Telemetry Exercise", href: href("/missions/:mission_id", mission) },
  { label: "Mission Operations", href: href("/missions/:mission_id/ops", mission) },
  {
    label: "Fleet Planning",
    href: href("/missions/:mission_id/ops/planning", mission),
  },
  { label: "Plan Fleet Horizon" },
];

const CollectionBody = defineComponent(() => {
  useOpsHeader("/missions/:mission_id/ops/planning", {
    description: "Plan contact coverage across the fleet and review each planning run.",
    primary: {
      id: "plan-horizon",
      label: "Plan Horizon",
      href: href("/missions/:mission_id/ops/planning/new", mission),
    },
    refresh: { run: () => {} },
  });
  return () => h("p", "Fleet planning content");
});

const constrainedLayout: Story = {
  render: () => ({
    components: { HostPage },
    setup: () => ({ breadcrumbs }),
    // Reserve the widths of collapsed/expanded navigation and context rails.
    // At phone widths test the header itself; mobile shell behavior is separate.
    template: `
      <section id="header-container">
        <HostPage title="Plan Fleet Horizon" route="/missions/:mission_id/ops/planning/new" :breadcrumbs="breadcrumbs" workspace />
      </section>`,
  }),
  play: async ({ canvasElement }) => {
    try {
      for (const width of [1063, 1280, 390]) {
        await page.viewport(width, 779);
        for (const rails of [96, 272, 336, 512]) {
          required(canvasElement.querySelector<HTMLElement>("#header-container")).style.width =
            `min(100%, max(288px, calc(100vw - ${rails}px)))`;
          const header = required(canvasElement.querySelector<HTMLElement>(".cd-page-header"));
          const title = within(header).getByRole("heading", { level: 1 });
          const trail = within(header).getByRole("navigation", { name: "Breadcrumb" });
          const description = required(header.querySelector<HTMLElement>(".cd-page-description"));
          const bounds = header.getBoundingClientRect();
          const titleBounds = title.getBoundingClientRect();

          // Breadcrumbs cannot take the title's column or force horizontal overflow.
          await expect(trail.getBoundingClientRect().bottom).toBeLessThanOrEqual(titleBounds.top);
          await expect(titleBounds.height).toBeLessThanOrEqual(
            parseFloat(getComputedStyle(title).lineHeight) * 2,
          );
          await expect(description.getBoundingClientRect().width).toBeGreaterThanOrEqual(
            Math.min(240, bounds.width - 48),
          );
          await expect(header.scrollWidth).toBeLessThanOrEqual(header.clientWidth);
          for (const link of within(trail).getAllByRole("link")) {
            await expect(link.getBoundingClientRect().right).toBeLessThanOrEqual(bounds.right);
          }
          await expect(
            within(trail).getByRole("link", { name: "SRE Telemetry Exercise" }),
          ).toHaveAttribute("href", href("/missions/:mission_id", mission));

          const action = within(header).queryByRole("link", { name: "Plan Horizon" });
          if (action) {
            const actionBounds = action.getBoundingClientRect();
            const descriptionBounds = description.getBoundingClientRect();
            await expect(action).toBeVisible();
            await expect(actionBounds.right).toBeLessThanOrEqual(bounds.right);
            await expect(
              actionBounds.left >= descriptionBounds.right ||
                actionBounds.top >= descriptionBounds.bottom,
            ).toBe(true);
            if (width === 390) {
              await expect(actionBounds.top).toBeGreaterThanOrEqual(descriptionBounds.bottom);
            }
          }
        }
      }
    } finally {
      await page.viewport(1280, 1100);
    }
  },
};

export const ConstrainedWorkspace: Story = constrainedLayout;

export const ConstrainedActions: Story = {
  ...constrainedLayout,
  render: () => ({
    components: { HostPage, CollectionBody },
    setup: () => ({ breadcrumbs }),
    template: `<section id="header-container"><HostPage title="Fleet Planning" route="/missions/:mission_id/ops/planning" :breadcrumbs="breadcrumbs.slice(0, -1)" workspace><CollectionBody /></HostPage></section>`,
  }),
};
