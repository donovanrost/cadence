import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect, userEvent, within, waitFor } from "storybook/test";
import CommandWorkspaceExample from "./CommandWorkspaceExample.vue";
const meta = {
  title: "Operations/Commanding/Workspace",
  component: CommandWorkspaceExample,
  parameters: {
    layout: "fullscreen",
    viewport: {
      options: {
        laptop: { name: "Compact laptop", styles: { width: "1280px", height: "720px" } },
        macbook: { name: "Laptop", styles: { width: "1440px", height: "800px" } },
        short: { name: "Short desktop window", styles: { width: "1600px", height: "700px" } },
        desktop: { name: "Large desktop", styles: { width: "1920px", height: "1080px" } },
      },
    },
    docs: {
      description: {
        component:
          "The production Ops workspace with deterministic mission fixtures. Core UI owns the splitter layout, pane framing, selection tiles, and popover behavior. Commanding owns target identity, exact arguments, stages, and request review.",
      },
    },
  },
} satisfies Meta<typeof CommandWorkspaceExample>;
export default meta;
type Story = StoryObj<typeof meta>;

async function prepareInViewport({ canvasElement }: { canvasElement: HTMLElement }) {
  const canvas = within(canvasElement);
  await userEvent.click(canvas.getByRole("button", { name: "Select KESTREL-01 · KESTREL-01 OBC" }));
  await userEvent.click(canvas.getByRole("button", { name: "Select KESTREL-02 · KESTREL-02 OBC" }));
  await userEvent.click(canvas.getByRole("button", { name: /Set telemetry rate SET_TLM_RATE/ }));
  const argument = canvas.getByRole("textbox", { name: "interval_seconds integer" });
  await userEvent.clear(argument);
  await userEvent.type(argument, "12");

  // This checks actual clipping: toBeVisible alone also passes for offscreen scroll content.
  const preview = canvas.getByRole("button", { name: "Enqueue 2 commands" });
  await waitFor(() => expect(preview).toBeEnabled());
  preview.scrollIntoView({ block: "center" });
  const scrollArea = preview.closest(".cadence-pane__body");
  if (!scrollArea) throw Error("Preparation must have an independent scroll area");
  const actionBounds = preview.getBoundingClientRect();
  const paneBounds = scrollArea.getBoundingClientRect();
  await expect(actionBounds.top).toBeGreaterThanOrEqual(paneBounds.top);
  await expect(actionBounds.bottom).toBeLessThanOrEqual(paneBounds.bottom);
  await expect(canvasElement.ownerDocument.documentElement.scrollWidth).toBeLessThanOrEqual(
    window.innerWidth,
  );
  await expect(canvas.getByRole("button", { name: "Toggle navigation" })).toBeVisible();
  await expect(canvas.getByRole("navigation", { name: "Breadcrumb" })).toBeVisible();
  await expect(canvas.getByRole("heading", { level: 1, name: "Commanding" })).toBeVisible();

  await userEvent.click(canvas.getByRole("button", { name: "Minimize command shelf" }));
  await expect(canvas.getByRole("button", { name: "Expand command shelf" })).toHaveFocus();
  await expect(argument).toHaveValue("12");
  await userEvent.keyboard("{Enter}");
  await expect(argument).toHaveValue("12");
  await expect(canvas.getByRole("heading", { name: "2 targets validated" })).toBeVisible();
  await expect(
    canvas.getByRole("button", { name: "Add 2 drafts to Flight preparation" }),
  ).toBeEnabled();
}

