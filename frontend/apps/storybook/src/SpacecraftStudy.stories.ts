import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect, userEvent, within } from "storybook/test";
import SpacecraftStudyShell from "./spacecraft-study/SpacecraftStudyShell.vue";
import CatalogReferenceView from "./spacecraft-study/CatalogReference.vue";
import type { SpacecraftId } from "./spacecraft-study/fixtures";

const meta = {
  title: "Design Studies/Spacecraft/Configuration",
  component: SpacecraftStudyShell,
  parameters: {
    layout: "fullscreen",
    docs: {
      description: {
        component:
          "Spacecraft configuration inside the production Cadence shell. The host retains primary navigation, account controls and page chrome; the visual fleet selector opens from the spacecraft heading. Visit Catalog and return to test navigation continuity and draft preservation. KESTREL-01 and KESTREL-02 start on different revisions; KESTREL-03 starts unconfigured. All navigation, edits, saves, approvals and activations are in-memory simulation. Reload resets them. Isolated Reference retains the original composition for comparison.",
      },
    },
  },
} satisfies Meta<typeof SpacecraftStudyShell>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Explore: Story = { args: { initial: "established" } };
export const IsolatedReference: Story = {
  args: { navigation: "isolated" },
  parameters: {
    docs: {
      description: {
        story:
          "Original isolated composition retained for comparison. The default stories now use the production Cadence shell and a contextual spacecraft switcher.",
      },
    },
  },
};
export const FirstSpacecraft: Story = { args: { initial: "new" } };
export const UpgradeCatalog: Story = { args: { initial: "upgrade" } };
export const ReviewChanges: Story = { args: { initial: "review" } };
export const MissingPacketInput: Story = { args: { initial: "missing-input" } };
export const CatalogReference: Story = {
  render: () => ({ components: { CatalogReferenceView }, template: "<CatalogReferenceView />" }),
};

function sectionButton(canvasElement: HTMLElement, name: string) {
  const canvas = within(canvasElement);
  return within(canvas.getByRole("navigation", { name: "Spacecraft sections" })).getByRole(
    "button",
    { name },
  );
}

async function switchSpacecraft(canvasElement: HTMLElement, id: SpacecraftId) {
  const canvas = within(canvasElement);
  await userEvent.click(canvas.getByRole("button", { name: "Switch spacecraft" }));
  await userEvent.click(canvas.getByRole("button", { name: `Open ${id}` }));
}

async function expectFleetRevision(canvasElement: HTMLElement, id: SpacecraftId, revision: string) {
  const canvas = within(canvasElement);
  const trigger = canvas.getByRole("button", { name: "Switch spacecraft" });
  await userEvent.click(trigger);
  await expect(canvas.getByTestId(`sc-fleet-revision-${id}`)).toBeVisible();
  await expect(canvas.getByTestId(`sc-fleet-revision-${id}`)).toHaveTextContent(revision);
  await userEvent.keyboard("{Escape}");
  await expect(trigger).toHaveFocus();
}

export const FleetSwitcher: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("button", { name: "Switch spacecraft" }));
    await expect(canvas.getByRole("button", { name: "Open KESTREL-02" })).toHaveAttribute(
      "aria-pressed",
      "true",
    );
    await expect(
      within(canvas.getByRole("navigation", { name: "Primary navigation" })).getByRole("link", {
        name: "Spacecraft",
      }),
    ).toHaveAttribute("aria-current", "page");
  },
};

export const NavigationContinuity: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const primaryNavigation = canvas.getByRole("navigation", { name: "Primary navigation" });
    const sidebarToggle = canvas.getByRole("button", { name: "Toggle sidebar" });
    await userEvent.click(sidebarToggle);
    await expect(sidebarToggle).toHaveAttribute("aria-expanded", "false");
    await userEvent.click(canvas.getByRole("button", { name: "Browse revisions" }));
    await userEvent.click(canvas.getByRole("button", { name: "Use r3.4 in draft" }));
    await userEvent.click(within(primaryNavigation).getByRole("link", { name: "Catalog" }));
    await expect(canvas.getByRole("heading", { level: 1, name: "Catalog" })).toBeVisible();
    await expect(sidebarToggle).toHaveAttribute("aria-expanded", "false");
    await expect(canvas.getByRole("navigation", { name: "Primary navigation" })).toBe(
      primaryNavigation,
    );
    await expect(within(primaryNavigation).getByRole("link", { name: "Catalog" })).toHaveAttribute(
      "aria-current",
      "page",
    );
    const usage = canvas.getByRole("table", {
      name: "Active and draft catalog revisions in this sample mission",
    });
    await expect(within(usage).getByRole("row", { name: /KESTREL-02/ })).toHaveTextContent(
      "r3.3r3.4",
    );
    await userEvent.click(canvas.getByRole("link", { name: "Return to KESTREL-02" }));
    await expect(canvas.getByRole("heading", { level: 1, name: "KESTREL-02" })).toBeVisible();
    await expect(canvas.getByRole("button", { name: "Save draft" })).toBeVisible();
    await expect(sidebarToggle).toHaveAttribute("aria-expanded", "false");
    await expect(canvas.getByRole("navigation", { name: "Primary navigation" })).toBe(
      primaryNavigation,
    );
    await expect(
      within(primaryNavigation).getByRole("link", { name: "Spacecraft" }),
    ).toHaveAttribute("aria-current", "page");
    await expectFleetRevision(canvasElement, "KESTREL-02", "r3.3");
  },
};

