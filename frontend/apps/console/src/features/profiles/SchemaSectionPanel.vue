<script setup lang="ts">
import { ApButton, ApCallout, ApChip, ApPanel, ApTag, formatCount } from "@/ui";
import { fieldText, type ProfileField, type ProfileSection } from "./detail.ts";
import { generationNote } from "./present.ts";
import { stagedText, type StagedField } from "./staged.ts";

/** P1: one schema section as a key/value grid, with Edit when the section can be staged. */
const props = defineProps<{
  section: ProfileSection;
  inheritCount: number;
  canEdit: boolean;
  /** The mission turned profile framing off in ST1 (#45), so framing doesn't reach ingress. */
  framingOff: boolean;
  /** Fields already staged in the open change set (Profile.md States: Conflict). */
  staged: ReadonlyMap<string, StagedField>;
}>();
defineEmits<{ edit: [] }>();
/** Conflict chip (Profile.md States): caution when someone else staged this field. */
const chip = (f: ProfileField) => {
  const s = props.staged.get(f.path);
  return s
    ? { state: s.mine ? ("neutral" as const) : ("caution" as const), label: stagedText(f, s) }
    : null;
};
</script>

<template>
  <ApPanel
    index="P1"
    :title="section.label"
    :meta="`Inherited by ${formatCount(inheritCount)}`"
    flush
  >
    <template v-if="canEdit" #header>
      <ApButton size="compact" variant="primary" data-swap-opener @click="$emit('edit')"
        >Edit</ApButton
      >
    </template>
    <ApCallout v-if="section.key === 'catalog'" tone="info">
      A catalog change goes through a change set: when it's applied, spacecraft on this profile move
      to the new revision. Spacecraft still running another catalog show in Readiness.
    </ApCallout>
    <ApCallout v-else-if="section.key === 'framing' && framingOff" tone="info">
      This mission's settings keep profile framing out of the runtime, so changing it here doesn't
      change how telemetry is decoded.
      <RouterLink :to="{ name: 'setup.settings' }" class="text-readout hover:underline"
        >Mission settings</RouterLink
      >
    </ApCallout>
    <dl class="m-0 grid grid-cols-1 gap-px bg-hairline md:grid-cols-2">
      <div v-for="f in section.fields" :key="f.path" class="flex flex-col gap-1 bg-panel px-4 py-3">
        <dt class="ap-label flex items-center gap-2">
          {{ f.label }}
          <ApChip v-if="f.overridden_by > 0">{{ f.overridden_by }} override</ApChip>
          <ApTag v-if="chip(f)" v-bind="chip(f)" />
          <ApTag
            v-if="f.runtime_impact === 'generation'"
            state="caution"
            label="Cancels queued commands"
            :title="generationNote"
          />
        </dt>
        <dd
          class="m-0 font-mono text-md"
          :class="f.value === null ? 'text-text-3' : 'text-readout'"
        >
          {{ fieldText(f) }}
        </dd>
        <dd v-if="f.help" class="m-0 text-sm text-text-3">{{ f.help }}</dd>
      </div>
    </dl>
  </ApPanel>
</template>
