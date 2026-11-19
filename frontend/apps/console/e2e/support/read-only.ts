import type { Page } from "@playwright/test";

const READS = new Set(["GET", "HEAD", "OPTIONS"]);

/**
 * The a11y passes run read-only on the shared dev stack (qa's :4011 condition): every request
 * other than a read is aborted at the route, so nothing reaches the server, and each one is
 * logged as "a11y read-only: blocked METHOD path" for qa's report. It aborts with "aborted",
 * which the diagnostics fixture ignores as it does a request a navigation cut off.
 */
export async function guardReadOnly(page: Page): Promise<void> {
  await page.route("**/*", async (route) => {
    const request = route.request();
    if (READS.has(request.method())) return route.fallback();
    console.log(`a11y read-only: blocked ${request.method()} ${new URL(request.url()).pathname}`);
    return route.abort("aborted");
  });
}
