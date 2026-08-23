import "@cadence/design-tokens/base.css";
import type { Preview } from "@storybook/vue3-vite";
import "../src/storybook.css";

const preview: Preview = {
  tags: ["autodocs"],
  parameters: {
    layout: "centered",
    controls: {
      matchers: {
        color: /(background|color)$/i,
        date: /Date$/i,
      },
    },
    options: {
      storySort: {
        order: ["Foundations", "Components"],
      },
    },
    a11y: {
      test: "error",
    },
  },
};

export default preview;
