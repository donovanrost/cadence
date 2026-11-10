<script setup lang="ts">
import { computed } from "vue";
import { formatClock, formatDayTime, plural, ApPanel, ApTag } from "@/ui";
import { catalogRevisionWords } from "../api.ts";
import type { Group } from "../groups/show.ts";
import type { PersonName } from "../groups/words.ts";

/**
 * Request header + A1 What changes + (A2 slot) + A3 What will radiate (CommandFlow C2). v1 shows the decoded
 * stack (argument JSON as sent; 64-bit safe) — the encoded packet waits on M24.
 */
const props = defineProps<{ group: Group; nameOf: PersonName }>();
const LIMIT = 40;
const targets = computed(() => props.group.targets.slice(0, LIMIT));
const commands = computed(() => [...props.group.commands].sort((a, b) => a.position - b.position));
const release = computed(() => {
  const nb = props.group.release?.not_before;
  return nb
    ? `Held until ${formatClock(new Date(nb))}, then each target at its next AOS`
    : "Each target at its next AOS";
});
const args = (json: string) => (json.trim() === "{}" ? "no arguments" : json);
const pos = (n: number) => String(n + 1).padStart(2, "0");
</script>

<template>
  <div class="flex flex-col gap-3">
    <div v-if="group.log_entry" class="border-l-2 border-hairline pl-3">
      <p class="m-0 text-md text-text-2">“{{ group.log_entry }}”</p>
      <p class="m-0 font-mono text-xs text-text-4 uppercase">
        {{ nameOf(group.requested_by.user_id) }} ·
        {{ formatDayTime(new Date(group.requested_at)) }}
      </p>
    </div>
    <ApPanel
      index="A1"
      title="What changes"
      :meta="
        [plural(group.target_count, 'target'), catalogRevisionWords(group.catalog_revision)]
          .filter(Boolean)
          .join(' · ')
      "
      flush
    >
      <ul class="m-0 flex list-none flex-wrap gap-x-4 gap-y-1 px-4 py-3">
        <li v-for="t in targets" :key="t.spacecraft_id" class="font-mono text-sm text-readout">
          {{ t.name ?? "Unknown spacecraft" }}
          <span class="text-text-4">SCID {{ t.scid ?? "—" }}</span>
        </li>
        <li v-if="group.targets.length > LIMIT" class="font-mono text-sm text-text-4">
          and {{ group.targets.length - LIMIT }} more
        </li>
      </ul>
      <p class="m-0 border-t border-hairline px-4 py-2 text-md text-text-3">
        Release: {{ release }}.
      </p>
    </ApPanel>
    <slot name="checks" />
    <ApPanel index="A3" title="What will radiate" meta="encoded preview not available" flush>
      <ol class="m-0 list-none p-0">
        <li
          v-for="c in commands"
          :key="c.position"
          class="flex items-baseline gap-3 border-t border-hairline-faint px-4 py-2 first:border-t-0"
        >
          <span class="font-mono text-xs text-text-4">{{ pos(c.position) }}</span>
          <span class="font-mono text-md font-semibold text-readout">{{
            c.name ?? c.command_id
          }}</span>
          <ApTag v-if="c.hazardous" state="crit" label="HAZ" />
          <ApTag v-else-if="c.critical" state="caution" label="CRIT" />
          <span class="min-w-0 truncate font-mono text-sm text-text-3">{{
            args(c.argument_values_json)
          }}</span>
        </li>
      </ol>
    </ApPanel>
  </div>
</template>
