import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect, userEvent, waitFor, within } from "storybook/test";
import DirectoryStudyShell from "./dashboard-directory-study/DirectoryStudyShell.vue";

const meta = {
  title: "Design Studies/Dashboards/Directory",
  component: DirectoryStudyShell,
  parameters: {
    layout: "fullscreen",
    docs: {
      description: {
        component:
          "A Grafana-style dashboard directory inside the production Cadence shell: one search box, a tag picker, Starred and Show archived filters, sort, and a table whose Name cell opens the dashboard. Tags in a row add themselves to the filter. Authors get New (dashboard or import) and a row menu with Duplicate, Settings & sharing and Archive or Restore. Compare the three placements of personal shortcuts with the Quick access control: none (pure Grafana), a links strip, or Starred and Recently viewed panels. Shortcuts hide while searching or filtering. Everything is in-memory and links report where they would go. No folders yet.",
      },
    },
  },
  argTypes: {
    quickAccess: {
      control: "inline-radio",
      options: ["none", "links", "panels", "refined", "tabbed", "rail", "tiles", "resume"],
    },
    presentation: { control: "inline-radio", options: ["list", "table"] },
    initial: {
      control: "select",
      options: ["established", "first-run", "viewer", "large", "archived"],
    },
  },
} satisfies Meta<typeof DirectoryStudyShell>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Chosen: Story = {
  args: { initial: "established", quickAccess: "refined", presentation: "list" },
  parameters: {
    docs: {
      description: {
        story:
          "The chosen direction: refined Starred and Recently viewed panels above a list. Each row is the name and description on one line, with tags, last update, star and actions on the right. Switch Presentation to table to compare.",
      },
    },
  },
};
export const ChosenWithTable: Story = {
  args: { initial: "established", quickAccess: "refined", presentation: "table" },
};
export const ShortcutLinks: Story = { args: { initial: "established", quickAccess: "links" } };
export const ShortcutPanels: Story = { args: { initial: "established", quickAccess: "panels" } };
const variation = (story: string) => ({ docs: { description: { story } } });
export const Panels1Refined: Story = {
  args: { initial: "established", quickAccess: "refined" },
  parameters: variation(
    "The original two panels made equal height, with descriptions, unstar in place, at most five rows and Show all for longer starred lists.",
  ),
};
export const Panels2Tabbed: Story = {
  args: { initial: "established", quickAccess: "tabbed" },
  parameters: variation(
    "One full-width panel, half the height. A tab switches between starred and recently viewed; rows flow into columns.",
  ),
};
export const Panels3SideRail: Story = {
  args: { initial: "established", quickAccess: "rail" },
  parameters: variation(
    "Shortcuts move to a column beside the list. The list starts at the top of the page, and the shortcuts stay visible while searching.",
  ),
};
export const Panels4StarredTiles: Story = {
  args: { initial: "established", quickAccess: "tiles" },
  parameters: variation(
    "Starred dashboards become navigation tiles with description, tags and last update; recently viewed stays a compact list beside them.",
  ),
};
export const Panels5Resume: Story = {
  args: { initial: "established", quickAccess: "resume" },
  parameters: variation(
    "Leads with the dashboard you used last and reopens it in the same time range and spacecraft. Starred and the rest of your recent dashboards sit beside it.",
  ),
};
export const PureGrafana: Story = { args: { initial: "established", quickAccess: "none" } };
export const FirstRun: Story = { args: { initial: "first-run", quickAccess: "refined" } };
export const ViewerOnly: Story = { args: { initial: "viewer", quickAccess: "refined" } };
export const ShowingArchived: Story = { args: { initial: "archived", quickAccess: "refined" } };
export const ManyDashboards: Story = { args: { initial: "large", quickAccess: "refined" } };

export const TeammateSaves: Story = {
  args: { initial: "established", quickAccess: "refined", teammateAfterMs: 2500 },
  parameters: {
    docs: {
      description: {
        story:
          "After 2.5 seconds a teammate creates “Conjunction Watch” and renames “Comms Health”. The list follows without a reload and briefly highlights both rows.",
      },
    },
  },
};

export const FilterByTagFromRow: Story = {
  args: { initial: "established", quickAccess: "refined" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const list = canvas.getByRole("list", { name: "Dashboards" });
    const [eps] = within(list).getAllByRole("button", { name: "eps" });
    if (eps) await userEvent.click(eps);
    await expect(canvas.getByRole("button", { name: /Clear filters/ })).toBeVisible();
    await expect(canvas.queryByRole("navigation", { name: "Your dashboards" })).toBeNull();
    await waitFor(() => expect(within(list).getAllByRole("listitem")).toHaveLength(2));
  },
};

export const ArchiveAndUndo: Story = {
  args: { initial: "established", quickAccess: "none" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("button", { name: "Actions for Thermal Margins" }));
    await userEvent.click(within(document.body).getByRole("menuitem", { name: "Archive" }));
    await expect(canvas.queryByRole("link", { name: "Thermal Margins" })).toBeNull();
    await userEvent.click(canvas.getByRole("button", { name: "Undo" }));
    await expect(canvas.getByRole("link", { name: "Thermal Margins" })).toBeVisible();
  },
};