export const FirstSetupJourney: Story = {
  args: { initial: "new" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("button", { name: "Open in Ops" })).toBeDisabled();
    await userEvent.click(sectionButton(canvasElement, "Catalog & applications"));
    await userEvent.click(canvas.getByRole("button", { name: "Choose catalog" }));
    await expect(canvas.getByRole("heading", { name: "Choose catalog revision" })).toHaveFocus();
    await userEvent.click(canvas.getByRole("button", { name: "Use r3.4 in draft" }));
    await userEvent.click(canvas.getByRole("button", { name: "Configure Telemetry Decom" }));
    await userEvent.click(canvas.getByRole("checkbox", { name: "Enable Telemetry Decom" }));
    await expect(canvas.getByRole("radio", { name: /Payload downlink/ })).toBeDisabled();
    await userEvent.click(canvas.getByRole("radio", { name: "OBC downlink VC 0" }));
    await userEvent.click(canvas.getByRole("button", { name: "Done" }));
    await userEvent.click(canvas.getByRole("button", { name: "Configure Commanding" }));
    await userEvent.click(canvas.getByRole("checkbox", { name: "Enable Commanding" }));
    await userEvent.click(canvas.getByRole("button", { name: "Done" }));
    await userEvent.click(sectionButton(canvasElement, "Communications"));
    await userEvent.click(canvas.getByRole("button", { name: "Use Kestrel bus preset" }));
    await userEvent.click(canvas.getByRole("button", { name: "Connect path" }));
    await userEvent.click(canvas.getByRole("button", { name: "Save draft" }));
    await expect(canvas.getByRole("button", { name: "Open in Ops" })).toBeDisabled();
    await userEvent.click(sectionButton(canvasElement, "Changes"));
    await expect(canvas.getByRole("button", { name: "Submit for review" })).toBeEnabled();
    await expect(
      canvas.queryByRole("button", { name: "Activate configuration" }),
    ).not.toBeInTheDocument();
    await userEvent.click(canvas.getByRole("button", { name: "Submit for review" }));
    await userEvent.click(canvas.getByRole("button", { name: "Simulate approval" }));
    await userEvent.click(canvas.getByRole("button", { name: "Activate configuration" }));
    await expectFleetRevision(canvasElement, "KESTREL-02", "r3.3");
    await userEvent.click(canvas.getByRole("button", { name: "Open in Ops" }));
    await expect(canvas.getByTestId("sc-ops-binding")).toHaveTextContent("Active Kestrel FSW r3.4");
    await expect(canvas.getByRole("button", { name: /CAPTURE_IMAGE/ })).toBeVisible();
  },
};

export const IndependentRevisionJourney: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("button", { name: "Open in Ops" }));
    await expect(canvas.getByTestId("sc-ops-binding")).toHaveTextContent(
      "r3.3 · 18 command definitions",
    );
    await expect(canvas.queryByRole("button", { name: /CAPTURE_IMAGE/ })).not.toBeInTheDocument();
    await switchSpacecraft(canvasElement, "KESTREL-01");
    await expect(canvas.getByTestId("sc-ops-binding")).toHaveTextContent(
      "r3.4 · 19 command definitions",
    );
    await expect(canvas.getByRole("button", { name: /CAPTURE_IMAGE/ })).toBeVisible();
    await switchSpacecraft(canvasElement, "KESTREL-02");
    await userEvent.click(canvas.getByRole("button", { name: "Back to spacecraft" }));
    await userEvent.click(canvas.getByRole("button", { name: "Browse revisions" }));
    await userEvent.click(canvas.getByRole("button", { name: "Use r3.4 in draft" }));
    await userEvent.click(canvas.getByRole("button", { name: "Open in Ops" }));
    await expect(canvas.getByTestId("sc-ops-binding")).toHaveTextContent(
      "r3.3 · 18 command definitions",
    );
    await expect(canvas.queryByRole("button", { name: /CAPTURE_IMAGE/ })).not.toBeInTheDocument();
    await userEvent.click(canvas.getByRole("button", { name: "Back to spacecraft" }));
    await userEvent.click(canvas.getByRole("button", { name: "Save draft" }));
    await userEvent.click(sectionButton(canvasElement, "Changes"));
    await userEvent.click(canvas.getByRole("button", { name: "Submit for review" }));
    await userEvent.click(canvas.getByRole("button", { name: "Simulate approval" }));
    await userEvent.click(canvas.getByRole("button", { name: "Activate configuration" }));
    await userEvent.click(canvas.getByRole("button", { name: "Open in Ops" }));
    await expect(canvas.getByTestId("sc-ops-binding")).toHaveTextContent(
      "r3.4 · 19 command definitions",
    );
    await expect(canvas.getByRole("button", { name: /CAPTURE_IMAGE/ })).toBeVisible();
    await expectFleetRevision(canvasElement, "KESTREL-01", "r3.4");
  },
};

