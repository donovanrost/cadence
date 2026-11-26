import { expect, type Page } from "@playwright/test";

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

interface ProbedStop extends Omit<TabStop, "index"> {
  readonly key: string;
  readonly excluded: boolean;
}

/** Runs in the page: describes document.activeElement. Self-contained (serialised by Playwright). */
function probeStop(exclude: readonly string[]): ProbedStop | null {
  const el = document.activeElement;
  if (!(el instanceof HTMLElement) || el === document.body) return null;

  const LANDMARKS =
    "main, nav, header, footer, aside, [role=main], [role=navigation], [role=banner], [role=contentinfo], [role=complementary], [role=search]";
  const text = (node: Element | null) => (node?.textContent ?? "").replace(/\s+/g, " ").trim();
  const nameOf = (node: Element): string => {
    const labelledBy = node.getAttribute("aria-labelledby");
    if (labelledBy)
      return labelledBy
        .split(/\s+/)
        .map((id) => text(document.getElementById(id)))
        .join(" ")
        .trim();
    const label = node.getAttribute("aria-label");
    if (label) return label.trim();
    if (
      node instanceof HTMLInputElement ||
      node instanceof HTMLSelectElement ||
      node instanceof HTMLTextAreaElement
    )
      return text(node.labels?.[0] ?? null) || node.getAttribute("placeholder") || "";
    return text(node).slice(0, 80) || node.getAttribute("title") || "";
  };
  // The outermost landmark: a <header> or <aside> inside <main> belongs to main's run.
  const landmarkOf = (node: Element): string => {
    let mark: Element | null = null;
    for (let n = node.closest(LANDMARKS); n; n = n.parentElement?.closest(LANDMARKS) ?? null)
      mark = n;
    if (!mark) return "";
    const implicit: Record<string, string> = {
      HEADER: "banner",
      FOOTER: "contentinfo",
      NAV: "navigation",
      MAIN: "main",
      ASIDE: "complementary",
    };
    const role = mark.getAttribute("role") ?? implicit[mark.tagName] ?? mark.tagName.toLowerCase();
    const name = mark.getAttribute("aria-label") ?? "";
    return name ? `${role} '${name}'` : role;
  };
  // Stable identity across stops: the element's path from <html>.
  const keyOf = (node: Element): string => {
    const parts: string[] = [];
    for (let n: Element | null = node; n && n !== document.documentElement; n = n.parentElement)
      parts.unshift(
        `${n.tagName}:${Array.prototype.indexOf.call(n.parentElement?.children ?? [], n)}`,
      );
    return parts.join("/");
  };

  const problems: string[] = [];
  const rect = el.getBoundingClientRect();
  const style = getComputedStyle(el);
  if (
    rect.width === 0 ||
    rect.height === 0 ||
    style.visibility === "hidden" ||
    style.display === "none"
  )
    problems.push("invisible stop");
  if (el.closest('[aria-hidden="true"]')) problems.push("stop inside aria-hidden");

  const x = rect.left + rect.width / 2;
  const y = rect.top + rect.height / 2;
  if (problems.length === 0) {
    if (x < 0 || y < 0 || x > window.innerWidth || y > window.innerHeight) {
      // The geometry says which way it left: a tall stop's centre below the fold, or a link
      // left outside a sideways strip (#189 sweep).
      const box = `${Math.round(rect.left)},${Math.round(rect.top)} ${Math.round(rect.width)}×${Math.round(rect.height)}`;
      problems.push(
        `off screen when focused (at ${box} in ${window.innerWidth}×${window.innerHeight})`,
      );
    } else {
      const top = document.elementFromPoint(x, y);
      // An excluded overlay (the dev-only toolbar) isn't in production, so it doesn't count.
      const excludedCover = top !== null && exclude.some((s) => top.closest(s) !== null);
      if (top && !excludedCover && top !== el && !el.contains(top) && !top.contains(el))
        problems.push(`covered by ${top.tagName.toLowerCase()} "${nameOf(top).slice(0, 40)}"`);
    }
  }

  // A focus indicator: an outline or box-shadow on the stop or a :focus-within ancestor, or the
  // kit's designed focus style (a focus / focus-visible / focus-within utility) on the stop or a
  // wrapper up to three levels out (kit inputs change their wrapper's border, qa run 2).
  const drawn = (node: Element) => {
    const s = getComputedStyle(node);
    const outline =
      s.outlineStyle !== "none" &&
      parseFloat(s.outlineWidth) > 0 &&
      s.outlineColor !== "rgba(0, 0, 0, 0)";
    return outline || (s.boxShadow !== "none" && s.boxShadow !== "");
  };
  const designed = (node: Element) =>
    Array.from(node.classList).some((c) => /(^|:)(focus|focus-visible|focus-within):/.test(c));
  let shown = drawn(el) || designed(el);
  for (let n = el.parentElement, up = 0; n && up < 3 && !shown; n = n.parentElement, up++)
    shown = (n.matches(":focus-within") && drawn(n)) || designed(n);
  if (!shown) problems.push("no focus indicator");

  return {
    key: keyOf(el),
    excluded: exclude.some((selector) => el.closest(selector) !== null),
    tag: el.tagName.toLowerCase(),
    role: el.getAttribute("role"),
    name: nameOf(el),
    landmark: landmarkOf(el),
    problems,
  };
}
