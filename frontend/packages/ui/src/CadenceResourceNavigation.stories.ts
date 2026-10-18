import type { Meta, StoryObj } from "@storybook/vue3-vite";
import { expect, userEvent, within } from "storybook/test";
import CadenceResourceNavigation from "./CadenceResourceNavigation.vue";
const meta = {
  title: "Components/Navigation/Resource sections",
  component: CadenceResourceNavigation,
  args: { label: "Resource sections" },
  render: (args) => ({
    components: { CadenceResourceNavigation },
    setup: () => ({ args }),
    template:
      '<CadenceResourceNavigation v-bind="args"><a href="#overview" aria-current="page">Overview</a><a href="#catalog">Catalog &amp; applications</a><a href="#changes">Changes <span>2</span></a><template #status>Draft saved</template></CadenceResourceNavigation>',
  }),
} satisfies Meta<typeof CadenceResourceNavigation>;
export default meta;
type Story = StoryObj<typeof meta>;
export const Sections: Story = {
  play: async ({ canvasElement }) => {
    const canvas = within(canvasElement);
    const navigation = canvas.getByRole("navigation", { name: "Resource sections" });
    const links = within(navigation).getAllByRole("link");
    await expect(links).toHaveLength(3);
    await expect(links[0]).toHaveAttribute("aria-current", "page");
    links[0]?.focus();
    await userEvent.tab();
    await expect(links[1]).toHaveFocus();
    await expect(links[1]).toHaveAttribute("href", "#catalog");
    await expect(canvas.queryByRole("tab")).not.toBeInTheDocument();
  },
};
