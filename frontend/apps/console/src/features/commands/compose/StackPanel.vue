<script setup lang="ts">
import { ref } from "vue";
import { ApButton, ApEmptyState, ApPanel, ApTag } from "@/ui";
import CatalogSearch from "./CatalogSearch.vue";
import CommandForm from "./CommandForm.vue";
import { argSummary, checkItem, type StackItem } from "./stack.ts";

/** C2 · Command stack: ordered commands from the catalog; one row open for editing. */
defineProps<{ items: readonly StackItem[]; revision: string | null; adding: boolean }>();
const emit = defineEmits<{
  add: [commandId: string];
  change: [key: string, values: Record<string, string>];
  move: [index: number, by: -1 | 1];
  remove: [key: string];
}>();
const open = ref<string | null>(null);
</script>

<template>
  <ApPanel
    index="C2"
    title="Command stack"
    :meta="revision ? `catalog ${revision.slice(-8)}` : undefined"
    flush
  >
    <ApEmptyState
      v-if="items.length === 0"
      headline="Empty"
      sentence="Pick a command from the catalog below."
    />
    <ol v-else class="m-0 list-none p-0">
      <li
        v-for="(item, i) in items"
        :key="item.key"
        class="border-t border-hairline first:border-t-0"
      >
        <div class="flex flex-wrap items-center gap-3 px-4 py-2">
          <span class="font-mono text-xs text-text-4">{{ String(i + 1).padStart(2, "0") }}</span>
          <button
            type="button"
            class="max-md:hit-44 cursor-pointer font-mono font-semibold text-readout"
            :aria-expanded="open === item.key"
            @click="open = open === item.key ? null : item.key"
          >
            {{ item.command.name }}
          </button>
          <ApTag v-if="item.command.hazardous" state="crit" label="Hazardous" />
          <ApTag v-if="!checkItem(item).ok" state="caution" label="Needs values" />
          <span class="min-w-0 flex-1 truncate font-mono text-sm text-text-3">{{
            argSummary(item).join(" · ")
          }}</span>
          <ApButton
            size="compact"
            variant="ghost"
            :disabled="i === 0"
            disabled-reason="Already first"
            :aria-label="`Move ${item.command.name} up`"
            @click="emit('move', i, -1)"
            >↑</ApButton
          >
          <ApButton
            size="compact"
            variant="ghost"
            :disabled="i === items.length - 1"
            disabled-reason="Already last"
            :aria-label="`Move ${item.command.name} down`"
            @click="emit('move', i, 1)"
            >↓</ApButton
          >
          <ApButton
            size="compact"
            variant="ghost"
            :aria-label="`Remove ${item.command.name}`"
            @click="emit('remove', item.key)"
            >✕</ApButton
          >
        </div>
        <CommandForm
          v-if="open === item.key"
          :item="item"
          @change="(v) => emit('change', item.key, v)"
        />
      </li>
    </ol>
    <div class="border-t border-hairline p-4">
      <p v-if="adding" role="status" class="m-0 pb-2 font-mono text-xs text-text-4">ADDING…</p>
      <CatalogSearch @add="(id) => emit('add', id)" />
    </div>
  </ApPanel>
</template>
