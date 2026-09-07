import tailwindcss from "@tailwindcss/vite";
import type { StorybookConfig } from "@storybook/vue3-vite";

const config: StorybookConfig = {
  stories: ["../../../packages/ui/src/**/*.stories.@(js|ts)", "../src/**/*.stories.@(js|ts)"],
  addons: ["@storybook/addon-docs", "@storybook/addon-a11y", "@storybook/addon-vitest"],
  framework: {
    name: "@storybook/vue3-vite",
    options: {},
  },
  core: {
    disableTelemetry: true,
  },
  docs: {
    defaultName: "Documentation",
  },
  async viteFinal(viteConfig) {
    const { mergeConfig } = await import("vite-plus");

    return mergeConfig(viteConfig, {
      plugins: [tailwindcss()],
      build: {
        // Docs and accessibility panels are intentionally large development-only chunks.
        chunkSizeWarningLimit: 1200,
      },
    });
  },
};

export default config;
