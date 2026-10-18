import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect, userEvent, within } from "storybook/test";
import SettingsStudyShell from "./settings-study/SettingsStudyShell.vue";

const meta = {
  title: "Design Studies/Settings/Organization and mission",
  component: SettingsStudyShell,
  parameters: {
    layout: "fullscreen",
    docs: {
      description: {
        component:
          "Organization and mission settings in the production Cadence shell. Explore defaults, overrides, enforced requirements, separate permissions, application contributions and both activation journeys. All settings, navigation, people and activations are simulated in memory. No live settings or spacecraft are changed. The SDK supplies discovery metadata; production server admission and persistence are a separate integration.",
      },
    },
  },
} satisfies Meta<typeof SettingsStudyShell>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Explore: Story = { args: { initial: "inherited" } };
export const OrganizationDefaults: Story = {
  args: { initial: "organization" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const navigation = canvas.getByRole("navigation", { name: "Primary navigation" });
    await expect(within(navigation).getByRole("link", { name: "Home" })).toBeVisible();
    await expect(canvas.getByRole("navigation", { name: "Scope settings" })).toBeVisible();
    await expect(canvas.queryByText("Navigation unavailable")).not.toBeInTheDocument();
  },
};
export const SingleOperator: Story = { args: { initial: "single-operator" } };
export const MissionOverride: Story = { args: { initial: "overridden" } };
export const EnforcedRequirement: Story = { args: { initial: "enforced" } };
export const ViewOnly: Story = { args: { initial: "read-only" } };
export const ApplicationUnavailable: Story = { args: { initial: "application-unavailable" } };

function scopeLink(canvasElement: HTMLElement, name: string) {
  return within(
    within(canvasElement).getByRole("navigation", { name: "Settings scope" }),
  ).getByRole("link", { name: new RegExp(`^${name}(?: Unsaved changes)?$`) });
}
function sectionLink(canvasElement: HTMLElement, name: string) {
  return within(
    within(canvasElement).getByRole("navigation", { name: "Settings sections" }),
  ).getByRole("link", { name: new RegExp(`^${name}(?: Unsaved changes)?$`) });
}

export const DefaultsAndOverridesJourney: Story = {
  args: { initial: "organization" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("radio", { name: /^Independent approval/ }));
    await userEvent.click(scopeLink(canvasElement, "Kestrel"));
    await expect(canvas.getByRole("radio", { name: /^One authorized operator/ })).toBeChecked();
    await userEvent.click(canvas.getByRole("link", { name: "View organization setting" }));
    await expect(canvas.getByRole("button", { name: "Save changes" })).toBeEnabled();
    await userEvent.click(canvas.getByRole("button", { name: "Save changes" }));
    await userEvent.click(scopeLink(canvasElement, "Kestrel"));
    await expect(canvas.getByTestId("settings-source")).toHaveAttribute("data-source", "inherited");
    await expect(canvas.getByRole("radio", { name: /^Independent approval/ })).toBeChecked();
    await userEvent.click(canvas.getByRole("radio", { name: /^One authorized operator/ }));
    await userEvent.click(canvas.getByRole("button", { name: "Save changes" }));
    await expect(canvas.getByTestId("settings-source")).toHaveAttribute(
      "data-source",
      "overridden",
    );
    await userEvent.click(canvas.getByRole("button", { name: "Use organization default" }));
    await expect(canvas.getByRole("radio", { name: /^Independent approval/ })).toBeChecked();
    await userEvent.click(canvas.getByRole("button", { name: "Discard" }));
    await expect(canvas.getByRole("radio", { name: /^One authorized operator/ })).toBeChecked();
    await userEvent.click(canvas.getByRole("button", { name: "Use organization default" }));
    await userEvent.click(canvas.getByRole("button", { name: "Save changes" }));
    await expect(canvas.getByTestId("settings-source")).toHaveAttribute("data-source", "inherited");
  },
};

export const OrganizationEnforcementJourney: Story = {
  args: { initial: "overridden" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("link", { name: "View organization setting" }));
    await userEvent.click(
      canvas.getByRole("checkbox", { name: "Allow missions to override this requirement" }),
    );
    await userEvent.click(canvas.getByRole("button", { name: "Save changes" }));
    await userEvent.click(scopeLink(canvasElement, "Kestrel"));
    await expect(canvas.getByTestId("settings-source")).toHaveAttribute("data-source", "enforced");
    await expect(canvas.getByRole("radio", { name: /^Independent approval/ })).toBeChecked();
    await expect(canvas.getByRole("radio", { name: /^One authorized operator/ })).toBeDisabled();
    await expect(
      canvas.queryByRole("button", { name: "Use organization default" }),
    ).not.toBeInTheDocument();
    await userEvent.click(sectionLink(canvasElement, "Commanding"));
    await expect(canvas.getByRole("radio", { name: /^Minimized/ })).toBeEnabled();
    await userEvent.click(canvas.getByRole("radio", { name: /^Minimized/ }));
    await userEvent.click(canvas.getByRole("button", { name: "Save changes" }));
  },
};

export const SingleOperatorActivation: Story = {
  args: { initial: "single-operator" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("link", { name: "Explore activation journey" }));
    await expect(
      canvas.queryByRole("button", { name: "Submit for review" }),
    ).not.toBeInTheDocument();
    await userEvent.click(canvas.getByRole("button", { name: "Activate configuration" }));
    await expect(canvas.getByRole("heading", { name: "Configuration activated" })).toBeVisible();
    await expect(canvas.getByText(/Maya Chen reviewed and activated/)).toBeVisible();
  },
};

