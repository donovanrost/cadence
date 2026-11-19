import AxeBuilder from "@axe-core/playwright";
import { expect, type Page } from "@playwright/test";

interface AccessibilityOptions {
  /** CSS selectors to leave out, e.g. a third-party canvas. Prefer fixing over excluding. */
  readonly exclude?: readonly string[];
}

/**
 * Runs axe against the current page for WCAG 2.x A/AA (includes 4.5:1 text contrast).
 * Call after the screen has rendered real data, not while it is still loading.
 */
export async function expectAccessible(
  page: Page,
  options: AccessibilityOptions = {},
): Promise<void> {
  let builder = new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]);
  for (const selector of options.exclude ?? []) builder = builder.exclude(selector);
  const { violations } = await builder.analyze();
  const summary = violations.map((violation) => ({
    rule: violation.id,
    impact: violation.impact,
    help: violation.help,
    targets: violation.nodes.slice(0, 5).map((node) => node.target.join(" ")),
  }));
  expect(summary, "axe WCAG A/AA violations").toEqual([]);
}
