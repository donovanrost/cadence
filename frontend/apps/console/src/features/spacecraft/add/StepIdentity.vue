<script setup lang="ts">
import { computed } from "vue";
import { ApField, ApPanel } from "@/ui";
import { useDraft } from "./context.ts";
import { rangeLabel } from "./batch.ts";
import type { FieldErrors } from "./draft.ts";

/** A2 Identity (profile path): count, naming pattern, SCID range, NORAD ids; clashes inline. */
const { draft, set, proposal } = useDraft();

const errors = computed((): FieldErrors => {
  const p = proposal();
  return p.status === "incomplete" && p.step === "identity" ? p.errors : {};
});
const preview = computed(() => {
  const p = proposal();
  return p.status === "ready" ? rangeLabel(p.report.rows) : null;
});
const clashes = computed(() => {
  const p = proposal();
  return p.status === "ready"
    ? p.report.rows.flatMap((r) => r.problems).slice(0, draft.source === "manifest" ? 50 : 3)
    : [];
});
const scidEnd = computed(() => {
  const start = Number(draft.scidStart);
  const count = Number(draft.count);
  return Number.isInteger(start) && Number.isInteger(count) && count > 0
    ? String(start + count - 1)
    : "—";
});
</script>

<template>
  <ApPanel index="A2" title="Identity">
    <p v-if="draft.source === 'manifest'" class="m-0 text-md text-text-3">
      Names and SCIDs come from the manifest. Rows that clash are listed below; fix them in the file
      and choose it again.
    </p>
    <div v-else class="grid grid-cols-1 gap-4 md:grid-cols-2">
      <ApField
        :model-value="draft.count"
        label="Count"
        inputmode="numeric"
        mono
        :error="errors.count ?? null"
        @update:model-value="set('count', $event)"
      />
      <ApField
        :model-value="draft.pattern"
        label="Naming pattern"
        mono
        hint="Tokens: {scid}, {n}, {n:03}"
        :error="errors.pattern ?? null"
        @update:model-value="set('pattern', $event)"
      />
      <ApField
        :model-value="draft.scidStart"
        label="First SCID"
        inputmode="numeric"
        mono
        :hint="`Last SCID ${scidEnd} · prefilled with the next free SCID`"
        :error="errors.scidStart ?? null"
        @update:model-value="set('scidStart', $event)"
      />
      <ApField
        :model-value="draft.norad"
        label="NORAD ids"
        mono
        hint="Optional: one per spacecraft, in order, separated by commas. Leave empty to add later."
        :error="errors.norad ?? null"
        @update:model-value="set('norad', $event)"
      />
      <div class="flex flex-col gap-1.5">
        <span class="ap-label">Names</span>
        <span class="font-mono text-md text-readout">{{ preview ?? "—" }}</span>
      </div>
    </div>
    <ul v-if="clashes.length > 0" class="m-0 mt-3 list-none p-0 text-sm text-caution-text">
      <li v-for="clash in clashes" :key="clash">{{ clash }}</li>
    </ul>
  </ApPanel>
</template>