export const IndependentApprovalJourney: Story = {
  args: { initial: "inherited" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("link", { name: "Explore activation journey" }));
    await userEvent.click(canvas.getByRole("button", { name: "Submit for review" }));
    await expect(canvas.getByText("Waiting for another reviewer")).toBeVisible();
    await expect(
      canvas.queryByRole("button", { name: "Approve and activate" }),
    ).not.toBeInTheDocument();
    await userEvent.click(canvas.getByText("Study controls · Acting as Maya Chen"));
    await userEvent.click(canvas.getByRole("button", { name: "Act as Eli Navarro" }));
    await expect(canvas.getByRole("button", { name: "Approve and activate" })).toBeDisabled();
    await userEvent.type(
      canvas.getByRole("textbox", { name: "Decision rationale" }),
      "Verified catalog, command compatibility, and replay evidence.",
    );
    await userEvent.click(canvas.getByRole("button", { name: "Approve and activate" }));
    await expect(canvas.getByRole("heading", { name: "Configuration activated" })).toBeVisible();
    await expect(canvas.getByText(/Eli Navarro approved and activated/)).toBeVisible();
  },
};

export const PolicyChangesInvalidatePendingReview: Story = {
  args: { initial: "inherited" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(canvas.getByRole("link", { name: "Explore activation journey" }));
    await userEvent.click(canvas.getByRole("button", { name: "Submit for review" }));
    await userEvent.click(canvas.getByRole("link", { name: "View approval setting" }));
    await userEvent.click(canvas.getByRole("radio", { name: /^One authorized operator/ }));
    await userEvent.click(canvas.getByRole("button", { name: "Save changes" }));
    await userEvent.click(canvas.getByRole("link", { name: "Explore activation journey" }));
    await expect(canvas.getByRole("heading", { name: "Approval settings changed" })).toBeVisible();
    await expect(
      canvas.queryByRole("heading", { name: "Configuration activated" }),
    ).not.toBeInTheDocument();
    await userEvent.click(canvas.getByRole("button", { name: "Activate configuration" }));
    await expect(canvas.getByRole("heading", { name: "Configuration activated" })).toBeVisible();
  },
};

export const ContributionsAndNavigation: Story = {
  args: { initial: "inherited" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const primaryNavigation = canvas.getByRole("navigation", { name: "Primary navigation" });
    await userEvent.click(canvas.getByRole("radio", { name: /^One authorized operator/ }));
    await userEvent.click(sectionLink(canvasElement, "Commanding"));
    await userEvent.click(canvas.getByRole("radio", { name: /^Minimized/ }));
    await userEvent.click(canvas.getByRole("button", { name: "Save changes" }));
    await userEvent.click(canvas.getByRole("link", { name: "View organization setting" }));
    await userEvent.click(scopeLink(canvasElement, "Pathfinder"));
    await expect(canvas.getByRole("radio", { name: /^Expanded/ })).toBeChecked();
    await userEvent.click(canvas.getByRole("link", { name: "View organization setting" }));
    await userEvent.click(scopeLink(canvasElement, "Kestrel"));
    await expect(canvas.getByRole("radio", { name: /^Minimized/ })).toBeChecked();
    await userEvent.click(sectionLink(canvasElement, "Governance"));
    await expect(canvas.getByRole("radio", { name: /^One authorized operator/ })).toBeChecked();
    await expect(canvas.getByRole("button", { name: "Save changes" })).toBeEnabled();
    await userEvent.click(within(primaryNavigation).getByRole("link", { name: "Catalog" }));
    await userEvent.click(canvas.getByRole("link", { name: "Return to settings" }));
    await expect(canvas.getByRole("navigation", { name: "Primary navigation" })).toBe(
      primaryNavigation,
    );
    await expect(canvas.getByRole("button", { name: "Save changes" })).toBeEnabled();
    await userEvent.type(
      canvas.getByRole("searchbox", { name: "Find settings sections" }),
      "command",
    );
    await expect(
      within(canvas.getByRole("navigation", { name: "Settings sections" })).queryByRole("link", {
        name: "Governance",
      }),
    ).not.toBeInTheDocument();
    await expect(sectionLink(canvasElement, "Commanding")).toBeVisible();
  },
};

export const PermissionAndFailureStates: Story = {
  args: { initial: "read-only" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(canvas.getByRole("radio", { name: /^Independent approval/ })).toBeDisabled();
    await expect(canvas.queryByRole("button", { name: "Save changes" })).not.toBeInTheDocument();
    await expect(
      canvas.getByText(/Changing them requires permission to manage governance/),
    ).toBeVisible();
    await userEvent.click(sectionLink(canvasElement, "Commanding"));
    await expect(canvas.getByRole("radio", { name: /^Expanded/ })).toBeDisabled();
  },
};

export const RecoverApplicationSection: Story = {
  args: { initial: "application-unavailable" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await expect(
      canvas.getByRole("heading", { name: "Commanding settings are unavailable" }),
    ).toBeVisible();
    await userEvent.click(sectionLink(canvasElement, "Governance"));
    await expect(canvas.getByRole("radio", { name: /^Independent approval/ })).toBeEnabled();
    await userEvent.click(sectionLink(canvasElement, "Commanding"));
    await userEvent.click(canvas.getByRole("button", { name: "Retry loading" }));
    await expect(canvas.getByRole("radio", { name: /^Expanded/ })).toBeEnabled();
  },
};
