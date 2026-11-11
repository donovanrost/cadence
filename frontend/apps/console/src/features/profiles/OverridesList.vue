<script setup lang="ts">
import { ref } from "vue";
import { failureOutcome, refreshConfigState, stageChange } from "@/features/changes/index.ts";
import { ApButton, ApCallout, formatShort } from "@/ui";
import type { ProfileField, ProfileOverride } from "./detail.ts";
import { overrideOp, valueText } from "./overrides.ts";

/** P3 rows: spacecraft · what differs · since · Reset (stages a spacecraft_override reset). */
const props = defineProps<{
  missionId: string;
  overrides: readonly ProfileOverride[];
  /** The profile's fields, so a row reads "Catalog revision rev 4 instead of rev 3", not ids. */
  fields: readonly ProfileField[];
  canStage: boolean;
}>();
const busy = ref<string | null>(null);
const note = ref<string | null>(null);
const fieldOf = (o: ProfileOverride) => props.fields.find((f) => f.path === o.path);
const key = (o: ProfileOverride) => `${o.spacecraft.id}:${o.path}`;

async function reset(o: ProfileOverride) {
  busy.value = key(o);
  note.value = null;
  try {
    const result = await stageChange(props.missionId, {
      summary: `${o.spacecraft.name} · reset ${fieldOf(o)?.label ?? o.path} to profile`,
      source: { surface: "profile_overrides" },
      ops: [overrideOp(o.spacecraft.id, o.path, null)],
    });
    if (result.ok) {
      note.value = `Reset staged for ${o.spacecraft.name}. It applies with the change set.`;
      refreshConfigState(props.missionId);
    } else note.value = failureOutcome(result.error, "staged").sentence;
  } finally {
    busy.value = null;
  }
}
</script>

<template>
  <ApCallout v-if="note" tone="info">{{ note }}</ApCallout>
  <ul class="m-0 list-none p-0">
    <li
      v-for="o in overrides"
      :key="key(o)"
      class="grid grid-cols-[150px_minmax(0,1fr)_auto] items-center gap-3 border-t border-hairline px-4 py-2.5 first:border-t-0 max-md:grid-cols-1"
    >
      <RouterLink
        :to="{ name: 'setup.spacecraft.one', params: { scId: o.spacecraft.id } }"
        class="font-mono text-readout no-underline hover:underline max-md:hit-44"
        >{{ o.spacecraft.name }}</RouterLink
      >
      <span class="text-md text-readout">
        <span :class="fieldOf(o) ? 'text-text-2' : 'font-mono text-text-3'">{{
          fieldOf(o)?.label ?? o.path
        }}</span>
        {{ valueText(fieldOf(o), o.spacecraft_value) }} instead of
        {{ valueText(fieldOf(o), o.profile_value) }}
        <span v-if="o.reason" class="text-text-3"> · {{ o.reason }}</span>
        <span class="font-mono text-xs text-text-4">
          {{
            o.since_revision !== null
              ? ` since r${o.since_revision}`
              : o.set_at
                ? ` since ${formatShort(new Date(o.set_at))}`
                : ""
          }}</span
        >
        <span v-if="o.redundant" class="text-sm text-text-3"> · same as the profile now</span>
      </span>
      <ApButton
        v-if="canStage"
        size="compact"
        :disabled="busy !== null"
        disabled-reason="Staging…"
        @click="reset(o)"
        >Reset</ApButton
      >
    </li>
  </ul>
</template>
