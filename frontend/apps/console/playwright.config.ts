import { defineConfig, devices } from "@playwright/test";
import { ADMIN_STORAGE_STATE, BASE_URL } from "./e2e/support/env.ts";

// Console e2e runs against a live Phoenix server (docs/apogee/qa/runbook.md).
// It is deliberately not part of the workspace `test` script.
export default defineConfig({
  testDir: "./e2e",
  outputDir: "./test-results",
  fullyParallel: true,
  forbidOnly: Boolean(process.env["CI"]),
  retries: 0,
  reporter: [["list"], ["html", { open: "never", outputFolder: "./playwright-report" }]],
  use: {
    baseURL: BASE_URL,
    channel: "chrome",
    trace: "retain-on-failure",
    screenshot: "only-on-failure",
  },
  projects: [
    { name: "setup", testMatch: /.*\.setup\.ts/ },
    {
      name: "desktop",
      testMatch: /.*\.e2e\.ts/,
      dependencies: ["setup"],
      use: {
        ...devices["Desktop Chrome"],
        channel: "chrome",
        viewport: { width: 1512, height: 1000 },
        storageState: ADMIN_STORAGE_STATE,
      },
    },
  ],
});
