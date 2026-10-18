import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { ref } from "vue";
import { expect, userEvent, within } from "storybook/test";
import CadenceWorkspaceLayout from "./CadenceWorkspaceLayout.vue";
import CadencePane from "./CadencePane.vue";
import CadenceSelectionTile from "./CadenceSelectionTile.vue";
import CadenceButton from "./CadenceButton.vue";
import CadenceTextField from "./CadenceTextField.vue";

const meta = {
  title: "Patterns/Workspace/Resizable Workbench",
  component: CadenceWorkspaceLayout,
  parameters: { layout: "fullscreen" },
  args: {
    id: "workspace-story",
    storageId: "cadence-workspace-story-v1",
    inspector: false,
    dock: false,
  },
  render: (args: { id: string; storageId: string; inspector?: boolean; dock?: boolean }) => ({
    components: {
      CadenceWorkspaceLayout,
      CadencePane,
      CadenceSelectionTile,
      CadenceButton,
      CadenceTextField,
    },
    setup() {
      const selected = ref(false),
        inspector = ref(args.inspector),
        dock = ref(args.dock),
        filter = ref("");
      return { args, selected, inspector, dock, filter };
    },
    template: `<div style="height: 700px"><CadenceWorkspaceLayout v-bind="args" :inspector="inspector" v-model:dock="dock" dock-title="Activity" dock-expand-label="Expand activity">
      <template #toolbar><strong>Operational workspace</strong></template>
      <template #primary><CadencePane id="objects" title="Objects" icon="hero-cube" :count="1"><template #toolbar><p style="padding: 12px; font-size: 12px">Select an object to inspect it.</p></template><div style="padding: 12px"><CadenceSelectionTile :selected="selected" label="Select Processor A" @click="selected = !selected; inspector = selected"><template #title>Processor A</template><template #visual><span class="hero-cpu-chip" style="width: 48px; height: 48px" /></template>Command endpoint<template #footer>SCID 007</template></CadenceSelectionTile></div><template #footer>1 object</template></CadencePane></template>
      <template #secondary><CadencePane id="browser" title="Browser" icon="hero-magnifying-glass"><p style="padding: 16px; font-size: 12px">Keep context visible as selection changes.</p></CadencePane></template>
      <template #inspector><CadencePane id="inspector" title="Inspector" icon="hero-adjustments-horizontal"><p style="padding: 16px; font-size: 12px">Contextual details appear alongside the browser.</p></CadencePane></template>
      <template #dock><CadencePane id="dock" title="Activity" icon="hero-queue-list"><template #actions><CadenceButton size="xs" variant="quiet" @click="dock = false">Minimize activity</CadenceButton></template><div style="padding: 16px"><CadenceTextField id="activity-filter" v-model="filter" label="Activity filter" /></div></CadencePane></template>
      <template #status>Layout is saved locally. Arrow keys resize focused separators.</template>
    </CadenceWorkspaceLayout></div>`,
  }),
} satisfies Meta<typeof CadenceWorkspaceLayout>;
export default meta;
type Story = StoryObj<typeof meta>;
export const Browse: Story = {};
export const InspectorAndDock: Story = { args: { inspector: true, dock: true } };
export const ProgressiveDisclosure: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("button", { name: "Select Processor A" }));
    await expect(canvas.getByRole("heading", { name: "Inspector" })).toBeVisible();
    await expect(canvasElement.querySelector("#workspace-story-inspector")).toHaveAttribute(
      "data-panel-size",
      "36.0",
    );
    await expect(canvas.getByRole("heading", { name: "Objects 1" })).toBeVisible();
    const separator = canvas.getByRole("separator", { name: "Resize navigation and browser" });
    const initial = separator.getAttribute("aria-valuenow");
    separator.focus();
    await userEvent.keyboard("{ArrowRight}");
    await expect(separator).not.toHaveAttribute("aria-valuenow", initial);
    await userEvent.click(canvas.getByRole("button", { name: "Expand activity" }));
    await expect(canvas.getByRole("heading", { name: "Activity" })).toBeVisible();
    await expect(canvasElement.querySelector("#workspace-story-dock")).toHaveAttribute(
      "data-panel-size",
      "34.0",
    );
    const dockSeparator = canvas.getByRole("separator", { name: "Resize workspace and dock" });
    dockSeparator.focus();
    await userEvent.keyboard("{ArrowUp}");
    const expandedSize = dockSeparator.getAttribute("aria-valuenow");
    await userEvent.type(canvas.getByRole("textbox", { name: "Activity filter" }), "critical");
    await userEvent.click(canvas.getByRole("button", { name: "Minimize activity" }));
    await expect(canvas.getByRole("button", { name: "Expand activity" })).toHaveFocus();
    await expect(
      canvas.queryByRole("textbox", { name: "Activity filter" }),
    ).not.toBeInTheDocument();
    await userEvent.keyboard("{Enter}");
    await expect(canvas.getByRole("textbox", { name: "Activity filter" })).toHaveValue("critical");
    await expect(dockSeparator).toHaveAttribute("aria-valuenow", expandedSize);
    await expect(canvas.getByRole("button", { name: "Select Processor A" })).toHaveAttribute(
      "aria-pressed",
      "true",
    );
  },
};