export const Browse: Story = { args: { initial: "browse" } };
export const Staged: Story = { args: { initial: "staged" } };
export const MissingModel: Story = { args: { initial: "model-unavailable" } };
export const EnqueueWithoutStage: Story = {
  args: { initial: "browse", withoutStage: true },
  globals: { viewport: { value: "laptop" } },
  play: async ({ canvas }) => {
    await userEvent.click(canvas.getByRole("button", { name: "Minimize command shelf" }));
    await userEvent.click(
      canvas.getByRole("button", { name: "Select KESTREL-01 · KESTREL-01 OBC" }),
    );
    await userEvent.click(canvas.getByRole("button", { name: /Set telemetry rate SET_TLM_RATE/ }));
    await waitFor(() =>
      expect(canvas.getByRole("button", { name: "Enqueue command" })).toBeEnabled(),
    );
    await userEvent.click(canvas.getByRole("button", { name: "Enqueue command" }));
    await expect(await canvas.findByText("Command queued.")).toBeVisible();
    await expect(canvas.getByRole("button", { name: "Expand command shelf" })).toBeVisible();
    await expect(canvas.queryByRole("link", { name: /Queued/ })).not.toBeInTheDocument();
    await expect(canvas.getByRole("button", { name: "Enqueue command" })).toBeDisabled();
    await userEvent.click(canvas.getByRole("button", { name: "Expand command shelf" }));
    await expect(canvas.getByRole("button", { name: "Choose a stage" })).toBeVisible();
  },
};
export const EnumeratedArguments: Story = {
  args: { initial: "browse" },
  globals: { viewport: { value: "laptop" } },
  play: async ({ canvas }) => {
    await userEvent.click(
      canvas.getByRole("button", { name: "Select KESTREL-01 · KESTREL-01 OBC" }),
    );
    await userEvent.click(
      canvas.getByRole("button", { name: /Set heater setpoint SET_HEATER_SETPOINT/ }),
    );
    await expect(canvas.getByRole("radiogroup", { name: "heater_id" })).toBeVisible();
    await userEvent.click(canvas.getByRole("radio", { name: "2" }));
    await userEvent.type(canvas.getByRole("textbox", { name: "setpoint float" }), "18.5");
    await expect(canvas.getByRole("heading", { name: "1 target validated" })).toBeVisible();
    await userEvent.click(canvas.getByRole("radio", { name: "1" }));
    await waitFor(() =>
      expect(
        canvas.getByRole("region", { name: "Resolved target previews" }).querySelector("dd"),
      ).toHaveTextContent("1"),
    );
  },
};
export const ManyEnumChoices: Story = {
  args: { initial: "browse" },
  globals: { viewport: { value: "laptop" } },
  play: async ({ canvas }) => {
    await userEvent.click(
      canvas.getByRole("button", { name: "Select KESTREL-01 · KESTREL-01 OBC" }),
    );
    await userEvent.click(
      canvas.getByRole("button", { name: /Select downlink channel SELECT_CHANNEL/ }),
    );
    await userEvent.selectOptions(canvas.getByRole("combobox", { name: "channel" }), "7");
    await expect(canvas.getByRole("heading", { name: "1 target validated" })).toBeVisible();
  },
};
export const PerSpacecraftValues: Story = {
  args: { initial: "browse" },
  globals: { viewport: { value: "laptop" } },
  play: async ({ canvas }) => {
    await userEvent.click(
      canvas.getByRole("button", { name: "Select KESTREL-01 · KESTREL-01 OBC" }),
    );
    await userEvent.click(
      canvas.getByRole("button", { name: "Select KESTREL-02 · KESTREL-02 OBC" }),
    );
    await userEvent.click(canvas.getByRole("button", { name: /Set telemetry rate SET_TLM_RATE/ }));
    const mode = canvas.getByRole("radiogroup", { name: "Argument values" });
    await expect(mode.closest("header")).not.toBeNull();
    await userEvent.click(canvas.getByRole("radio", { name: "Per spacecraft" }));
    const first = within(canvas.getByRole("region", { name: "Settings for KESTREL-01 OBC" }));
    const second = within(canvas.getByRole("region", { name: "Settings for KESTREL-02 OBC" }));
    await expect(first.getByRole("textbox")).toHaveValue("5");
    await userEvent.clear(first.getByRole("textbox"));
    await userEvent.type(first.getByRole("textbox"), "12");
    await userEvent.clear(second.getByRole("textbox"));
    await userEvent.type(second.getByRole("textbox"), "20");
    await userEvent.click(canvas.getByRole("radio", { name: "All spacecraft" }));
    await expect(canvas.getByRole("textbox", { name: "interval_seconds integer" })).toHaveValue(
      "5",
    );
    await expect(canvas.getByRole("heading", { name: "2 targets validated" })).toBeVisible();
    await userEvent.click(canvas.getByRole("radio", { name: "Per spacecraft" }));

    const restoredFirst = within(
      canvas.getByRole("region", { name: "Settings for KESTREL-01 OBC" }),
    );
    const restoredSecond = within(
      canvas.getByRole("region", { name: "Settings for KESTREL-02 OBC" }),
    );
    await expect(restoredFirst.getByRole("textbox")).toHaveValue("12");
    await expect(restoredSecond.getByRole("textbox")).toHaveValue("20");
    const preview = canvas.getByRole("region", { name: "Resolved target previews" });
    await expect(preview.querySelectorAll("dd")[0]).toHaveTextContent("12");
    await expect(preview.querySelectorAll("dd")[1]).toHaveTextContent("20");
  },
};
export const CompactLaptop: Story = {
  args: { initial: "browse" },
  globals: { viewport: { value: "laptop" } },
  play: prepareInViewport,
};
export const Laptop: Story = {
  args: { initial: "browse" },
  globals: { viewport: { value: "macbook" } },
  play: prepareInViewport,
};
export const ShortDesktopWindow: Story = {
  args: { initial: "browse" },
  globals: { viewport: { value: "short" } },
  play: prepareInViewport,
};
export const LargeDesktop: Story = {
  args: { initial: "browse" },
  globals: { viewport: { value: "desktop" } },
  play: prepareInViewport,
};
export const PrepareAcrossSpacecraft: Story = {
  args: { initial: "browse" },
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    await userEvent.click(
      canvas.getByRole("button", { name: "Select KESTREL-01 · KESTREL-01 OBC" }),
    );
    await userEvent.click(
      canvas.getByRole("button", { name: "Select KESTREL-02 · KESTREL-02 OBC" }),
    );
    await userEvent.click(canvas.getByRole("button", { name: /Set telemetry rate SET_TLM_RATE/ }));
    await expect(canvas.getByRole("heading", { name: /Command targets/ })).toBeVisible();
    await expect(canvas.getByRole("heading", { name: "2 targets validated" })).toBeVisible();
    await expect(
      canvas.getByRole("button", { name: "Add 2 drafts to Flight preparation" }),
    ).toBeEnabled();
    await userEvent.click(canvas.getByRole("button", { name: /^Flight preparation$/ }));
    await expect(canvas.getByRole("dialog", { name: "Command stages" })).toBeVisible();
    await userEvent.keyboard("{Escape}");
    await expect(canvas.queryByRole("dialog", { name: "Command stages" })).not.toBeInTheDocument();
    await expect(canvas.getByRole("button", { name: /^Flight preparation$/ })).toHaveFocus();
    await userEvent.click(canvas.getByRole("button", { name: "Close command preparation" }));
    await expect(
      canvas.getByRole("button", { name: /Set telemetry rate SET_TLM_RATE/ }),
    ).toHaveFocus();
    await userEvent.click(canvas.getByRole("button", { name: "Minimize command shelf" }));
    await expect(canvas.getByRole("button", { name: "Expand command shelf" })).toHaveFocus();
    await expect(canvasElement.querySelector(".cadence-workspace-layout__status")).toBeNull();
    await expect(canvas.getByRole("button", { name: "Expand command shelf" })).toHaveTextContent(
      "Flight preparation",
    );
    await userEvent.keyboard("{Enter}");
    await expect(canvas.getByRole("button", { name: "Minimize command shelf" })).toBeVisible();
  },
};