export const RepairInputJourney: Story = {
  args: { initial: "missing-input" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("button", { name: "Submit for review" })).toBeDisabled();
    await userEvent.click(canvas.getByRole("button", { name: "Connect input" }));
    await userEvent.click(canvas.getByRole("radio", { name: "OBC downlink VC 0" }));
    await userEvent.click(canvas.getByRole("button", { name: "Done" }));
    await userEvent.click(canvas.getByRole("button", { name: "Save draft" }));
    await userEvent.click(sectionButton(canvasElement, "Changes"));
    await expect(canvas.queryByRole("button", { name: "Connect input" })).not.toBeInTheDocument();
    await expect(canvas.getByRole("button", { name: "Submit for review" })).toBeEnabled();
    await expectFleetRevision(canvasElement, "KESTREL-02", "r3.3");
  },
};

export const EditsInvalidateReview: Story = {
  args: { initial: "review" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("button", { name: "Submit for review" }));
    await userEvent.click(canvas.getByRole("button", { name: "Simulate approval" }));
    await expect(canvas.getByRole("button", { name: "Activate configuration" })).toBeEnabled();
    await userEvent.click(sectionButton(canvasElement, "Catalog & applications"));
    await userEvent.click(canvas.getByRole("button", { name: "Configure Telemetry Decom" }));
    await userEvent.click(canvas.getByRole("button", { name: "Disconnect packet input" }));
    await userEvent.click(canvas.getByRole("button", { name: "Done" }));
    await userEvent.click(sectionButton(canvasElement, "Changes"));
    await expect(
      canvas.queryByRole("button", { name: "Activate configuration" }),
    ).not.toBeInTheDocument();
    await expect(canvas.getByRole("button", { name: "Submit for review" })).toBeDisabled();
    await userEvent.click(canvas.getByRole("button", { name: "Discard unsaved" }));
    await expect(canvas.getByRole("button", { name: "Submit for review" })).toBeEnabled();
    await expect(
      canvas.queryByRole("button", { name: "Activate configuration" }),
    ).not.toBeInTheDocument();
  },
};

export const PreserveDraftAndKeyboardContext: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(sectionButton(canvasElement, "Catalog & applications"));
    const trigger = canvas.getByRole("button", { name: "Change revision" });
    await userEvent.click(trigger);
    await expect(canvas.getByRole("heading", { name: "Choose catalog revision" })).toHaveFocus();
    await userEvent.type(canvas.getByRole("searchbox", { name: "Find imported catalogs" }), "3.4");
    await expect(
      canvas.queryByRole("radio", { name: "Kestrel FSW revision 3.3" }),
    ).not.toBeInTheDocument();
    await userEvent.keyboard("{Escape}");
    await expect(trigger).toHaveFocus();
    await userEvent.keyboard("{Enter}");
    await userEvent.click(canvas.getByRole("button", { name: "Use r3.4 in draft" }));
    await switchSpacecraft(canvasElement, "KESTREL-01");
    await expect(canvas.queryByRole("button", { name: "Save draft" })).not.toBeInTheDocument();
    await switchSpacecraft(canvasElement, "KESTREL-02");
    await expect(canvas.getByRole("button", { name: "Save draft" })).toBeVisible();
    await userEvent.click(sectionButton(canvasElement, "Communications"));
    await userEvent.click(sectionButton(canvasElement, "Catalog & applications"));
    await expect(canvas.getByText("Draft binding · active r3.3")).toBeVisible();
    await expectFleetRevision(canvasElement, "KESTREL-02", "r3.3");
  },
};
