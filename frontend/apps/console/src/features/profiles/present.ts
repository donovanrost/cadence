import { formatShort, plural } from "@/ui";
import type { ProfileDetail } from "./detail.ts";

/** "500 spacecraft inherit this profile · 3 on older versions · catalog set per spacecraft · v1 · 11-08 21:54Z" */
export function profileSubline(detail: ProfileDetail): string {
  const parts = [
    `${plural(detail.inherit_count, "spacecraft", "spacecraft")} inherit this profile`,
    detail.on_older_versions > 0 ? `${detail.on_older_versions} on older versions` : null,
    detail.routing_model === "profile" ? plural(detail.override_count, "override") : null,
    detail.profile.catalog_revision
      ? `catalog rev ${detail.profile.catalog_revision.number}`
      : "catalog set per spacecraft",
  ];
  const last = detail.profile.last_change;
  if (last) {
    const by = last.actor ? ` by ${last.actor.name}` : "";
    parts.push(
      last.revision !== null
        ? `last changed in r${last.revision}`
        : `v${last.version} · ${formatShort(new Date(last.at))}${by}`,
    );
  }
  return parts.filter((p): p is string => p !== null).join(" · ");
}