export const DragToMinimize: Story = {
  args: { id: "workspace-snap", storageId: "cadence-workspace-snap-v1", dock: true },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const pointer = userEvent.setup();
    const handle = canvas.getByRole("separator", { name: "Resize workspace and dock" });
    const group = canvasElement.querySelector(
      '[data-panel-group][data-panel-group-id="workspace-snap-vertical"]',
    );
    if (!group) throw new Error("Workspace splitter is missing");
    const header = canvas.getByRole("heading", { name: "Activity" }).closest("header");
    if (!header) throw new Error("Dock header is missing");
    const headerBackground = getComputedStyle(header).backgroundColor;
    await userEvent.type(canvas.getByRole("textbox", { name: "Activity filter" }), "critical");
    await userEvent.click(canvas.getByRole("button", { name: "Minimize activity" }));
    const minimizedBackground = getComputedStyle(
      canvas.getByRole("button", { name: "Expand activity" }),
    ).backgroundColor;
    await userEvent.click(canvas.getByRole("button", { name: "Expand activity" }));
    const bounds = group.getBoundingClientRect();
    const start = handle.getBoundingClientRect();
    const x = start.x + start.width / 2;
    const startCoords = { clientX: x, clientY: start.y + start.height / 2 };
    const returnCoords = { clientX: x, clientY: startCoords.clientY - 20 };
    const minimumCoords = { clientX: x, clientY: bounds.bottom - bounds.height * 0.18 };
    const snapCoords = { clientX: x, clientY: bounds.bottom - bounds.height * 0.06 };
    await pointer.pointer({ target: handle, coords: startCoords, keys: "[MouseLeft>]" });
    // The separator must keep following the pointer on both sides of the threshold.
    for (const remaining of [0.2, 0.16, 0.12, 0.09, 0.06]) {
      const coords = { clientX: x, clientY: bounds.bottom - bounds.height * remaining };
      await pointer.pointer({ target: handle, coords });
      const moved = handle.getBoundingClientRect();
      await expect(Math.abs(moved.y + moved.height / 2 - coords.clientY)).toBeLessThan(4);
      if (remaining > 0.11)
        await expect(getComputedStyle(header).backgroundColor).toBe(headerBackground);
      else await expect(getComputedStyle(header).backgroundColor).not.toBe(headerBackground);
      await expect(
        canvas.queryByRole("button", { name: "Expand activity" }),
      ).not.toBeInTheDocument();
    }
    await expect(header).toBeVisible();
    await expect(getComputedStyle(header).backgroundColor).not.toBe(headerBackground);
    await expect(canvas.queryByRole("button", { name: "Expand activity" })).not.toBeInTheDocument();
    // Returning above the threshold cancels the preview while the mouse remains held.
    await pointer.pointer({ target: handle, coords: returnCoords });
    await expect(getComputedStyle(header).backgroundColor).toBe(headerBackground);
    await pointer.pointer({ target: handle, coords: returnCoords, keys: "[/MouseLeft]" });
    await expect(canvas.getByRole("textbox", { name: "Activity filter" })).toBeVisible();
    const expandedSize = handle.getAttribute("aria-valuenow");
    const resized = handle.getBoundingClientRect();
    const resizedCoords = { clientX: x, clientY: resized.y + resized.height / 2 };

    await pointer.pointer({ target: handle, coords: resizedCoords, keys: "[MouseLeft>]" });
    await pointer.pointer({ target: handle, coords: snapCoords });
    await pointer.pointer({ target: handle, coords: snapCoords, keys: "[/MouseLeft]" });
    await expect(canvas.getByRole("button", { name: "Expand activity" })).toHaveFocus();
    await expect(
      getComputedStyle(canvas.getByRole("button", { name: "Expand activity" })).backgroundColor,
    ).toBe(minimizedBackground);
    await userEvent.keyboard("{Enter}");
    await expect(getComputedStyle(header).backgroundColor).toBe(headerBackground);
    await expect(canvas.getByRole("textbox", { name: "Activity filter" })).toHaveValue("critical");
    await expect(handle).toHaveAttribute("aria-valuenow", expandedSize);
    await pointer.pointer({ target: handle, coords: minimumCoords });
    await expect(handle).toHaveAttribute("aria-valuenow", expandedSize);

    // Escape restores the pre-gesture height and releases Reka's active drag.
    await pointer.pointer({ target: handle, coords: resizedCoords, keys: "[MouseLeft>]" });
    await pointer.pointer({ target: handle, coords: snapCoords });
    await userEvent.keyboard("{Escape}");
    await expect(getComputedStyle(header).backgroundColor).toBe(headerBackground);
    await pointer.pointer({ target: handle, coords: minimumCoords });
    await pointer.pointer({ target: handle, coords: minimumCoords, keys: "[/MouseLeft]" });
    await expect(handle).toHaveAttribute("aria-valuenow", expandedSize);
    await expect(canvas.getByRole("textbox", { name: "Activity filter" })).toHaveValue("critical");
  },
};
