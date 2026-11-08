<script setup lang="ts">
import { ref } from "vue";
import { ApButton, ApPanel, formatShort, plural } from "@/ui";
import type { Change } from "./shapes.ts";

/** K1: one row per staged change, collapsed; expanded shows what each op touches. */
defineProps<{ changes: readonly Change[] }>();
const open = ref(new Set<string>());
function toggle(id: string) {
  const next = new Set(open.value);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  open.value = next;
}
</script>

<template>
  <ApPanel index="K1" title="Changes" :meta="plural(changes.length, 'change')" flush>
    <ul class="m-0 list-none p-0">
      <li
        v-for="change in changes"
        :key="change.id"
        class="border-t border-hairline first:border-t-0"
      >
        <div class="grid grid-cols-[minmax(0,1fr)_auto_auto] items-center gap-3 px-4 py-3">
          <span class="text-base font-semibold text-readout">{{ change.summary }}</span>
          <span class="text-sm text-text-3"
            >{{ change.author.name }} ·
            <time class="font-mono text-xs" :datetime="change.staged_at">{{
              formatShort(new Date(change.staged_at))
            }}</time></span
          >
          <ApButton
            size="compact"
            variant="ghost"
            :aria-expanded="open.has(change.id)"
            @click="toggle(change.id)"
            >{{ open.has(change.id) ? "Hide" : "Details" }}</ApButton
          >
        </div>
        <ul
          v-if="open.has(change.id)"
          class="m-0 list-none border-t border-hairline-faint bg-vacuum px-4 py-2.5 font-mono text-sm"
        >
          <li v-for="op in change.ops" :key="op.id" class="py-0.5 text-text-2">
            <span class="text-text-4">{{ op.action }} {{ op.kind }}</span>
            {{ op.entity_id ?? "new"
            }}<template v-if="op.paths.length > 0"> · {{ op.paths.join(", ") }}</template>
          </li>
        </ul>
      </li>
    </ul>
    <p class="m-0 border-t border-hairline px-4 py-2.5 text-sm text-text-3">
      Withdraw and Discard arrive with the change-set write endpoints. Until then, changes are
      withdrawn where they were made.
    </p>
  </ApPanel>
</template>
