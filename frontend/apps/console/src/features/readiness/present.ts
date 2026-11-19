import type { RouteLocationRaw } from "vue-router";
import { formatCount, formatShort, plural } from "@/ui";
import type { OpState } from "@/ui";
import type { AreaKey, AreaStatus, FindingFix, Readiness, Severity } from "./api.ts";

/** Severity grammar (ux U3): blocker = crit diamond, optional = gray dash. */
export function severityState(severity: Severity): OpState {
  switch (severity) {
    case "blocker":
      return "crit";
    case "caution":
      return "caution";
    case "stale":
      return "stale";
    case "not_set_up":
      return "off";
    case "optional":
      return "optional";
  }
}

/** The word that leads a finding's title, so severity isn't only its mark (a11y B2). */
export function severityWord(severity: Severity): string {
  switch (severity) {
    case "blocker":
      return "Blocker";
    case "caution":
      return "Caution";
    case "stale":
      return "Stale";
    case "not_set_up":
      return "Not set up";
    case "optional":
      return "Optional";
  }
}

export function areaState(status: AreaStatus): OpState {
  switch (status) {
    case "ready":
      return "nominal";
    case "blocker":
      return "crit";
    case "caution":
      return "caution";
    case "stale":
      return "stale";
    case "not_set_up":
    case "unknown":
      return "off";
  }
}

export function areaWord(status: AreaStatus): string {
  switch (status) {
    case "ready":
      return "Ready";
    case "blocker":
      return "Blocker";
    case "caution":
      return "Caution";
    case "stale":
      return "Stale";
    case "not_set_up":
      return "Not set up";
    case "unknown":
      return "Unknown";
  }
}

export function areaName(key: AreaKey): string {
  switch (key) {
    case "fleet":
      return "Fleet";
    case "catalog":
      return "Catalog";
    case "comms":
      return "Comms & routing";
    case "stations":
      return "Ground stations";
    case "data_sources":
      return "Data sources";
    case "apps":
      return "Apps";
  }
}

export function areaRoute(key: AreaKey): RouteLocationRaw {
  switch (key) {
    case "fleet":
      return { name: "setup.spacecraft" };
    case "catalog":
      return { name: "setup.catalog" };
    case "comms":
      return { name: "setup.comms" };
    case "stations":
      return { name: "setup.stations" };
    case "data_sources":
      return { name: "setup.data-sources" };
    case "apps":
      return { name: "setup.apps" };
  }
}

export type FixLink = Readonly<{ label: string; to: RouteLocationRaw }>;

/**
 * The one action a finding offers: verb + object, or the server's label when it has a better one.
 * An app that isn't set up offers "Install" (ux review 2026-11-08).
 */
export function fixLink(fix: FindingFix, severity: Severity): FixLink {
  const link = ((): FixLink => {
    switch (fix.kind) {
      case "spacecraft_list":
        return { label: "Open spacecraft", to: { name: "setup.spacecraft" } };
      case "spacecraft_new":
        return { label: "Add spacecraft", to: { name: "setup.spacecraft.new" } };
      case "catalog":
        return { label: "Open catalog", to: { name: "setup.catalog" } };
      case "catalog_import":
        return { label: "Import catalog", to: { name: "setup.catalog.import" } };
      case "comms":
        return { label: "Open routing", to: { name: "setup.comms" } };
      case "contact_planning":
        return { label: "Set up contact planning", to: { name: "setup.contact-planning" } };
      case "change_set":
        return { label: "Open changes", to: { name: "setup.changes" } };
      case "spacecraft":
        return {
          label: "Open spacecraft",
          to: { name: "setup.spacecraft.one", params: { spacecraftId: fix.id } },
        };
      case "profile":
        return {
          label: "Open profile",
          to: { name: "setup.profile", params: { profileId: fix.id } },
        };
      case "station":
        return fix.id === null
          ? { label: "Open Ground stations", to: { name: "setup.stations" } }
          : {
              label: "Open station",
              to: { name: "setup.stations", params: { stationId: fix.id } },
            };
      case "data_source":
        return fix.id === null
          ? { label: "Open Data sources", to: { name: "setup.data-sources" } }
          : {
              label: "Open source",
              to: { name: "setup.data-sources", params: { sourceId: fix.id } },
            };
      case "app":
        return {
          label: severity === "not_set_up" || severity === "optional" ? "Install" : "Open app",
          to:
            severity === "not_set_up" || severity === "optional"
              ? { name: "setup.apps" }
              : { name: "setup.app", params: { appKey: fix.id } },
        };
    }
  })();
  return fix.label ? { ...link, label: fix.label } : link;
}

/** The h1: blockers only (U3). */
export function verdictTitle(readiness: Readiness): string {
  const blockers = readiness.verdict.blocker;
  return blockers === 0 ? "Ready for operations" : plural(blockers, "blocker");
}

/** "Block 1 framing … · 11-08 02:29Z by Donovan R." for the subline, when a change feed exists. */
export function latestChangeLine(readiness: Readiness): string | null {
  const latest = readiness.recentChanges?.[0];
  if (!latest) return null;
  const by = latest.actorName ? ` by ${latest.actorName}` : "";
  return `${latest.summary} · ${formatShort(new Date(latest.at))}${by}`;
}

/** Subline: counts of the other severities (zeros omitted), then the latest change. */
export function verdictSubline(readiness: Readiness): string | null {
  const parts = [verdictSummary(readiness), latestChangeLine(readiness)].filter(
    (part): part is string => part !== null,
  );
  return parts.length > 0 ? parts.join(" · ") : null;
}

/** Counts of the other severities, omitting zeros: "3 suggestions, 1 caution". */
export function verdictSummary(readiness: Readiness): string | null {
  const v = readiness.verdict;
  const parts = [
    v.caution > 0 ? plural(v.caution, "caution") : null,
    v.stale > 0 ? `${v.stale} stale` : null,
    v.not_set_up > 0 ? `${v.not_set_up} not set up` : null,
    v.optional > 0 ? plural(v.optional, "suggestion") : null,
  ].filter((part): part is string => part !== null);
  return parts.length > 0 ? parts.join(", ") : null;
}

/** Findings in the U3 severity order, stable within a severity. */
export function orderedFindings(readiness: Readiness) {
  const rank: Record<Severity, number> = {
    blocker: 0,
    caution: 1,
    stale: 2,
    not_set_up: 3,
    optional: 4,
  };
  return [...readiness.findings].sort((a, b) => rank[a.severity] - rank[b.severity]);
}

/**
 * R1's meta: "Grouped by cause · 3,006 findings → 4 lines" when grouping collapsed something
 * (ux #317: findings, never items), else "Grouped by cause · 4 lines".
 */
export function groupedMeta(affected: number, lines: number): string {
  const l = plural(lines, "line");
  return affected > lines
    ? `Grouped by cause · ${formatCount(affected)} findings → ${l}`
    : `Grouped by cause · ${l}`;
}
