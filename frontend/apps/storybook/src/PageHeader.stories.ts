import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect, within } from "storybook/test";
import { defineComponent, h } from "vue";
import {
  useManagementHeader,
  useOpsHeader,
  type ManagementHeaderFor,
  type ManagementRoute,
  type OpsHeaderFor,
  type OpsRoute,
} from "@cadence/plugin-sdk/page-header";
import { href } from "@cadence/plugin-sdk/routes";
import HostPage from "../../host/src/shell/HostPage.vue";

/**
 * Every page header is drawn by the host from the route catalog plus the data a
 * page gives `useOpsHeader` or `useManagementHeader`. Pages cannot add markup,
 * so these are the only looks. Each layer keeps its own layout.
 */
const meta = {
  title: "Host/Page header",
  parameters: { layout: "fullscreen" },
} satisfies Meta;
export default meta;
type Story = StoryObj<typeof meta>;

const mission = { mission_id: "kestrel" };
const crumbs = [
  { label: "Flight Operations", href: "/" },
  { label: "Kestrel", href: "/missions/kestrel" },
];

function render(route: string, title: string, workspace: boolean, describe: () => void) {
  const PageBody = defineComponent(() => {
    describe();
    return () => h("p", { class: "text-sm text-base-content/70" }, "Page content");
  });
  return {
    render: () => ({
      components: { HostPage, PageBody },
      setup: () => ({ route, title, workspace, crumbs: [...crumbs, { label: title }] }),
      template: `<HostPage :title="title" :route="route" :breadcrumbs="crumbs" :workspace="workspace" section="Observe"><PageBody /></HostPage>`,
    }),
  };
}
const ops = <R extends OpsRoute>(route: R, title: string, header?: OpsHeaderFor<R>) =>
  render(route, title, true, () => {
    if (header) useOpsHeader(route, header);
  });
const management = <R extends ManagementRoute>(
  route: R,
  title: string,
  header?: ManagementHeaderFor<R>,
) =>
  render(route, title, false, () => {
    if (header) useManagementHeader(route, header);
  });

export const OpsCollection: Story = {
  ...ops("/missions/:mission_id/ops/alarms", "Alarms", {
    description: "Latest evaluated limit states across the mission.",
    facts: ["3 active", "1 critical"],
    actions: [
      {
        id: "definitions",
        label: "Limit definitions",
        href: href("/missions/:mission_id/ops/alarms", mission),
      },
    ],
    refresh: { run: () => {} },
  }),
  play: async ({ canvasElement }) => {
    const header = within(canvasElement).getByRole("banner");
    await expect(within(header).getByRole("heading", { level: 1 })).toHaveTextContent("Alarms");
    await expect(within(header).getByRole("button", { name: "Refresh" })).toBeVisible();
  },
};

export const OpsPrimaryMenu: Story = ops("/missions/:mission_id/ops/dashboards", "Dashboards", {
  description:
    "Telemetry workspaces shared across the mission. Stars and recently viewed are yours alone.",
  actions: [
    {
      id: "library",
      label: "Library",
      icon: "hero-rectangle-stack",
      href: href("/missions/:mission_id/ops/dashboards/library", mission),
    },
    {
      id: "playlists",
      label: "Playlists",
      icon: "hero-play",
      href: href("/missions/:mission_id/ops/dashboards/playlists", mission),
    },
  ],
  primary: {
    id: "new",
    label: "New",
    icon: "hero-plus",
    menu: [
      {
        id: "blank",
        label: "New dashboard",
        href: href("/missions/:mission_id/ops/dashboards/new", mission),
      },
      {
        id: "import",
        label: "Import",
        href: href("/missions/:mission_id/ops/dashboards/new", mission, { mode: "import" }),
      },
    ],
  },
});

export const OpsResource: Story = ops(
  "/missions/:mission_id/ops/dashboards/:dashboard_id/settings",
  "Dashboard Settings",
  {
    title: "Pass Overview",
    status: { tone: "warning", label: "Archived" },
    facts: ["Version 14"],
    actions: [
      {
        id: "open",
        label: "Open dashboard",
        icon: "hero-arrow-top-right-on-square",
        href: href("/missions/:mission_id/ops/dashboards/:dashboard_id", {
          ...mission,
          dashboard_id: "pass",
        }),
      },
    ],
    more: [{ id: "archive", label: "Restore", run: () => {} }],
  },
);

/** A page that says nothing still gets its route's title and breadcrumbs. */
export const OpsRouteDefault: Story = ops("/missions/:mission_id/ops/timeline", "Mission Timeline");

/** A record list: what the records are, how many, and how to add one. No refresh. */
export const ManagementCollection: Story = {
  ...management("/missions/:mission_id/comms/transports", "Comms Transports", {
    description: "Durable byte-moving capabilities for spacecraft traffic.",
    facts: ["3 configured"],
    primary: {
      id: "new",
      label: "New transport",
      icon: "hero-plus",
      href: href("/missions/:mission_id/comms/transports/new", mission),
    },
  }),
  play: async ({ canvasElement }) => {
    const header = within(canvasElement).getByRole("banner");
    await expect(within(header).queryByRole("button", { name: "Refresh" })).toBeNull();
  },
};

/** One record: its name and stable id; "back to the list" is the breadcrumb. */
export const ManagementRecord: Story = {
  ...management(
    "/missions/:mission_id/comms/ground-stations/:ground_station_id",
    "Ground Station",
    {
      title: "Svalbard SG-3",
      identifier: "gs_svalbard_sg3",
      status: { tone: "success", label: "Active" },
      primary: {
        id: "edit",
        label: "Edit station",
        icon: "hero-pencil-square",
        href: href("/missions/:mission_id/comms/ground-stations/:ground_station_id/edit", {
          ...mission,
          ground_station_id: "gs_svalbard_sg3",
        }),
      },
      more: [{ id: "archive", label: "Archive station", tone: "danger", run: () => {} }],
    },
  ),
  play: async ({ canvasElement }) => {
    const header = within(canvasElement).getByRole("banner");
    await expect(within(header).getByRole("heading", { level: 1 })).toHaveTextContent(
      "Svalbard SG-3",
    );
    await expect(within(header).getByText("gs_svalbard_sg3")).toBeVisible();
  },
};

/** A creation form takes its title from the route; the form is the page. */
export const ManagementForm: Story = management(
  "/missions/:mission_id/comms/transports/new",
  "New Transport",
  {
    description:
      "Describe a durable byte-moving capability. This setup does not mean a connection is currently open.",
  },
);
