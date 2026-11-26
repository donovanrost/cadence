import type { MissionId } from "@/api/index.ts";
import { ref, shallowRef, type Ref } from "vue";
import type { ApiError } from "@/api";
import { compareVersions, fetchVersions, restore } from "../editor/api.ts";
import type { Saved, VersionChange, Versions } from "../editor/contracts.ts";

export type Comparison = Readonly<{
  from: number;
  to: number;
  changes: readonly VersionChange[];
  fromJson: string;
  toJson: string;
}>;

/** B6: what a screen reader hears when a compare arrives. */
export function compareSentence(c: Pick<Comparison, "from" | "to" | "changes">): string {
  const n = c.changes.length;
  const what = n === 0 ? "these versions are the same" : `${n} ${n === 1 ? "change" : "changes"}`;
  return `v${c.from} to v${c.to}: ${what}.`;
}

/**
 * The Versions sheet's reads and its one write (D12, D13). Restore makes a new current version
 * from an old one (non-destructive); a 409 means someone saved first, so the list reloads.
 */
export function useVersions(
  missionId: Readonly<Ref<MissionId>>,
  dashboardId: Readonly<Ref<string>>,
) {
  const list = shallowRef<Versions | null>(null);
  const comparison = shallowRef<Comparison | null>(null);
  const error = shallowRef<ApiError | null>(null);
  const busy = ref(false);

  async function load() {
    error.value = null;
    const result = await fetchVersions(missionId.value, dashboardId.value);
    if (result.ok) list.value = result.value;
    else error.value = result.error;
  }
  async function compare(a: number, b: number) {
    const [from, to] = a < b ? [a, b] : [b, a];
    error.value = null;
    const result = await compareVersions(missionId.value, dashboardId.value, from, to);
    if (result.ok)
      comparison.value = {
        from,
        to,
        changes: result.value.changes,
        fromJson: result.value.from_json,
        toJson: result.value.to_json,
      };
    else error.value = result.error;
  }
  async function restoreVersion(version: number): Promise<Saved | null> {
    const current = list.value?.current_version;
    if (current === undefined || busy.value) return null;
    busy.value = true;
    try {
      const result = await restore(missionId.value, dashboardId.value, version, current);
      comparison.value = null;
      await load();
      if (result.ok) return result.value;
      error.value = result.error;
      return null;
    } finally {
      busy.value = false;
    }
  }
  return { list, comparison, error, busy, load, compare, restoreVersion };
}
