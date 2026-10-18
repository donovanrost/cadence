import "../src/styles.css";
import type { Preview } from "@storybook/vue3-vite";
import "../src/storybook.css";

const preview: Preview = {
  tags: ["autodocs"],
  initialGlobals: {
    skin: "standard",
  },
  globalTypes: {
    skin: {
      description: "Cadence presentation",
      toolbar: {
        icon: "contrast",
        items: [
          { value: "standard", title: "Production" },
          { value: "legible", title: "Reduced decoration" },
        ],
      },
    },
  },
  decorators: [
    (story, context) => {
      document.documentElement.dataset.theme = "dark";
      document.documentElement.dataset.skin =
        context.globals.skin === "legible" ? "legible" : "standard";

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
