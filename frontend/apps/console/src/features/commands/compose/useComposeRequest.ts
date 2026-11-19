import type { MissionId } from "@/api/index.ts";
import { expiryProblem } from "../priority.ts";
import { computed, ref, watch, type Ref } from "vue";
import { useRouter } from "vue-router";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import type { Draft, NextContact, Preflight } from "../groups/api.ts";
import {
  holdAcksToSend,
  holdReason,
  noGoReason,
  reasonWord,
  type HoldAcks,
} from "../groups/checks.ts";
import { buildDraft, type Release } from "./draft.ts";
import { checkItem, secondGoReasons, type StackItem } from "./stack.ts";
import { FLEET_REACH, type TargetQuery } from "./targets.ts";
import { usePreflight } from "./usePreflight.ts";
import { useSubmit } from "./useSubmit.ts";

export type ComposeForm = Readonly<{
  title: Ref<string>;
  log: Ref<string>;
  release: Ref<Release>;
  approver: Ref<string>;
  /** The sent-back group this resends (DECISIONS #31 (4)), else null. */
  sentBackFrom: Ref<string | null>;
  endpoints: Ref<Record<string, string>>;
}>;

/**
 * Compose's request: the draft, its server preflight, what blocks the commit (in words), and the
 * submit. The commit opens only when the checks on screen answer this exact draft with no NO-GO.
 */
export function useComposeRequest(
  missionId: Ref<MissionId>,
  fleet: Ref<readonly FleetSpacecraft[]>,
  targets: Ref<readonly FleetSpacecraft[]>,
  query: Ref<TargetQuery>,
  stack: Ref<readonly StackItem[]>,
  form: ComposeForm,
  /** Autosave's submit hooks: freeze returns the draft revision to delete with the group. */
  saved: Readonly<{ freeze: () => Promise<number | null>; thaw: () => void }>,
) {
  const router = useRouter();
  const draft = computed(() =>
    targets.value.length && stack.value.length
      ? buildDraft({
          title: form.title.value,
          log: form.log.value,
          targets: targets.value,
          query: query.value,
          stack: stack.value,
          notBefore: form.release.value.mode === "not_before" ? form.release.value.notBefore : null,
          expiresAt: form.release.value.expiresAt,
          priority: form.release.value.priority,
          approver: form.approver.value,
          sentBackFrom: form.sentBackFrom.value,
          endpoints: form.endpoints.value,
        })
      : null,
  );
  const preflight = usePreflight(missionId, draft);

  const nameOf = (id: string) => {
    const sc = fleet.value.find((r) => r.id === id);
    if (sc) return `${sc.name} (SCID ${sc.scid})`;
    const t = preflight.current.value?.targets.find((r) => r.spacecraft_id === id);
    if (!t?.name) return "Unknown spacecraft";
    return t.scid === null ? t.name : `${t.name} (SCID ${t.scid})`;
  };
  const contacts = computed(() => {
    const check = preflight.current.value?.checks.find((c) => c.key === "contact");
    if (!check) return null;
    return new Map<string, NextContact | null>(
      check.per_target.map((t) => [t.spacecraft_id, t.next_contact ?? null]),
    );
  });
  /** The server's two-person reasons once it answers; the catalog's estimate until then. */
  const secondGo = computed(() => {
    const check = preflight.current.value?.checks.find((c) => c.key === "two_person");
    if (check) return check.result === "go" ? [] : (check.evidence.reasons ?? []).map(reasonWord);
    return secondGoReasons(stack.value, targets.value.length, FLEET_REACH);
  });

  /** #60: the operator's HOLD acks, each stamped with the hold_basis it was written against. */
  const acks = ref<HoldAcks>({});
  function ack(key: string, basis: string | null, note: string) {
    acks.value = { ...acks.value, [key]: { basis, note } };
  }

  const blocked = computed(() => {
    if (targets.value.length === 0) return "Add at least one target.";
    if (stack.value.length === 0) return "Add a command from the catalog.";
    const ids = targets.value.map((t) => t.id);
    if (stack.value.some((i) => !checkItem(i, ids).ok))
      return "Fix the highlighted argument values.";
    if (!form.title.value.trim()) return "Give the request a title.";
    if (secondGo.value.length && !form.log.value.trim())
      return "Write a log entry: a second GO needs one.";
    if (form.release.value.mode === "not_before" && form.release.value.notBefore === null)
      return "Pick the hold-until time.";
    const expiry = expiryProblem(
      form.release.value.expiresAt,
      form.release.value.mode === "not_before" ? form.release.value.notBefore : null,
      Date.now(),
    );
    if (expiry) return expiry;
    if (preflight.checking.value) return "Waiting for the server's checks.";
    const pf = preflight.current.value;
    if (!pf) return "The server's checks didn't run. Check again in C3.";
    const noGo = noGoReason(pf, nameOf);
    if (noGo) return noGo;
    const hold = holdReason(pf, acks.value, nameOf);
    if (hold) return hold;
    if (!pf.digest) return "The server's checks didn't return a digest. Check again in C3.";
    return null;
  });

  const submission = useSubmit(missionId, preflight.refetch);
  watch(
    () => (draft.value ? JSON.stringify(draft.value) : null),
    () => submission.reset(),
  );
  watch(submission.state, (s) => {
    // Rejected (also after a check): nothing was created, so autosave picks up again. Unclear
    // stays frozen until the check answers.
    if (s.status === "rejected") saved.thaw();
    if (s.status === "done")
      router
        .push({ name: "ops.commands.request", params: { requestId: s.groupId } })
        .catch((e: unknown) => console.error("Navigation failed", e));
  });
  async function submitNow(d: Draft, pf: Preflight, digest: string) {
    const revision = await saved.freeze();
    await submission.submit(d, digest, holdAcksToSend(pf, acks.value), revision);
  }
  function send() {
    const d = draft.value;
    const pf = preflight.current.value;
    const digest = pf?.digest;
    if (blocked.value !== null || !d || !pf || !digest) return;
    submitNow(d, pf, digest).catch((e: unknown) => console.error("Submit failed", e));
  }
  const check = () => submission.check().catch((e: unknown) => console.error("Check failed", e));

  return {
    draft,
    preflight,
    nameOf,
    contacts,
    secondGo,
    acks,
    ack,
    blocked,
    submission,
    send,
    check,
  };
}
