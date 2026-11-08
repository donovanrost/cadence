import { expect, type Page, type Response } from "@playwright/test";

/**
 * Opens a console route and waits until the shell has booted (lead's contract:
 * `<body data-shell-ready>`). The boot screen also has an h1, so never assert before this.
 */
export async function openConsole(page: Page, path = "/console"): Promise<Response | null> {
  const response = await page.goto(path);
  await expect(page.locator("body[data-shell-ready]")).toBeAttached();
  return response;
}
