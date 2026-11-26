import { expect, type Page } from "@playwright/test";
import { probeStop } from "./probe-stop.ts";

/** The dev-only Tidewave toolbar: not in production builds; it covers the 390 tab bar in dev. */
export const DEV_ONLY = ["#tidewave-toolbar"] as const;

/**
 * Waits until a screen has really rendered, as qa's run 2 did: shell ready, the network quiet
 * (best effort: live pushes may never go idle), and no "Loading…" left in <main>.
 */
export async function waitForScreen(page: Page): Promise<void> {
  await expect(page.locator("body[data-shell-ready]")).toBeAttached();
  await page.waitForLoadState("networkidle", { timeout: 10_000 }).catch(() => undefined);
  await expect(page.locator("main").getByText(/loading…/i)).toHaveCount(0, { timeout: 60_000 });
}

/** One Tab stop, as the page saw it. */
export interface TabStop {
  readonly index: number;
  readonly tag: string;
  readonly role: string | null;
  readonly name: string;
  /** The landmark the stop sits in: "main", "navigation 'Mission'", …, or "" outside any. */
  readonly landmark: string;
  readonly problems: readonly string[];
}

interface KeyboardPassOptions {
  /** Selectors whose stops are skipped (default: the dev-only toolbar). */
  readonly exclude?: readonly string[];
  /** Give up after this many stops (qa's run 2: 120). */
  readonly maxStops?: number;
}

/**
 * qa's run-2 keyboard pass (a11y checklist B1, plus §6's visible focus), read-only: it only presses
 * Tab. Checks one h1 and one <main>, no sideways scroll, then Tabs from the top until focus leaves
 * the page or wraps. Each stop must be visible, not aria-hidden, not covered by something else
 * (`elementFromPoint`), and show a focus indicator; focus must never stick on one element, and Tab
 * must visit each landmark in one run (reading order: rail, top bar, main…, never back).
 * Returns the stops, so a spec can assert its own order on top.
 */
export async function expectKeyboardPass(
  page: Page,
  options: KeyboardPassOptions = {},
): Promise<readonly TabStop[]> {
  const exclude = [...(options.exclude ?? DEV_ONLY)];
  const maxStops = options.maxStops ?? 120;

  await expect(page.locator("h1"), "one h1").toHaveCount(1);
  await expect(page.locator("main, [role=main]"), "one main landmark").toHaveCount(1);
  const sideways = await page.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
  );
  expect(sideways, "page scrolls sideways by (px)").toBeLessThanOrEqual(1);

  // Start from the top of the document, as a person arriving on the page would.
  await page.evaluate(() => {
    const active = document.activeElement;
    if (active instanceof HTMLElement) active.blur();
    window.scrollTo(0, 0);
  });

  const stops: TabStop[] = [];
  let previous: string | null = null;
  let first: string | null = null;
  for (let index = 0; index < maxStops; index++) {
    await page.keyboard.press("Tab");
    const stop = await page.evaluate(probeStop, exclude);
    if (stop === null) break; // focus left the page (browser chrome) or sits on <body>
    if (stop.excluded) continue;
    if (stop.key === first) break; // wrapped around
    first ??= stop.key;
    const problems = [...stop.problems];
    if (stop.key === previous) problems.push("focus stuck: Tab didn't move");
    previous = stop.key;
    const { key: _key, excluded: _excluded, ...rest } = stop;
    stops.push({ ...rest, index, problems });
    if (problems.includes("focus stuck: Tab didn't move")) break;
  }

  const report = stops
    .filter((s) => s.problems.length > 0)
    .map(
      (s) =>
        `#${s.index} ${s.tag}${s.role ? `[${s.role}]` : ""} "${s.name}": ${s.problems.join("; ")}`,
    );
  expect(report, "keyboard pass: stops with problems").toEqual([]);
  expect(landmarkRevisits(stops), "keyboard pass: Tab returns to a landmark it left").toEqual([]);
  return stops;
}

/** Landmarks Tab comes back to after leaving them, e.g. main → navigation → main. */
export function landmarkRevisits(stops: readonly Pick<TabStop, "landmark">[]): string[] {
  const runs: string[] = [];
  for (const { landmark } of stops) if (runs.at(-1) !== landmark) runs.push(landmark);
  return runs.filter((landmark, i) => runs.indexOf(landmark) !== i);
}
