<script setup lang="ts">
import { computed, nextTick, ref, watch } from "vue";
import type { ApiError } from "@/api";
import { ApButton, ApCallout, ApTextarea, plural } from "@/ui";
import {
  reasonText,
  REASON_MAX,
  REASON_MIN,
  stationCode,
  type Acknowledgement,
  type PlanDetail,
} from "./api.ts";
import { planErrorText } from "./errors.ts";
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
  confirm: string;
  busy: boolean;
}>();
const emit = defineEmits<{ submit: [acks: Acknowledgement[]]; close: [] }>();
const error = defineModel<ApiError | null>("error", { default: null });

const dialog = ref<HTMLDialogElement | null>(null);
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

let opener: HTMLElement | null = null;
const titleId = `ap-submit-${Math.random().toString(36).slice(2, 9)}`;
function open() {
  error.value = null;
  opener = document.activeElement instanceof HTMLElement ? document.activeElement : null;
  dialog.value?.showModal();
  // Focus the first reason (or the commit when nothing is unmet) rather than the first control.
  void nextTick(() =>
    (
      dialog.value?.querySelector<HTMLElement>("textarea") ??
      dialog.value?.querySelector<HTMLElement>("footer button:last-child")
    )?.focus(),
  );
}
function close() {
  dialog.value?.close();
}
function onClosed() {
  opener?.focus();
  opener = null;
  emit("close");
}
function submit() {
  if (missing.value > 0) return;
  emit(
    "submit",
    groups.value.flatMap((g) =>
      g.unmet.map((u) => ({
        requirement_id: u.requirement_id,
        reason: reasonFor(keyOf(g.spacecraftId), u.requirement_id) ?? "",
      })),
    ),
  );
}
const title = computed(() =>
  groups.value.length > 0
    ? `Accept ${plural(groups.value.length, "gap")} · ${contactsShortText(coverage(props.plan).contactsShort)}`
    : "Submit the plan",
);
const errorText = computed(() => {
  const e = error.value;
  if (!e) return null;
  if (e.kind === "conflict" && e.code === "plan_changed")
    return "The plan changed since you opened this. Close it and review again.";
  return planErrorText(e);
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
  <dialog
    ref="dialog"
    :aria-labelledby="titleId"
    aria-modal="true"
    class="m-auto w-[min(760px,calc(100vw-32px))] border border-line bg-panel p-0 text-readout backdrop:bg-[rgba(5,7,10,0.72)]"
    @close="onClosed"
  >
    <div class="flex max-h-[70vh] flex-col gap-3 overflow-auto p-5">
      <h2 :id="titleId" class="m-0 font-display text-xl font-semibold tracking-tag uppercase">
        {{ title }}
      </h2>
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
      <ApCallout v-if="errorText" tone="caution">{{ errorText }}</ApCallout>
    </div>
    <footer class="flex flex-wrap items-center gap-3 border-t border-hairline px-5 py-3">
      <span v-if="groups.length > 0" class="font-mono text-xs text-text-4 uppercase"
        >Audited · visible to the approver</span
      >
      <span class="ml-auto flex flex-wrap items-center gap-2">
        <span v-if="missing > 0" class="text-sm text-text-3"
          >{{ missing }} {{ missing === 1 ? "gap still needs" : "gaps still need" }} a reason</span
        >
        <ApButton variant="ghost" @click="close">Cancel</ApButton>
        <ApButton
          variant="primary"
          :disabled="missing > 0 || busy"
          :disabled-reason="busy ? 'Submitting…' : 'Every gap needs a reason first.'"
          @click="submit"
          >{{ commitLabel }}</ApButton
        >
      </span>
    </footer>
  </dialog>
</template>
