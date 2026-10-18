import { afterEach } from "vite-plus/test";
// The browser runner virtualizes this exact module; a re-export loads a second context.
// oxlint-disable-next-line vite-plus/prefer-vite-plus-imports
import { page } from "@vitest/browser/context";

// Opt-in review artifacts, kept outside source control alongside build output.
afterEach(async ({ task }) => {
  if (import.meta.env.VITE_DESIGN_SYSTEM_SCREENSHOTS !== "true") return;
  if (!/System Reference|Production|Data Table|Native Form|Page States/i.test(task.name)) return;
  await page.viewport(1280, 1200);
  await page.screenshot({ fullPage: true });
});
