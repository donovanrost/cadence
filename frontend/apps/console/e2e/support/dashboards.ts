import { expect, type Locator, type Page } from "@playwright/test";
import { missionPath, openConsole } from "./console.ts";
import { waitForScreen } from "./keyboard.ts";

/**
 * Opening a dashboard records a view (`POST …/dashboards/:id/views`). The a11y passes are
 * read-only on real data, so the view record is aborted at the route and never reaches the
 * server (the viewer doesn't wait on it). Registered after guardReadOnly, so it logs the same way.
 */
export async function holdViewRecords(page: Page): Promise<void> {
  await page.route(/\/dashboards\/[^/]+\/views$/, async (route) => {
    if (route.request().method() !== "POST") return route.fallback();
    console.log(`a11y read-only: blocked POST ${new URL(route.request().url()).pathname}`);
    return route.abort("aborted");
  });
}

/** A list screen's first row link in <main>'s table, or null when the list is empty. */
export async function firstRowLink(page: Page, rest: string): Promise<Locator | null> {
  await openConsole(page, missionPath(rest));
  await waitForScreen(page);
  const link = page.getByRole("main").getByRole("table").getByRole("link").first();
  return (await link.count()) === 0 ? null : link;
}

/** The path of the directory's first dashboard (its Name link), or null on a mission with none. */
export async function firstDashboardPath(page: Page): Promise<string | null> {
  const link = await firstRowLink(page, "telemetry/dashboards");
  if (link === null) return null;
  const href = await link.getAttribute("href");
  expect(href, "the Name cell links to the dashboard").toMatch(/\/telemetry\/dashboards\/[^/]+$/);
  return href;
}
