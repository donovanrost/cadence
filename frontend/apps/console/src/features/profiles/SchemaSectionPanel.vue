<script setup lang="ts">
import { ApCallout, ApChip, ApPanel, formatCount } from "@/ui";
import { fieldText, type ProfileSection } from "./detail.ts";

/** P1: one schema section as a read-only key/value grid (DECISIONS #19: framing read-only). */
defineProps<{ section: ProfileSection; inheritCount: number }>();
</script>

<template>
  <ApPanel
    index="P1"
    :title="section.label"
    :meta="`Inherited by ${formatCount(inheritCount)}`"
    flush
  >
    <ApCallout v-if="section.key === 'catalog'" tone="info">
      Catalog revisions can't change through change sets yet (DECISIONS #36): a change set that
      would move a spacecraft to another catalog revision is refused with the supported route.
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
