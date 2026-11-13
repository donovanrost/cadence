import { computed, type Ref } from "vue";
import { useRemoteQuery, type ApiResult } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { formatClock, formatRelative, plural } from "@/ui";
import { fetchGroups, type Preflight } from "../groups/api.ts";
import { goHoldReason } from "../groups/checks.ts";
import { fetchGroup, fetchReview, type Group } from "../groups/show.ts";
import type { PersonName } from "../groups/words.ts";
import { cannotDecide, noGoAfter } from "./decision.ts";

/**
 * Mobile.md §3 "Your GO is requested" on the paged alarm view: the oldest request awaiting the
 * viewer's GO that targets this spacecraft, with its re-check. The list rows don't carry targets,
 * so up to MAX_LOOKED of the awaiting requests are read whole.
 */
const MAX_LOOKED = 5;

export async function requestFor(
  missionId: string,
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
    const g = await fetchGroup(missionId, row.id, signal);
    if (!g.ok) return g;
    if (g.value.targets.some((t) => t.spacecraft_id === spacecraftId))
      return { ok: true, value: g.value };
  }
  return { ok: true, value: null };
}

export function useYourGo(missionId: Ref<string>, spacecraftId: Ref<string | null>) {
  const found = useRemoteQuery(
    computed(() => (spacecraftId.value ? `${missionId.value}|${spacecraftId.value}` : null)),
    (k, signal) => {
      const [m = "", sc = ""] = k.split("|");
      return requestFor(m, sc, signal);
    },
  );
  const group = computed(() =>
    found.state.value.status === "ready" ? found.state.value.value : null,
  );
  const review = useRemoteQuery(
    computed(() => (group.value ? `${missionId.value}|${group.value.id}` : null)),
    (k, signal) => {
      const [m = "", id = ""] = k.split("|");
      return fetchReview(m, id, signal);
    },
  );
  const refetch = () => {
    found.refetch();
    review.refetch();
  };
  useMissionInvalidation(missionId, ["commanding"], refetch);
  return { group, review, refetch };
}

/** "Low power safe · 4 SC", "Mira K. · T+12m", the release sentence and the stack lines. */
export function yourGoWords(group: Group, nameOf: PersonName, now: Date) {
  const nb = group.release?.not_before;
  return {
    title: `${group.title} · ${group.target_count} SC`,
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
  viewerId: string,
  canApprove: boolean,
  nameOf: PersonName,
): string | null {
  const who = cannotDecide(group, viewerId, canApprove, nameOf);
  if (who) return who;
  if (!review) return "Re-checking before GO…";
  const name = (id: string) => group.targets.find((t) => t.spacecraft_id === id)?.name ?? id;
  return noGoAfter(review, new Set()) ?? goHoldReason(review, group.events, {}, name);
}
