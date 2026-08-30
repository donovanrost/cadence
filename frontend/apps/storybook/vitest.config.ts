import { storybookTest } from "@storybook/addon-vitest/vitest-plugin";
import { playwright } from "vite-plus/test/browser-playwright";
import { resolve } from "node:path";
import { defineConfig, mergeConfig } from "vite-plus";
import viteConfig from "./vite.config";

const storybookConfigDirectory = resolve(import.meta.dirname, ".storybook");

export default mergeConfig(
  viteConfig,
  defineConfig({
    test: {
      projects: [
        {
          extends: true,
          plugins: [
            storybookTest({
              configDir: storybookConfigDirectory,
              tags: { include: ["test"], exclude: [], skip: [] },
            }),
          ],
          test: {
            name: "storybook",
            browser: {
              enabled: true,
              headless: true,
              provider: playwright({ launchOptions: { channel: "chrome" } }),
              instances: [{ browser: "chromium" }],
            },
          },
        },
      ],
    },
  }),
);
