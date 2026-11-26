import type { TabStop } from "./keyboard.ts";

export interface ProbedStop extends Omit<TabStop, "index"> {
  readonly key: string;
  readonly excluded: boolean;
}

/** Runs in the page: describes document.activeElement. Self-contained (serialised by Playwright). */
export function probeStop(exclude: readonly string[]): ProbedStop | null {
  const el = document.activeElement;
  if (!(el instanceof HTMLElement) || el === document.body) return null;

  // A region is a landmark only when it has a name (ARIA), e.g. the staged-changes bar (#928).
  const LANDMARKS =
    "main, nav, header, footer, aside, [role=main], [role=navigation], [role=banner], [role=contentinfo], [role=complementary], [role=search], [role=region][aria-label], [role=region][aria-labelledby], section[aria-label], section[aria-labelledby]";
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
      SECTION: "region",
    };
    const role = mark.getAttribute("role") ?? implicit[mark.tagName] ?? mark.tagName.toLowerCase();
    const labelledBy = mark.getAttribute("aria-labelledby");
    const name =
      mark.getAttribute("aria-label") ??
      (labelledBy
        ? labelledBy
            .split(/\s+/)
            .map((id) => text(document.getElementById(id)))
            .join(" ")
            .trim()
        : "");
    return name ? `${role} '${name}'` : role;
  };
  // Stable identity across stops: the element's path from <html>. A windowed row (#868: the kit's
  // useRowWindow) is named by its place in the whole list, not its child index, which shifts as
  // the window moves: two rows at the same child index are different stops.
  const placeOf = (n: Element): string | null =>
    n.getAttribute("data-row-index") ??
    n.getAttribute("aria-posinset") ??
    (n.tagName === "TR" ? n.getAttribute("aria-rowindex") : null);
  const keyOf = (node: Element): string => {
    const parts: string[] = [];
    for (let n: Element | null = node; n && n !== document.documentElement; n = n.parentElement) {
      const place = placeOf(n);
      parts.unshift(
        place === null
          ? `${n.tagName}:${Array.prototype.indexOf.call(n.parentElement?.children ?? [], n)}`
          : `${n.tagName}@${place}`,
      );
    }
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

  // The point to test on one axis, or null when the stop is off screen on it. A stop that fits
  // the viewport is on screen when its centre is (a link half cut off by a sideways strip is
  // not). A bigger one, like a table region taller than a phone, is on screen when part of it
  // shows, and the middle of that part is tested (#189: its centre is always below the fold).
  const onAxis = (start: number, size: number, limit: number): number | null => {
    if (size <= limit) {
      const centre = start + size / 2;
      return centre >= 0 && centre <= limit ? centre : null;
    }
    const from = Math.max(start, 0);
    const to = Math.min(start + size, limit);
    return from < to ? (from + to) / 2 : null;
  };
  const x = onAxis(rect.left, rect.width, window.innerWidth);
  const y = onAxis(rect.top, rect.height, window.innerHeight);
  if (problems.length === 0) {
    if (x === null || y === null) {
      // The geometry says where it was, e.g. a link left outside a sideways strip.
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
