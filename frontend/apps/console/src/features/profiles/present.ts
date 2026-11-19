import { formatShort, plural } from "@/ui";
import type { ProfileDetail } from "./detail.ts";

/** "500 spacecraft inherit this profile · 3 on older versions · catalog set per spacecraft · v1 · 11-08 21:54Z" */
export function profileSubline(detail: ProfileDetail): string {
  const parts = [
    `${plural(detail.inherit_count, "spacecraft", "spacecraft")} inherit this profile`,
    detail.on_older_versions > 0 ? `${detail.on_older_versions} on older versions` : null,
    detail.routing_model === "profile" || detail.override_count > 0
      ? plural(detail.override_count, "override")
      : null,
    detail.profile.catalog_revision
      ? `catalog rev ${detail.profile.catalog_revision.number}`
      : "catalog set per spacecraft",
  ];
  const last = detail.profile.last_change;
  if (last) {
    const by = last.actor?.name ? ` by ${last.actor.name}` : "";
    parts.push(
      last.revision !== null
        ? `last changed in r${last.revision}`
        : `v${last.version} · ${formatShort(new Date(last.at))}${by}`,
    );
  }
  return parts.filter((p): p is string => p !== null).join(" · ");
}

/** domain (catalog generations): what applying a generation field does, from an operator's view. */
export const generationNote =
  "From the moment it applies, telemetry decodes and commands build with the new value. Commands still waiting to release are canceled; commands in flight hold the apply until they finish. Nothing restarts and no link drops. Derived values and limit timers start fresh.";
