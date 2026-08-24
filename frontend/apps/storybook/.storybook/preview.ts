import "@cadence/design-tokens/base.css";
import type { Preview } from "@storybook/vue3-vite";
import "../src/storybook.css";

const preview: Preview = {
  tags: ["autodocs"],
  initialGlobals: {
    theme: "dark",
  },
  globalTypes: {
    theme: {
      description: "Cadence color mode",
      toolbar: {
        icon: "contrast",
        items: [
          { value: "dark", title: "Dark mode" },
          { value: "light", title: "Light mode" },
        ],
      },
    },
  },
  decorators: [
    (story, context) => {
      document.documentElement.dataset.theme = context.globals.theme === "light" ? "light" : "dark";

      return {
        components: { story },
        template: "<story />",
      };
    },
  ],
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
        order: ["Foundations", "Components", "Compositions"],
      },
    },
    a11y: {
      test: "error",
    },
  },
};

export default preview;
