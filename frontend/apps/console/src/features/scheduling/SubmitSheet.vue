<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { decoders as d, detailsOf, isError, type ApiError, type Reader } from "@/api";
import { ApButton, ApCallout, ApSheet, ApTextarea, plural } from "@/ui";
import {
  reasonText,
  REASON_MAX,
  REASON_MIN,
  stationCode,
  type Acknowledgement,
  type PlanDetail,
} from "./api.ts";
import type { ReviewAct } from "./review-run.ts";
import { approveRefusal, submitRefusalText } from "./review-words.ts";
import { lifecycleRefusal, planOfDayRoute } from "./lifecycle.ts";
import { contactsShortText, coverage, gapGroups } from "./coverage.ts";
import type { SpacecraftName } from "./names.ts";

/**
 * Accept-gaps sheet (ScheduleFlow K1, DECISIONS #28, U23 amended): one row per uncovered
 * spacecraft with its unmet requirements; one reason per spacecraft, sent as the acknowledgement for
 * each of its requirements (the audit stays per requirement); a disclosure allows a different
 * reason per requirement. Also the confirm step when nothing is unmet.
 */
const props = defineProps<{
  plan: PlanDetail;
  nameOf: (id: string | null) => SpacecraftName | null;
  commitLabel: string;
  /** The act, without the count (U36); a sheet with gaps titles itself by them instead. */
  title: string;
  confirm: string;
  busy: boolean;
  /** The day on screen, for a U61 refusal's Open (K1's `?plan=`). */
  day?: string | undefined;
  /** #257 (U97): what the commit does, for its refusal words; the viewer, for "you already …". */
  act?: ReviewAct | undefined;
  userId: string;
  /** ux: a note typed for an approve that was refused, put back for the retry when the field is empty. */
  keptNote?: string | null | undefined;
}>();
const emit = defineEmits<{ submit: [acks: Acknowledgement[], note?: string]; close: [] }>();
/** U36: resubmitting a sent-back draft prefills the previous reasons. */
const again = computed(() => props.plan.approval?.decision === "rejected");
/** U76: an optional note for the record on every Submit and Approve (one cap, 2,000; api). */
const note = ref("");
const NOTE_MAX = 2000;
const noteError = computed(() =>
  note.value.trim().length > NOTE_MAX ? "Keep the note under 2,000 characters." : null,
);
/** U76 (as U65's reasons): a counter from 1,800 characters, else the hint. */
const noteHint = computed(() =>
  note.value.length >= 1800
    ? `${note.value.length.toLocaleString("en-US")} / ${NOTE_MAX.toLocaleString("en-US")}`
    : "Saved with your name in the plan's history.",
);
const error = defineModel<ApiError | null>("error", { default: null });

const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const groups = computed(() => gapGroups(props.plan.unmet));
const keyOf = (id: string | null) => id ?? "—";
/** Reason per spacecraft group, and optional overrides per requirement. */
const reasons = ref<Record<string, string>>({});
const overrides = ref<Record<string, string>>({});
const split = ref<Record<string, boolean>>({});
/** "Same reason for all" (qa #27): one shared reason replaces every per-spacecraft box. */
const sameForAll = ref(false);
const shared = ref("");
const rules = computed(() => new Map(props.plan.demand.rules.map((r) => [r.requirement_id, r])));
/** `11 NOV 00:00–06:00Z · ≥ 1 contact`: each occurrence's window tells identical rules apart (ux #9). */
function requirementLine(requirementId: string): string {
  const r = rules.value.get(requirementId);
  if (!r) return requirementId;
  const { from, to } = r.window;
  if (!from || !to) return r.text;
  const day = new Date(from)
    .toLocaleDateString("en-GB", { day: "2-digit", month: "short", timeZone: "UTC" })
    .toUpperCase();
  return `${day} ${from.slice(11, 16)}–${to.slice(11, 16)}Z · ${r.text}`;
}
const valid = (text: string | undefined) => {
  const t = (text ?? "").trim();
  return t.length >= REASON_MIN && t.length <= REASON_MAX;
};
/** The reason a requirement will be acknowledged with, or null when it has none yet. */
function reasonFor(group: string, requirementId: string): string | null {
  if (sameForAll.value) return valid(shared.value) ? shared.value.trim() : null;
  const own = split.value[group] ? overrides.value[requirementId] : undefined;
  const text = own !== undefined && own.trim() !== "" ? own : reasons.value[group];
  return valid(text) ? (text ?? "").trim() : null;
}
const missing = computed(
  () =>
    groups.value.filter((g) =>
      g.unmet.some((u) => reasonFor(keyOf(g.spacecraftId), u.requirement_id) === null),
    ).length,
);

