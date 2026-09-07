import type { InjectionKey } from "vue";

export const pageRegions = ["eyebrow", "title", "description", "metadata", "actions"] as const;
export type PageRegion = (typeof pageRegions)[number];
export interface PageBreadcrumb {
  label: string;
  href?: string | null;
  id?: string;
}
export interface PageHeadingContent {
  id?: string;
  breadcrumbs?: readonly PageBreadcrumb[];
  regions: readonly PageRegion[];
}
/** One host-owned header per routed page. Slots retain the remote's Vue ownership. */
export interface PageChrome {
  targets: Partial<Record<PageRegion, HTMLElement | null>>;
  publish(owner: symbol, content: PageHeadingContent): void;
  release(owner: symbol): void;
}
// Stable across independently built federated modules; no shared mutable singleton.
export const pageChromeKey = Symbol.for("cadence.page-chrome.v1") as InjectionKey<PageChrome>;

/** Boundary adapter for older Phoenix presentation DTOs. Styling stays in Vue. */
export function presentationBreadcrumbs(value?: {
  items: readonly {
    link?: { text: string; attrs: Record<string, string> } | null;
    current?: { text: string; attrs: Record<string, string> } | null;
  }[];
}): PageBreadcrumb[] {
  return (
    value?.items.flatMap((item) => {
      const entry = item.link ?? item.current;
      return entry ? [{ label: entry.text, href: item.link?.attrs.href, id: entry.attrs.id }] : [];
    }) ?? []
  );
}

/** Preserve page identity and behavior while retiring server-owned page geometry. */
export function pageContentAttrs(attrs: Record<string, string>): Record<string, string> {
  const { class: _class, style: _style, ...identity } = attrs;
  return { ...identity, class: "cd-page-content" };
}
