import { computed, watch, type Ref } from "vue";
import { useRouter } from "vue-router";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import type { NextContact } from "../groups/api.ts";
import { noGoReason, reasonWord } from "../groups/checks.ts";
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
}>;

/**
 * Compose's request: the draft, its server preflight, what blocks the commit (in words), and the
 * submit. The commit opens only when the checks on screen answer this exact draft with no NO-GO.
 */
export function useComposeRequest(
  missionId: Ref<string>,
  fleet: Ref<readonly FleetSpacecraft[]>,
  targets: Ref<readonly FleetSpacecraft[]>,
  query: Ref<TargetQuery>,
  stack: Ref<readonly StackItem[]>,
  form: ComposeForm,
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
          approver: form.approver.value,
          sentBackFrom: form.sentBackFrom.value,
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

  const blocked = computed(() => {
    if (targets.value.length === 0) return "Add at least one target.";
    if (stack.value.length === 0) return "Add a command from the catalog.";
    if (stack.value.some((i) => !checkItem(i).ok)) return "Fix the highlighted argument values.";
    if (!form.title.value.trim()) return "Give the request a title.";
    if (secondGo.value.length && !form.log.value.trim())
      return "Write a log entry: a second GO needs one.";
    if (form.release.value.mode === "not_before" && form.release.value.notBefore === null)
      return "Pick the hold-until time.";
    if (preflight.checking.value) return "Waiting for the server's checks.";
    const pf = preflight.current.value;
    if (!pf) return "The server's checks didn't run. Check again in C3.";
    const noGo = noGoReason(pf, nameOf);
    if (noGo) return noGo;
    if (!pf.digest) return "The server's checks didn't return a digest. Check again in C3.";
    return null;
  });

  const submission = useSubmit(missionId, preflight.refetch);
  watch(
    () => (draft.value ? JSON.stringify(draft.value) : null),
    () => submission.reset(),
  );
  watch(submission.state, (s) => {
    if (s.status === "done")
      router
        .push({ name: "ops.commands.request", params: { requestId: s.groupId } })
        .catch((e: unknown) => console.error("Navigation failed", e));
  });
  function send() {
    const d = draft.value;
    const digest = preflight.current.value?.digest;
    if (blocked.value !== null || !d || !digest) return;
    submission.submit(d, digest).catch((e: unknown) => console.error("Submit failed", e));
  }
  const check = () => submission.check().catch((e: unknown) => console.error("Check failed", e));

  return { draft, preflight, nameOf, contacts, secondGo, blocked, submission, send, check };
}