// Ticking seeds the shared reason from the first one already written; per-spacecraft reasons are
// kept, so unticking brings them back.
watch(sameForAll, (on) => {
  if (!on || valid(shared.value)) return;
  shared.value =
    groups.value.map((g) => reasons.value[keyOf(g.spacecraftId)]).find((r) => valid(r)) ?? "";
});
const requirementCount = computed(() => groups.value.reduce((n, g) => n + g.unmet.length, 0));
/** The causes, once each (qa #26: the server can repeat one). */
const causeText = (why: readonly string[]) =>
  [...new Set(why.map(reasonText))].join(" · ") || "rule not met";

/** U36: the reasons the author gave last round, per spacecraft (same text) or per requirement. */
function prefill() {
  const before = new Map(
    (props.plan.previous_round?.acknowledgements ?? []).map((a) => [a.requirement_id, a.reason]),
  );
  if (before.size === 0) return;
  for (const g of groups.value) {
    const key = keyOf(g.spacecraftId);
    if (reasons.value[key]) continue;
    const texts = g.unmet.map((u) => before.get(u.requirement_id));
    const first = texts[0];
    if (first && texts.every((t) => t === first)) reasons.value[key] = first;
    else {
      for (const u of g.unmet) {
        const t = before.get(u.requirement_id);
        if (t && !overrides.value[u.requirement_id]) overrides.value[u.requirement_id] = t;
      }
      if (texts.some((t) => t)) split.value[key] = true;
    }
  }
}
function open() {
  error.value = null;
  if (props.keptNote && !note.value) note.value = props.keptNote;
  if (again.value) prefill();
  sheet.value?.open();
}
function close() {
  sheet.value?.close();
}
function submit() {
  if (missing.value > 0 || noteError.value) return;
  const acks = groups.value.flatMap((g) =>
    g.unmet.map((u) => ({
      requirement_id: u.requirement_id,
      reason: reasonFor(keyOf(g.spacecraftId), u.requirement_id) ?? "",
    })),
  );
  const text = note.value.trim();
  if (text) emit("submit", acks, text);
  else emit("submit", acks);
}
const heading = computed(() =>
  groups.value.length > 0
    ? `Accept ${plural(groups.value.length, "gap")} · ${contactsShortText(coverage(props.plan).contactsShort)}`
    : props.title,
);
/** U61: a refusal that names another plan offers to open it. */
const refusalOpen = computed(() => {
  const open = error.value ? lifecycleRefusal(error.value)?.open : null;
  const day = open?.day ?? props.day ?? null;
  return open && day ? { label: open.label, to: planOfDayRoute(day, open.planId) } : null;
});
/** U97: a 422 on the note shows the server's words under the note, not in the callout. */
const message: Reader<string> = (value, path) =>
  Array.isArray(value)
    ? value.map((v, i) => d.string(v, `${path}[${i}]`)).join(" ")
    : d.string(value, path);
const noteDetails = d.object({ decision_note: d.optional(message), note: d.optional(message) });
const serverNoteError = computed(() => {
  const x = error.value?.kind === "invalid" ? detailsOf(error.value, noteDetails) : null;
  return x?.decision_note ?? x?.note ?? null;
});
/** U97: approve's own refusals (a code it doesn't know goes to Technical details); U36 otherwise. */
const refusal = computed((): Readonly<{ text: string; code: string | null }> | null => {
  const e = error.value;
  if (!e || serverNoteError.value) return null;
  const who = { version: props.plan.version, userId: props.userId, day: props.day ?? "" };
  if (props.act === "approve") return approveRefusal(e, who);
  if (e.kind === "conflict" && isError(e, "plan_changed"))
    return {
      text: "The plan changed since you opened this. Close it and review again.",
      code: null,
    };
  return { text: submitRefusalText(e, who), code: null };
});
/** U26/ux #13: passes on a degraded station, listed so booking them is an informed choice. */
const atRisk = computed(() => {
  const ids = new Set(props.plan.at_risk.flatMap((r) => r.snapshot_ids));
  return props.plan.passes
    .filter((p) => ids.has(p.snapshot_id))
    .map((p) => ({
      id: p.snapshot_id,
      text: `${props.nameOf(p.spacecraft_id)?.name ?? p.spacecraft_id ?? "?"} · ${stationCode(p.station)} · ${p.starts_at.slice(11, 16)}–${p.ends_at.slice(11, 16)}Z`,
    }));
});
defineExpose({ open, close });
</script>

