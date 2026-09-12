import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect, waitFor, within } from "storybook/test";
import { ref } from "vue";
import { AccountMenu as ShellAccount } from "../../host/src/auth-and-navigation";

const meta = {
  title: "Patterns/Account Menus",
  parameters: { layout: "fullscreen" },
} satisfies Meta;
export default meta;
type Story = StoryObj<typeof meta>;

const context = {
  version: 1,
  user: { user_id: "story-user", display_name: "Mission operator", email: "operator@example.test" },
  organization: { organization_id: "flight", display_name: "Flight Operations" },
  organizations: [
    { organization_id: "flight", display_name: "Flight Operations" },
    { organization_id: "engineering", display_name: "Engineering" },
  ],
  notifications: [
    {
      notification_id: "contact",
      title: "Contact scheduled",
      body: "Artemis acquisition in 10 minutes",
      read_at: null,
    },
  ],
  unread_count: 1,
  platform_admin: false,
  admin_mode: false,
  csrf_token: "storybook-csrf",
};

const render = () => ({
  components: { ShellAccount },
  setup() {
    const submitted = ref("");
    function submit(event: Event) {
      event.preventDefault();
      const form = event.target as HTMLFormElement;
      const data = new FormData(form);
      const text = (key: string) => {
        const value = data.get(key);
        if (typeof value !== "string" && value !== null) throw Error("Expected a text form field");
        return value ?? "";
      };
      submitted.value = `${text("_method")} ${form.getAttribute("action")} ${text("organization_id")} ${text("_csrf_token")}`;
    }
    return { context, submitted, submit };
  },
  template: `<div class="min-h-screen bg-base-100" @submit="submit" @click="$event.target.closest('a') && $event.preventDefault()">
    <header class="flex h-12 items-center justify-end border-b border-base-300 bg-base-200 px-4">
      <ShellAccount id="story-account" :context="context" />
    </header>
    <main class="p-6"><button type="button" class="btn btn-outline">Outside the menus</button><p role="status" class="mt-4">{{ submitted }}</p></main>
  </div>`,
});

export const Interaction: Story = {
  name: "Production interaction",
  render,
  play: async ({ canvas, userEvent }) => {
    const notifications = canvas.getByRole("button", { name: "Notifications" });
    const account = canvas.getByRole("button", { name: "Mission operator" });
    await expect(canvas.queryByRole("menu")).not.toBeInTheDocument();
    await expect(notifications).toHaveAttribute("aria-expanded", "false");
    await expect(account).toHaveAttribute("aria-expanded", "false");

    await userEvent.click(notifications);
    await expect(canvas.getByRole("menu")).toBeVisible();
    await userEvent.keyboard("{Escape}");
    await waitFor(() => expect(canvas.queryByRole("menu")).not.toBeInTheDocument());
    await expect(notifications).toHaveFocus();

    await userEvent.keyboard("{ArrowDown}");
    await expect(canvas.getByRole("menuitem", { name: /Contact scheduled/ })).toHaveFocus();
    await userEvent.click(account);
    await waitFor(() => expect(notifications).toHaveAttribute("aria-expanded", "false"));
    await expect(canvas.getAllByRole("menu")).toHaveLength(1);
    await userEvent.click(canvas.getByRole("button", { name: "Outside the menus" }));
    await waitFor(() => expect(canvas.queryByRole("menu")).not.toBeInTheDocument());

    await userEvent.click(account);
    await userEvent.click(canvas.getByRole("menuitem", { name: "Engineering" }));
    await expect(canvas.getByRole("status")).toHaveTextContent(
      "put /session/organization engineering storybook-csrf",
    );
    // The fixture intercepts navigation; native form items stay mounted until it occurs.
    await expect(canvas.getByRole("menu")).toBeVisible();
    await userEvent.keyboard("{Escape}");
    await userEvent.click(account);
    await userEvent.click(canvas.getByRole("menuitem", { name: "Sign out" }));
    await expect(canvas.getByRole("status")).toHaveTextContent("delete /session storybook-csrf");
    await expect(canvas.getByRole("menu")).toBeVisible();
    await userEvent.keyboard("{Escape}");
    await expect(account).toHaveFocus();
  },
};

export const NotificationsOpen: Story = {
  name: "Production notifications",
  render,
  play: async ({ canvas, userEvent }) => {
    await userEvent.click(canvas.getByRole("button", { name: "Notifications" }));
    await expect(canvas.getByRole("menu")).toBeVisible();
  },
};

export const AccountOpen: Story = {
  name: "Production account menu",
  render,
  play: async ({ canvas, userEvent }) => {
    await userEvent.click(canvas.getByRole("button", { name: "Mission operator" }));
    const menu = canvas.getByRole("menu");
    await expect(within(menu).getByRole("menuitem", { name: "Sign out" })).toBeVisible();
    await waitFor(async () => {
      const bounds = menu.getBoundingClientRect();
      await expect(bounds.right).toBeLessThanOrEqual(window.innerWidth);
      await expect(bounds.bottom).toBeLessThanOrEqual(window.innerHeight);
      await expect(bounds.top).toBeGreaterThanOrEqual(40);
    });
  },
};
