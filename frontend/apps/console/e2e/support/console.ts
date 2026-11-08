import { expect, type Page, type Response } from "@playwright/test";
import { DEMO } from "./env.ts";

/**
 * Opens a console route and waits until the shell has booted (lead's contract:
 * `<body data-shell-ready>`). The boot screen also has an h1, so never assert before this.
 */
export async function openConsole(page: Page, path = "/console"): Promise<Response | null> {
  const response = await page.goto(path);
  await expect(page.locator("body[data-shell-ready]")).toBeAttached();
  return response;
}

/** `/console/<org>/<mission>/<rest>` for the seeded demo mission. */
export function missionPath(rest = ""): string {
  const base = `/console/${DEMO.organizationSlug}/${DEMO.missionSlug}`;
  return rest === "" ? base : `${base}/${rest.replace(/^\//, "")}`;
}

/** Glob for a mission-scoped console API endpoint, for page.route. */
export function missionApi(rest: string): string {
  return `**/api/console/v1/missions/${DEMO.missionId}/${rest.replace(/^\//, "")}`;
}

/** Fulfils a console API route with `{ data }` JSON. */
export function jsonData(data: unknown, status = 200) {
  return { status, contentType: "application/json", body: JSON.stringify({ data }) };
}

/** Fulfils a console API route with a JSON problem. */
export function jsonProblem(status: number, code: string) {
  return {
    status,
    contentType: "application/json",
    body: JSON.stringify({ error: { code, message: `qa fixture ${code}`, details: {} } }),
  };
}