<template>
  <!-- Focus the first reason (or the commit when nothing is unmet) rather than the first control. -->
  <ApSheet
    ref="sheet"
    :title="heading"
    width="wide"
    initial-focus="textarea, footer button:last-child"
    @closed="emit('close')"
  >
    <p v-if="groups.length === 0" class="m-0 text-base text-text-3">{{ confirm }}</p>
    <template v-else>
      <label class="flex items-center gap-2 text-md text-text-2">
        <input
          v-model="sameForAll"
          type="checkbox"
          class="accent-[var(--color-readout)] [color-scheme:dark]"
        />
        Same reason for all
      </label>
      <ApTextarea
        v-if="sameForAll"
        v-model="shared"
        :label="`Reason for accepting all ${plural(groups.length, 'gap')}`"
        :rows="2"
        :maxlength="REASON_MAX"
        :hint="`At least ${REASON_MIN} characters. Recorded for each of the ${plural(requirementCount, 'requirement')}.`"
      />
      <div
        v-for="group in groups"
        :key="keyOf(group.spacecraftId)"
        class="flex flex-col gap-2 border-t border-hairline pt-3"
      >
        <p class="m-0 font-mono text-sm font-semibold text-readout">
          {{
            nameOf(group.spacecraftId)?.name ??
            group.spacecraftId ??
            "Requirements without a spacecraft"
          }}
        </p>
        <ul class="m-0 list-none p-0 font-mono text-xs text-text-3">
          <li v-for="u in group.unmet" :key="u.requirement_id">
            {{ requirementLine(u.requirement_id) }} ·
            {{ causeText(u.why) }}
          </li>
        </ul>
        <ApTextarea
          v-if="!sameForAll"
          :model-value="reasons[keyOf(group.spacecraftId)] ?? ''"
          :label="`Reason for accepting this gap`"
          :rows="2"
          :maxlength="REASON_MAX"
          :hint="`At least ${REASON_MIN} characters. Recorded for each of its ${plural(group.unmet.length, 'requirement')}.`"
          @update:model-value="reasons[keyOf(group.spacecraftId)] = $event"
        />
        <details
          v-if="!sameForAll && group.unmet.length > 1"
          :open="split[keyOf(group.spacecraftId)]"
          @toggle="split[keyOf(group.spacecraftId)] = ($event.target as HTMLDetailsElement).open"
        >
          <summary class="max-md:hit-44 cursor-pointer text-sm text-text-3">
            Different reason per requirement
          </summary>
          <div class="mt-2 flex flex-col gap-2">
            <ApTextarea
              v-for="u in group.unmet"
              :key="u.requirement_id"
              :model-value="overrides[u.requirement_id] ?? ''"
              :label="requirementLine(u.requirement_id)"
              :rows="1"
              :maxlength="REASON_MAX"
              hint="Leave empty to use the reason above."
              @update:model-value="overrides[u.requirement_id] = $event"
            />
          </div>
        </details>
      </div>
    </template>
    <ApTextarea
      v-model="note"
      label="Note for the record (optional)"
      :hint="noteHint"
      :maxlength="NOTE_MAX"
      :error="noteError ?? serverNoteError"
    />
    <ApCallout v-if="atRisk.length > 0" tone="caution">
      <span class="flex flex-col gap-1">
        <span
          >{{ plural(atRisk.length, "pass", "passes") }} on a degraded station may lose data.
          Booking them is still allowed.</span
        >
        <span v-for="r in atRisk" :key="r.id" class="font-mono text-sm text-text-2">{{
          r.text
        }}</span>
      </span>
    </ApCallout>
    <ApCallout v-if="refusal" tone="caution">
      <span class="flex flex-wrap items-center gap-x-3 gap-y-1">
        <span>{{ refusal.text }}</span>
        <details v-if="refusal.code" class="mt-1 basis-full text-xs text-text-3">
          <summary class="cursor-pointer font-mono uppercase">Technical details</summary>
          <p class="m-0 font-mono">{{ refusal.code }}</p>
        </details>
        <ApButton
          v-if="refusalOpen"
          variant="ghost"
          size="compact"
          :to="refusalOpen.to"
          @click="close"
          >{{ refusalOpen.label }}</ApButton
        >
      </span>
    </ApCallout>
    <template #footer>
      <span v-if="groups.length > 0" class="mr-auto font-mono text-xs text-text-4 uppercase"
        >Audited · visible to the approver</span
      >
      <span class="ml-auto flex flex-wrap items-center gap-2">
        <span v-if="missing > 0" class="text-sm text-text-3"
          >{{ missing }} {{ missing === 1 ? "gap still needs" : "gaps still need" }} a reason</span
        >
        <ApButton variant="ghost" @click="close">Cancel</ApButton>
        <ApButton
          variant="primary"
          :disabled="missing > 0 || busy || noteError !== null"
          :disabled-reason="
            busy
              ? 'Submitting…'
              : noteError
                ? 'Shorten the note first.'
                : 'Every gap needs a reason first.'
          "
          @click="submit"
          >{{ commitLabel }}</ApButton
        >
      </span>
    </template>
  </ApSheet>
</template>
