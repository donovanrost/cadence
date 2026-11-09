<script setup lang="ts">
import { computed, ref, watch } from "vue";
import { describeApiError, type ApiError } from "@/api";
import { ApButton, ApCallout, ApTextarea, plural } from "@/ui";
import {
  reasonText,
  REASON_MAX,
  REASON_MIN,
  type Acknowledgement,
  type PlanDetail,
} from "./api.ts";
import { contactsShortText, coverage } from "./coverage.ts";
import type { SpacecraftName } from "./names.ts";

/**
 * Accept-gaps sheet (ScheduleFlow K1, DECISIONS #28), also the confirm step when nothing is unmet.
 * One reason per unmet requirement (10–2000 chars, audited, visible to the approver).
 */
const props = defineProps<{
  plan: PlanDetail;
  nameOf: (id: string | null) => SpacecraftName | null;
  /** Commit label, e.g. "Accept 6 gaps and submit". */
  commitLabel: string;
  /** Sentence under the title when nothing is unmet. */
  confirm: string;
  busy: boolean;
}>();
const emit = defineEmits<{ submit: [acks: Acknowledgement[]]; close: [] }>();
const error = defineModel<ApiError | null>("error", { default: null });

const dialog = ref<HTMLDialogElement | null>(null);
const reasons = ref<Record<string, string>>({});
const sameForAll = ref(false);
const rules = computed(
  () => new Map(props.plan.demand.rules.map((r) => [r.requirement_id, r.text])),
);
const valid = (text: string | undefined) => {
  const t = (text ?? "").trim();
  return t.length >= REASON_MIN && t.length <= REASON_MAX;
};
const missing = computed(
  () => props.plan.unmet.filter((u) => !valid(reasons.value[u.requirement_id])).length,
);

watch(sameForAll, (on) => {
  const first = props.plan.unmet.map((u) => reasons.value[u.requirement_id]).find((r) => valid(r));
  if (!on || !first) return;
  for (const u of props.plan.unmet)
    if (!valid(reasons.value[u.requirement_id])) reasons.value[u.requirement_id] = first;
});

function open() {
  error.value = null;
  dialog.value?.showModal();
}
function close() {
  dialog.value?.close();
}
function submit() {
  if (missing.value > 0) return;
  emit(
    "submit",
    props.plan.unmet.map((u) => ({
      requirement_id: u.requirement_id,
      reason: (reasons.value[u.requirement_id] ?? "").trim(),
    })),
  );
}
const errorText = computed(() => {
  const e = error.value;
  if (!e) return null;
  if (e.kind === "conflict" && e.code === "plan_changed")
    return "The plan changed since you opened this. Close it and review again.";
  return describeApiError(e);
});
defineExpose({ open, close });
</script>

<template>
  <dialog
    ref="dialog"
    :aria-label="commitLabel"
    class="m-auto w-[min(760px,calc(100vw-32px))] border border-line bg-panel p-0 text-readout backdrop:bg-[rgba(5,7,10,0.72)]"
    @close="emit('close')"
  >
    <div class="flex max-h-[70vh] flex-col gap-3 overflow-auto p-5">
      <h2 class="m-0 font-display text-xl font-semibold tracking-tag uppercase">
        {{
          plan.unmet.length > 0
            ? `Accept ${plural(plan.unmet.length, "gap")} · ${contactsShortText(coverage(plan).contactsShort)}`
            : "Submit the plan"
        }}
      </h2>
      <p v-if="plan.unmet.length === 0" class="m-0 text-base text-text-3">{{ confirm }}</p>
      <template v-else>
        <label class="flex items-center gap-2 text-md text-text-2">
          <input
            v-model="sameForAll"
            type="checkbox"
            class="accent-[var(--color-readout)] [color-scheme:dark]"
          />
          Same reason for all
        </label>
        <div
          v-for="gap in plan.unmet"
          :key="gap.requirement_id"
          class="flex flex-col gap-2 border-t border-hairline pt-3"
        >
          <p class="m-0 flex flex-wrap gap-x-3 font-mono text-sm">
            <span class="font-semibold text-readout">{{
              nameOf(gap.spacecraft_id)?.name ?? gap.spacecraft_id ?? "Requirement"
            }}</span>
            <span class="text-text-3 uppercase">{{ rules.get(gap.requirement_id) ?? "" }}</span>
          </p>
          <p class="m-0 text-md text-text-3">
            {{ gap.why.map(reasonText).join(" · ") || "Rule not met" }}
          </p>
          <ApTextarea
            :model-value="reasons[gap.requirement_id] ?? ''"
            @update:model-value="reasons[gap.requirement_id] = $event"
            :label="`Reason for accepting this gap`"
            :rows="2"
            :maxlength="REASON_MAX"
            :hint="`At least ${REASON_MIN} characters.`"
          />
        </div>
      </template>
      <ApCallout v-if="errorText" tone="caution">{{ errorText }}</ApCallout>
    </div>
    <footer class="flex flex-wrap items-center gap-3 border-t border-hairline px-5 py-3">
      <span v-if="plan.unmet.length > 0" class="font-mono text-xs text-text-4 uppercase"
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