export const SearchAndInfiniteScroll: Story = {
  args: { initial: "browse", largeCatalog: true },
  globals: { viewport: { value: "laptop" } },
  play: async ({ canvas, canvasElement }) => {
    await userEvent.click(
      canvas.getByRole("button", { name: "Select KESTREL-01 · KESTREL-01 OBC" }),
    );
    await userEvent.click(canvas.getByRole("button", { name: /Set telemetry rate SET_TLM_RATE/ }));
    await userEvent.clear(canvas.getByRole("textbox", { name: "interval_seconds integer" }));
    await userEvent.type(canvas.getByRole("textbox", { name: "interval_seconds integer" }), "12");
    const fleet = canvas.getByRole("region", { name: /Command targets/ });
    const catalog = canvas.getByRole("region", { name: /Command catalog/ });
    for (const [region, selector] of [
      [fleet, "[data-workspace-target]"],
      [catalog, "[data-workspace-command]"],
    ] as const) {
      const scrollArea = region.querySelector(".cadence-pane__body");
      if (!scrollArea) throw Error("Missing pane scroll area");
      scrollArea.scrollTop = scrollArea.scrollHeight;
      await waitFor(() => expect(region.querySelectorAll(selector).length).toBeGreaterThan(25));
      scrollArea.scrollTop = scrollArea.scrollHeight;
      await waitFor(() => expect(region.querySelectorAll(selector).length).toBeGreaterThan(50));
    }
    await userEvent.type(
      canvas.getByRole("searchbox", { name: "Search command targets" }),
      "KESTREL-64",
    );
    await userEvent.type(canvas.getByRole("searchbox", { name: "Find commands" }), "TEST_060");
    await waitFor(async () => {
      await expect(fleet.querySelectorAll("[data-workspace-target]")).toHaveLength(1);
      await expect(catalog.querySelectorAll("[data-workspace-command]")).toHaveLength(1);
    });
    await expect(
      canvas.getByRole("button", { name: "Select KESTREL-64 · KESTREL-64 OBC" }),
    ).toBeVisible();
    await expect(canvas.getByRole("button", { name: /Test command 60 TEST_060/ })).toBeVisible();
    await expect(canvas.getByRole("textbox", { name: "interval_seconds integer" })).toHaveValue(
      "12",
    );
    await expect(canvas.getByRole("heading", { name: "1 target validated" })).toBeVisible();
    await expect(canvas.queryByRole("button", { name: "Find" })).not.toBeInTheDocument();
    await expect(canvasElement.ownerDocument.documentElement.scrollWidth).toBeLessThanOrEqual(
      window.innerWidth,
    );
  },
};
