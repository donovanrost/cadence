import { test as base, expect, type Page, type Request, type Response } from "@playwright/test";
import { BASE_URL } from "./env.ts";

/** Everything the browser complained about while a test ran. */
export interface BrowserDiagnostics {
  readonly pageErrors: string[];
  readonly consoleErrors: string[];
  readonly failedRequests: string[];
}

interface DiagnosticsFixtures {
  /**
   * Diagnostics a test expects (e.g. a deliberate 404 in an error-state test), as one RegExp.
   * Build it with `allow(...)`. A single value, not an array: Playwright reads an array option
   * as a `[value, fixtureOptions]` tuple.
   */
  allowedDiagnostics: RegExp | null;
  diagnostics: BrowserDiagnostics;
}

const appOrigin = new URL(BASE_URL).origin;

function isAppRequest(request: Request): boolean {
  return new URL(request.url()).origin === appOrigin;
}

function describeFailedRequest(request: Request): string | null {
  const errorText = request.failure()?.errorText ?? "unknown";
  // Navigations and unmounting components cancel in-flight requests; that is not a defect.
  if (errorText === "net::ERR_ABORTED") return null;
  return `${request.method()} ${request.url()} failed: ${errorText}`;
}

function describeErrorResponse(response: Response): string | null {
  if (response.status() < 400 || !isAppRequest(response.request())) return null;
  return `${response.request().method()} ${response.url()} -> ${response.status()}`;
}

function collect(page: Page): BrowserDiagnostics {
  const diagnostics: BrowserDiagnostics = { pageErrors: [], consoleErrors: [], failedRequests: [] };
  page.on("pageerror", (error) => diagnostics.pageErrors.push(error.message));
  page.on("console", (message) => {
    if (message.type() !== "error") return;
    const source = message.location().url;
    diagnostics.consoleErrors.push(source ? `${message.text()} (${source})` : message.text());
  });
  page.on("requestfailed", (request) => {
    const described = describeFailedRequest(request);
    if (described !== null) diagnostics.failedRequests.push(described);
  });
  page.on("response", (response) => {
    const described = describeErrorResponse(response);
    if (described !== null) diagnostics.failedRequests.push(described);
  });
  return diagnostics;
}

function unexpected(entries: readonly string[], allowed: RegExp | null): string[] {
  return allowed === null ? [...entries] : entries.filter((entry) => !allowed.test(entry));
}

/** Combines patterns into the single RegExp `allowedDiagnostics` takes. */
export function allow(...patterns: readonly RegExp[]): RegExp {
  return new RegExp(patterns.map((pattern) => `(?:${pattern.source})`).join("|"));
}

/**
 * Every console e2e test fails if the page threw, logged a console error, or had an
 * app request fail (network error or HTTP >= 400), unless the test allows it explicitly.
 */
export const test = base.extend<DiagnosticsFixtures>({
  allowedDiagnostics: [null, { option: true }],
  diagnostics: [
    async ({ page, allowedDiagnostics }, use) => {
      const diagnostics = collect(page);
      await use(diagnostics);
      expect
        .soft(
          {
            pageErrors: unexpected(diagnostics.pageErrors, allowedDiagnostics),
            consoleErrors: unexpected(diagnostics.consoleErrors, allowedDiagnostics),
            failedRequests: unexpected(diagnostics.failedRequests, allowedDiagnostics),
          },
          "browser diagnostics",
        )
        .toEqual({ pageErrors: [], consoleErrors: [], failedRequests: [] });
    },
    { auto: true },
  ],
});

export { expect };
