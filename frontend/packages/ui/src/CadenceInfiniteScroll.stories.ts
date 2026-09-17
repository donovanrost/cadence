import type { Meta, StoryObj } from "@storybook/vue3-vite";
import CadenceInfiniteScroll from "./CadenceInfiniteScroll.vue";

const meta = {
  title: "Components/Feedback/Infinite Scroll",
  component: CadenceInfiniteScroll,
  args: { root: null, hasMore: true, loading: true },
  parameters: {
    docs: {
      description: {
        component:
          "Place at the end of a scroll container and supply its element as root. Requests another page near the bottom and rechecks after each page, including when the first page does not fill the pane. The caller owns fetching, results, and errors. See Operations/Commanding/Workspace for an interactive example.",
      },
    },
  },
} satisfies Meta<typeof CadenceInfiniteScroll>;
export default meta;
type Story = StoryObj<typeof meta>;
export const Loading: Story = {};
export const Retry: Story = { args: { loading: false, error: "Results could not be loaded." } };
export const Complete: Story = { args: { loading: false, hasMore: false } };
