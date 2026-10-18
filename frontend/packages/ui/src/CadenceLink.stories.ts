import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect, userEvent, within } from "storybook/test";
import CadenceLink from "./CadenceLink.vue";

const meta = {
  title: "Components/Actions/Link",
  component: CadenceLink,
  args: { href: "#catalog-revision" },
  parameters: {
    docs: {
      description: {
        component:
          "Native navigation with shared link styling. Supports href, target, rel, downloads and modified clicks through native anchor attributes. Use CadenceButton for actions that change local state.",
      },
    },
  },
  render: (args) => ({
    components: { CadenceLink },
    setup: () => ({ args }),
    template: '<CadenceLink v-bind="args">View catalog revision</CadenceLink>',
  }),
} satisfies Meta<typeof CadenceLink>;
export default meta;
type Story = StoryObj<typeof meta>;

export const Navigation: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const link = canvas.getByRole("link", { name: "View catalog revision" });
    await expect(link).toHaveAttribute("href", "#catalog-revision");
    link.focus();
    await expect(link).toHaveFocus();
    await userEvent.tab();
    await expect(link).not.toHaveFocus();
    await expect(canvas.queryByRole("button")).not.toBeInTheDocument();
  },
};

export const NewTab: Story = {
  render: () => ({
    components: { CadenceLink },
    template:
      '<CadenceLink href="/iframe.html?id=components-actions-link--navigation&amp;viewMode=story" target="_blank" rel="noopener">View reference <span class="sr-only">(opens in new tab)</span><template #icon><span class="hero-arrow-top-right-on-square" /></template></CadenceLink>',
  }),
  play: async ({ canvasElement }) => {
    const link = within(canvasElement).getByRole("link", {
      name: "View reference (opens in new tab)",
    });
    await expect(link).toHaveAttribute("target", "_blank");
    await expect(link).toHaveAttribute("rel", "noopener");
  },
};
