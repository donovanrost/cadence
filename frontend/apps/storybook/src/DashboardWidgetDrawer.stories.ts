import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect, fn, userEvent, waitFor, within } from "storybook/test";
import { dashboardContribution } from "@cadence/dashboards-and-exploration/workspace";
import {
  editPage,
  pageContext,
} from "../../../modules/dashboards-and-exploration/src/features/dashboard/fixtures.test-support";

const execute = fn(async (action: string, _input: Record<string, unknown>): Promise<unknown> => ({
  status: "ok",
  page: { status: "ready", data: editPage(action === "save" ? 2 : 1, action !== "save") },
  result: null,
}));

const meta = {
  title: "Modules/Dashboards/Widget drawer",
  component: dashboardContribution.component,
  parameters: {
    layout: "fullscreen",
    // Scan the drawer under review; the surrounding dashboard is context for the journey.
    a11y: { context: '[role="dialog"][aria-modal="true"]' },
  },
  args: {
    page: editPage(),
    context: pageContext,
    port: {
      execute,
      navigate: fn(),
      guardNavigation: () => () => {},
    },
    refresh: async () => {},
  },
} satisfies Meta<typeof dashboardContribution.component>;
export default meta;
type Story = StoryObj<typeof meta>;

export const KeyboardAndPointer: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const body = within(canvasElement.ownerDocument.body);
    const opener = canvas.getByRole("button", { name: "Widget" });
    const section = canvas.getByRole("button", { name: "Section" });
    opener.focus();
    await userEvent.keyboard("{Enter}");
    const dialog = await body.findByRole("dialog", { name: "Add widget" });
    await expect(dialog).toHaveAttribute("aria-modal", "true");
    await waitFor(() => expect(within(dialog).getByRole("heading")).toHaveFocus());
    // Background controls are absent from the accessible modal surface.
    await expect(canvas.queryByRole("button", { name: "Section" })).not.toBeInTheDocument();
    section.focus();
    await expect(dialog.contains(document.activeElement)).toBe(true);

    const close = within(dialog).getByRole("button", { name: "Close" });
    await userEvent.tab();
    await expect(close).toHaveFocus();
    await userEvent.tab({ shift: true });
    await expect(within(dialog).getByRole("button", { name: "Cancel" })).toHaveFocus();
    await userEvent.tab();
    await expect(close).toHaveFocus();
    // Walk the whole form in both directions, including its radio groups.
    for (const shift of [false, true]) {
      for (let step = 0; step < 24; step++) {
        await userEvent.tab({ shift });
        await expect(dialog.contains(document.activeElement)).toBe(true);
      }
    }
    await userEvent.keyboard("{Escape}");
    await waitFor(() => expect(body.queryByRole("dialog")).not.toBeInTheDocument());
    await expect(opener).toHaveFocus();

    await userEvent.keyboard("{Enter}");
    await userEvent.click(await body.findByRole("button", { name: "Close" }));
    await waitFor(() => expect(opener).toHaveFocus());
    await userEvent.keyboard("{Enter}");
    const reopened = await body.findByRole("dialog", { name: "Add widget" });
    // Hit-test where the background Section button sits: the scrim receives the click.
    const bounds = section.getBoundingClientRect();
    const target = document.elementFromPoint(
      bounds.x + bounds.width / 2,
      bounds.y + bounds.height / 2,
    );
    if (!(target instanceof HTMLElement)) throw Error("Missing backdrop hit target");
    await expect(target).not.toBe(section);
    await userEvent.click(target);
    await waitFor(() => expect(reopened).not.toBeInTheDocument());
    await expect(body.queryByRole("dialog")).not.toBeInTheDocument();
    await expect(opener).toHaveFocus();
    // Leave the subject of this story open for the accessibility scan and preview.
    await userEvent.keyboard("{Enter}");
    await waitFor(() => expect(body.getByRole("heading", { name: "Add widget" })).toHaveFocus());
  },
};

export const AddAndSave: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const body = within(canvasElement.ownerDocument.body);
    const opener = canvas.getByRole("button", { name: "Widget" });
    await userEvent.click(opener);
    const dialog = await body.findByRole("dialog", { name: "Add widget" });
    await userEvent.type(within(dialog).getByRole("textbox", { name: "Title" }), "Fleet overview");
    await userEvent.selectOptions(
      within(dialog).getByRole("combobox", { name: "Visualization" }),
      "constellation_health",
    );
    await userEvent.click(within(dialog).getByRole("button", { name: "Add widget" }));
    await waitFor(() => expect(dialog).not.toBeInTheDocument());
    await expect(opener).toHaveFocus();
    await expect(execute.mock.calls.find(([action]) => action === "add_widget")?.[1]).toMatchObject(
      {
        command: { fields: { title: "Fleet overview", type: "constellation_health" } },
      },
    );
    const save = canvas.getByRole("button", { name: "Save dashboard" });
    await userEvent.click(save);
    const saveDialog = await body.findByRole("dialog", { name: "Save dashboard" });
    await userEvent.type(
      within(saveDialog).getByRole("textbox", { name: "Message" }),
      "Widget focus regression",
    );
    await userEvent.click(within(saveDialog).getByRole("button", { name: "Save" }));
    await waitFor(() => expect(saveDialog).not.toBeInTheDocument());
    await expect(save).toHaveFocus();
    await expect(execute.mock.calls.find(([action]) => action === "save")?.[1]).toMatchObject({
      command: { message: "Widget focus regression" },
    });
    await userEvent.click(opener);
    await waitFor(() => expect(body.getByRole("heading", { name: "Add widget" })).toHaveFocus());
  },
};

export const ConfigureExisting: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const body = within(canvasElement.ownerDocument.body);
    const opener = canvas.getByRole("button", { name: "Actions for Battery" });
    opener.focus();
    await userEvent.keyboard("{Enter}");
    await userEvent.click(await body.findByRole("menuitem", { name: "Configure" }));
    let dialog = await body.findByRole("dialog", { name: "Configure widget" });
    await waitFor(() => expect(within(dialog).getByRole("heading")).toHaveFocus());
    await expect(within(dialog).getByRole("textbox", { name: "Title" })).toHaveValue("Battery");
    await userEvent.tab();
    await userEvent.tab({ shift: true });
    await expect(within(dialog).getByRole("button", { name: "Apply" })).toHaveFocus();
    await userEvent.tab();
    await expect(within(dialog).getByRole("button", { name: "Close" })).toHaveFocus();
    await userEvent.keyboard("{Escape}");
    await waitFor(() => expect(opener).toHaveFocus());

    await userEvent.keyboard("{Enter}");
    await userEvent.click(await body.findByRole("menuitem", { name: "Configure" }));
    dialog = await body.findByRole("dialog", { name: "Configure widget" });
    const title = within(dialog).getByRole("textbox", { name: "Title" });
    await userEvent.clear(title);
    await userEvent.type(title, "Battery voltage");
    await userEvent.click(within(dialog).getByRole("button", { name: "Apply" }));
    await waitFor(() => expect(dialog).not.toBeInTheDocument());
    await expect(opener).toHaveFocus();
    await expect(
      execute.mock.calls.find(([action]) => action === "update_widget")?.[1],
    ).toMatchObject({
      command: { placement_id: "battery", fields: { title: "Battery voltage" } },
    });
    await userEvent.keyboard("{Enter}");
    await userEvent.click(await body.findByRole("menuitem", { name: "Configure" }));
    await waitFor(() =>
      expect(body.getByRole("heading", { name: "Configure widget" })).toHaveFocus(),
    );
  },
};
