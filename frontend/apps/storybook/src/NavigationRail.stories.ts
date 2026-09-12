import { required } from "../../../test-support/required";
import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect, waitFor } from "storybook/test";
import ApplicationShell from "../../host/src/shell/ApplicationShell.vue";

const meta = {
  title: "Patterns/Navigation Rail",
  parameters: { layout: "fullscreen" },
} satisfies Meta;
export default meta;
type Story = StoryObj<typeof meta>;

const context = {
  version: 1,
  user: { user_id: "operator", display_name: "Mission operator", email: "operator@example.test" },
  organization: { organization_id: "flight", display_name: "Flight Operations" },
  organizations: [],
  capabilities: ["organization_admin"],
  platform_admin: false,
  admin_mode: false,
  csrf_token: "storybook-csrf",
  nav_context: "mission",
  nav_item: "comms_transports",
  notifications: [],
  unread_count: 0,
  mission: { mission_id: "artemis", display_name: "Artemis", slug: "artemis" },
  ops_nav_item: "requirements",
  dashboard_navigation: { starred: [], recent: [] },
  dock_surfaces: [],
};

const renderShell =
  (variant = "mission_sidebar", overrides = {}) =>
  () => ({
    components: { ApplicationShell },
    setup: () => ({ context: { ...context, ...overrides }, variant }),
    template: `<div @submit.prevent @click="$event.target.closest('a') && $event.preventDefault()">
    <ApplicationShell :variant="variant" :context="context">
      <button type="button" class="btn btn-outline">Page content</button>
    </ApplicationShell>
  </div>`,
  });

async function expectIcons(root: Element) {
  const icons = root.querySelectorAll<HTMLElement>(
    'span[class*="hero-"]:not(.cd-side-nav-chevron)',
  );
  await expect(icons.length).toBeGreaterThan(0);
  for (const icon of icons) {
    await expect(getComputedStyle(icon).maskImage, icon.className).not.toBe("none");
    await expect(icon.getBoundingClientRect().width, icon.className).toBeGreaterThan(0);
  }
}

export const Mission: Story = {
  name: "Production mission navigation",
  render: renderShell(),
  play: async ({ canvas, canvasElement, userEvent }) => {
    const nav = canvas.getByRole("navigation", { name: "Primary navigation" });
    await expectIcons(nav);
    const group = canvas.getByRole("button", { name: "Comms" });
    const child = canvas.getByRole("link", { name: "Transports" });
    await expect(group).toHaveAttribute("aria-expanded", "true");
    await expect(child).toHaveAttribute("aria-current", "page");
    await expect(nav.querySelectorAll('[aria-current="page"]')).toHaveLength(1);
    await expect(getComputedStyle(group).backgroundColor).toBe("rgba(0, 0, 0, 0)");
    await expect(getComputedStyle(child).backgroundColor).not.toBe("rgba(0, 0, 0, 0)");
    await expect(
      required(child.querySelector("span")).getBoundingClientRect().left,
    ).toBeGreaterThan(required(group.querySelector(".sidebar-label")).getBoundingClientRect().left);
    await expect(
      Math.abs(child.getBoundingClientRect().right - group.getBoundingClientRect().right),
    ).toBeLessThan(2);
    await expect(
      Math.abs(group.getBoundingClientRect().width - nav.getBoundingClientRect().width),
    ).toBeLessThan(2);
    await userEvent.click(group);
    await waitFor(() =>
      expect(canvas.queryByRole("link", { name: "Transports" })).not.toBeInTheDocument(),
    );
    await userEvent.keyboard("{Enter}");
    await waitFor(() => expect(canvas.getByRole("link", { name: "Transports" })).toBeVisible());
    await expect(canvasElement.querySelector('[aria-current="page"]')).toBeVisible();
    await userEvent.click(canvas.getByRole("button", { name: "Page content" }));
  },
};

export const Collapsed: Story = {
  name: "Production collapsed mission rail",
  render: renderShell(),
  play: async ({ canvas, canvasElement, userEvent }) => {
    const rail = required(canvasElement.querySelector<HTMLElement>("[data-sidebar-collapsible]"));
    await userEvent.click(canvas.getByRole("button", { name: "Toggle sidebar" }));
    await userEvent.click(canvas.getByRole("button", { name: "Page content" }));
    await waitFor(() => expect(rail.getBoundingClientRect().width).toBe(56));
    const signOut = canvas.getByRole("button", { name: "Sign out" });
    const toggle = canvas.getByRole("button", { name: "Toggle sidebar" });
    await expect(signOut.getBoundingClientRect().bottom).toBeLessThanOrEqual(
      toggle.getBoundingClientRect().top,
    );
    await expect(canvas.queryByRole("link", { name: "Transports" })).not.toBeInTheDocument();
    await expectIcons(canvas.getByRole("navigation", { name: "Primary navigation" }));
    for (const chevron of rail.querySelectorAll<HTMLElement>(".cd-side-nav-chevron")) {
      await expect(chevron).not.toBeVisible();
    }
    for (const icon of rail.querySelectorAll<HTMLElement>(".cd-side-nav-icon")) {
      const bounds = icon.getBoundingClientRect();
      await expect(
        Math.abs(bounds.x + bounds.width / 2 - (rail.getBoundingClientRect().x + 28)),
      ).toBeLessThan(2);
    }
    // Tab from page content into the rail; keyboard focus must reveal its labels.
    await userEvent.tab();
    await waitFor(() => expect(rail.getBoundingClientRect().width).toBeGreaterThan(56));
    await userEvent.click(canvas.getByRole("button", { name: "Page content" }));
    await waitFor(() => expect(rail.getBoundingClientRect().width).toBe(56));
  },
};

export const Organization: Story = {
  name: "Production organization navigation",
  render: renderShell("sidebar", { nav_context: "organization", nav_item: "provider_accounts" }),
  play: async ({ canvas }) =>
    expectIcons(canvas.getByRole("navigation", { name: "Primary navigation" })),
};

export const Administration: Story = {
  name: "Production administration navigation",
  render: renderShell("sidebar", { nav_context: "admin", nav_item: "admin_runtime" }),
  play: async ({ canvas }) =>
    expectIcons(canvas.getByRole("navigation", { name: "Primary navigation" })),
};

export const Operations: Story = {
  name: "Production operations rail",
  render: renderShell("ops"),
  play: async ({ canvasElement, canvas, userEvent }) => {
    await userEvent.click(canvas.getByRole("button", { name: "Toggle navigation" }));
    await expectIcons(required(canvasElement.querySelector("#ops-nav-rail")));
  },
};
