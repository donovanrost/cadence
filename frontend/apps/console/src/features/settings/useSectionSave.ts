import { ref } from "vue";
import { failureOutcome } from "@/features/changes/index.ts";
import { saveSection, type SettingsScope, type SettingsSection } from "./api.ts";
import { approvalRefusal } from "./governance.ts";
import { suspensionsOf, type Suspensions } from "./suspensions.ts";

type Outcome = (version: number) => string;
/**
 * #499: a save refused because it would suspend automation grants, held until the person
 * confirms (saved again with the list's digest) or cancels. `changed`: the list moved since the
 * last confirm, so it's shown again before anything is saved.
 */
export type PendingSuspension = Readonly<{
  values: Readonly<Record<string, unknown>>;
  what: string;
  outcome: Outcome | undefined;
  suspensions: Suspensions;
  changed: boolean;
}>;

/**
 * Direct save of one settings section (201, active); U20 wording on failure, ux U96's for a refused
 * approval-setting change (#233). `missionName` words a mission-level refusal.
 */
export function useSectionSave(
  scope: () => SettingsScope,
  section: () => SettingsSection,
  onSaved: () => void,
  missionName: () => string = () => "this mission",
) {
  const busy = ref(false);
  const note = ref<{ tone: "nominal" | "caution" | "crit"; text: string } | null>(null);
  const pending = ref<PendingSuspension | null>(null);

  /** `outcome` writes the whole line from the new version (ux: a Reset names the value it had). */
  async function save(
    values: Readonly<Record<string, unknown>>,
    what = "Saved",
    outcome?: Outcome,
    acknowledged?: Suspensions,
  ) {
    if (busy.value) return;
    busy.value = true;
    try {
      const result = await saveSection(scope(), section().key, {
        values,
        expected_version: section().version?.version ?? null,
        ...(acknowledged ? { acknowledged_suspensions: acknowledged.digest } : {}),
      });
      const suspensions = result.ok ? null : suspensionsOf(result.error);
      if (suspensions) {
        // Nothing was written: show the grants it would suspend and wait for the person.
        note.value = null;
        pending.value = { values, what, outcome, suspensions, changed: acknowledged !== undefined };
        return;
      }
      pending.value = null;
      note.value = result.ok
        ? {
            tone: "nominal",
            text: outcome
              ? outcome(result.value.version)
              : `${what} as v${result.value.version}. It's active now.`,
          }
        : {
            tone: "crit",
            text:
              approvalRefusal(result.error, scope().kind, section().key, missionName()) ??
              failureOutcome(result.error, "changed").sentence,
          };
      if (result.ok) onSaved();
    } finally {
      busy.value = false;
    }
  }

  /** #499: save again with the digest of the list the person saw. */
  function confirmSuspension() {
    const p = pending.value;
    if (p) void save(p.values, p.what, p.outcome, p.suspensions);
  }
  const cancelSuspension = () => (pending.value = null);

  return { busy, note, pending, save, confirmSuspension, cancelSuspension };
}
