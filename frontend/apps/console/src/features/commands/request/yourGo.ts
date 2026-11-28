import type { MissionId } from "@/api/index.ts";
import { computed, type Ref } from "vue";
import { useRemoteQuery, type ApiResult } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { formatClock, formatCount, formatRelative, plural } from "@/ui";
import { fetchGroups, type Preflight } from "../groups/api.ts";
import { goHoldReason } from "../groups/checks.ts";
import { fetchAllEvents, fetchTargetsPage } from "../groups/pages.ts";
import { fetchGroup, fetchReview, type Group, type GroupEvent } from "../groups/show.ts";
import type { PersonName } from "../groups/words.ts";
import { cannotDecide, noGoAfter } from "./decision.ts";

/**
 * Mobile.md §3 "Your GO is requested" on the paged alarm view: the oldest request awaiting the
 * viewer's GO that targets this spacecraft, with its re-check. The list rows don't carry targets,
 * so up to MAX_LOOKED of the awaiting requests are asked whether they target it (#795: a targets
 * page searched by the spacecraft's id, never the whole request).
 */
const MAX_LOOKED = 5;

export async function requestFor(
  missionId: MissionId,
  spacecraftId: string,
  signal?: AbortSignal,
): Promise<ApiResult<Group | null>> {
  const rows = await fetchGroups(missionId, { awaitingMe: true }, signal);
  if (!rows.ok) return rows;
  const oldest = [...rows.value]
    .filter((r) => r.state === "approval_pending")
    .sort((a, b) => Date.parse(a.requested_at) - Date.parse(b.requested_at))
    .slice(0, MAX_LOOKED);
  for (const row of oldest) {
    // q is a substring match, so the page is checked for this exact id.
    const hit = await fetchTargetsPage(
      { missionId, groupId: row.id, q: spacecraftId, limit: 100 },
      null,
      signal ?? new AbortController().signal,
    );
    if (!hit.ok) return hit;
    if (!hit.value.items.some((t) => t.spacecraft_id === spacecraftId)) continue;
    const g = await fetchGroup(missionId, row.id, signal);
    return g.ok ? { ok: true, value: g.value } : g;
  }
  return { ok: true, value: null };
}

export function useYourGo(missionId: Ref<MissionId>, spacecraftId: Ref<string | null>) {
  const found = useRemoteQuery(
    // A typed key (§12 A4; useRemoteQuery compares by value), so the MissionId stays one.
    computed(() => (spacecraftId.value ? { m: missionId.value, sc: spacecraftId.value } : null)),
    (k, signal) => requestFor(k.m, k.sc, signal),
  );
  const group = computed(() =>
    found.state.value.status === "ready" ? found.state.value.value : null,
  );
  const review = useRemoteQuery(
    computed(() => (group.value ? { m: missionId.value, id: group.value.id } : null)),
    (k, signal) => fetchReview(k.m, k.id, signal),
  );
  /** #795: the HOLD acknowledgements, read on their own (written at submit, so the oldest). */
  const holds = useRemoteQuery(
    computed(() => (group.value ? { missionId: missionId.value, groupId: group.value.id } : null)),
    (k, signal) => fetchAllEvents({ ...k, kinds: ["hold_acknowledged"] }, signal),
  );
  const refetch = () => {
    found.refetch();
    review.refetch();
    holds.refetch();
  };
  useMissionInvalidation(missionId, ["commanding"], refetch);
  return { group, review, holds, refetch };
}

/**
 * ux #237, lead's ruling: a target with no name doesn't block GO. The caution says how many, and
 * Technical details keeps their exact ids (U25: ids live there, never in place of a name).
 */
export function namelessTargets(
  group: Group,
): Readonly<{ line: string; ids: readonly string[] }> | null {
  const ids = group.targets.flatMap((t) => (t.name ? [] : [t.spacecraft_id]));
  const n = ids.length;
  if (n === 0) return null;
  // #795: the read carries the first targets only; say so rather than count past them.
  const among =
    group.targets.length < group.targets_page.total
      ? ` among the first ${formatCount(group.targets.length)}`
      : "";
  return {
    line: `This console can't show the name of ${n} target spacecraft${among}. Check ${n === 1 ? "its id" : "their ids"} in Technical details before you give GO.`,
    ids,
  };
}

/** "Low power safe · 4 spacecraft", "Mira K. · T+12m", the release sentence and the stack lines. */
export function yourGoWords(group: Group, nameOf: PersonName, now: Date) {
  const nb = group.release?.not_before;
  return {
    // U102 (ux 11-20): never "SC"; "spacecraft" reads the same in the singular and the plural.
    // ux on #580: the count takes its thousands separator ("1,200 spacecraft").
    title: `${group.title} · ${formatCount(group.target_count)} spacecraft`,
    by: `${nameOf(group.requested_by.user_id)} · ${formatRelative(new Date(group.requested_at), now)}`,
    release: nb
      ? `Held until ${formatClock(new Date(nb))}Z, then each target at its next AOS.`
      : "Each target at its next AOS.",
    stack: [...group.commands]
      .sort((a, b) => a.position - b.position)
      .map(
        (c) =>
          `${String(c.position + 1).padStart(2, "0")} ${c.name ?? c.command_id}${
            c.argument_values_json.trim() === "{}" ? "" : ` ${c.argument_values_json}`
          }`,
      ),
    confirm: `Sign GO for ${plural(group.target_count, "target")} and ${plural(group.member_count, "uplink")}?`,
  };
}

/**
 * Why GO can't be signed from the phone, in words; null when it can. A HOLD that needs the
 * approver's note or a NO-GO the re-check found sends you to the full review instead.
 */
export function phoneGoBlocked(
  group: Group,
  review: Preflight | null,
  holds: readonly GroupEvent[] | null,
  viewerId: string,
  canApprove: boolean,
  nameOf: PersonName,
): string | null {
  const who = cannotDecide(group, viewerId, canApprove, nameOf);
  if (who) return who;
  if (!review || !holds) return "Re-checking before GO…";
  const name = (id: string) =>
    group.targets.find((t) => t.spacecraft_id === id)?.name ?? "Unknown spacecraft";
  return noGoAfter(review, new Set()) ?? goHoldReason(review, holds, {}, name);
}
