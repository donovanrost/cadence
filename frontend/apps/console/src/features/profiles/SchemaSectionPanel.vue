<script setup lang="ts">
import { ApButton, ApCallout, ApChip, ApPanel, formatCount } from "@/ui";
import { fieldText, type ProfileSection } from "./detail.ts";

/** P1: one schema section as a read-only key/value grid (DECISIONS #19: framing read-only). */
defineProps<{ section: ProfileSection; inheritCount: number; canEdit: boolean }>();
defineEmits<{ edit: [] }>();
/** domain (catalog generations): what applying a generation field does, from an operator's view. */
const generationNote =
  "From the moment it applies, telemetry decodes and commands build with the new value. Commands still waiting to release are canceled; commands in flight hold the apply until they finish. Nothing restarts and no link drops.";
</script>

<template>
  <ApPanel
    index="P1"
    :title="section.label"
    :meta="`Inherited by ${formatCount(inheritCount)}`"
    flush
  >
    <template v-if="canEdit" #header>
      <ApButton size="compact" variant="primary" @click="$emit('edit')">Edit</ApButton>
    </template>
    <ApCallout v-if="section.key === 'catalog'" tone="info">
      A catalog change goes through a change set: when it's applied, spacecraft on this profile move
      to the new revision. Spacecraft still running another catalog show in Readiness.
    </ApCallout>
    <ApCallout v-else-if="section.key === 'framing'" tone="info">
      Decode uses each transport's frame settings today. Profile framing takes effect when the
      pipeline reads it.
    </ApCallout>
    <dl class="m-0 grid grid-cols-1 gap-px bg-hairline md:grid-cols-2">
      <div v-for="f in section.fields" :key="f.path" class="flex flex-col gap-1 bg-panel px-4 py-3">
        <dt class="ap-label flex items-center gap-2">
          {{ f.label }}
          <ApChip v-if="f.overridden_by > 0">{{ f.overridden_by }} override</ApChip>
          <ApChip v-if="f.runtime_impact === 'generation'" :title="generationNote"
            >Cancels queued commands</ApChip
          >
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
