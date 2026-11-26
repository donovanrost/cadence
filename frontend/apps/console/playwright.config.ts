import { defineConfig, devices } from "@playwright/test";
import { BASE_URL, DEFAULT_STORAGE_STATE, storageStateFor } from "./e2e/support/env.ts";
import { A11Y_PERSONAS, A11Y_VIEWPORTS } from "./e2e/support/a11y-projects.ts";

/** Specs that stage a change set on the shared server (docs/apogee/qa/e2e.md §1). */
const SERIAL_SPECS = /\/(changes|setup-stations|setup-add-spacecraft)\.e2e\.ts$/;

// Console e2e runs against a live Phoenix server (docs/dev-environment.md).
// It is deliberately not part of the workspace `test` script.
export default defineConfig({
  testDir: "./e2e",
  outputDir: "./test-results",
  fullyParallel: true,
  // The dev stack shares one laptop with the whole team (Vite dev, Phoenix code reloader, mix
  // builds), so keep parallelism and timeouts conservative. Raise with E2E_WORKERS when idle.
  workers: Number(process.env["E2E_WORKERS"] ?? "2"),
  timeout: 60_000,
  expect: { timeout: 15_000 },
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
    {
      name: "setup",
      testMatch: /.*\.setup\.ts/,
      // #242 (director): sign-in is never traced or recorded; the specs only reuse its storageState.
      use: { trace: "off", video: "off" },
      // The LiveView sign-in page can take 10–20 s to connect on the loaded laptop; retry once.
      retries: 1,
    },
    {
      name: "desktop",
      testMatch: /.*\.e2e\.ts/,
      testIgnore: SERIAL_SPECS,
      dependencies: ["setup"],
      use: {
        ...devices["Desktop Chrome"],
        channel: "chrome",
        viewport: { width: 1512, height: 1000 },
        storageState: DEFAULT_STORAGE_STATE,
      },
    },
    // e2e.md shared-state rules: these stage a QA-E2E change set and discard it, and each skips when another
    // set is staged, so they never run side by side on one server. CI runs this project on one
    // shard with --workers=1 (#242); locally, run it the same way.
    {
      name: "desktop-serial",
      testMatch: SERIAL_SPECS,
      fullyParallel: false,
      dependencies: ["setup"],
      use: {
        ...devices["Desktop Chrome"],
        channel: "chrome",
        viewport: { width: 1512, height: 1000 },
        storageState: DEFAULT_STORAGE_STATE,
      },
    },
    // #176 fleet-scale budgets (*.perf.ts): timings, so CI runs them alone with one worker.
    {
      name: "scale",
      testMatch: /.*\.perf\.ts/,
      fullyParallel: false,
      dependencies: ["setup"],
      use: {
        ...devices["Desktop Chrome"],
        channel: "chrome",
        viewport: { width: 1512, height: 1000 },
        storageState: DEFAULT_STORAGE_STATE,
      },
    },
    // #189 per-screen a11y passes (*.a11y.ts): each spec runs at 1440 and 390, as an organization
    // admin and as a member, like qa's run 2. The spec reads its persona from the project metadata.
    ...A11Y_VIEWPORTS.flatMap((size) =>
      A11Y_PERSONAS.map((persona) => ({
        name: `a11y-${size.name}-${persona.name}`,
        testMatch: /.*\.a11y\.ts/,
        dependencies: ["setup"],
        metadata: { persona: persona.name },
        use: {
          ...devices["Desktop Chrome"],
          channel: "chrome",
          viewport: size.viewport,
          storageState: storageStateFor(persona.key),
        },
      })),
    ),
  ],
});
