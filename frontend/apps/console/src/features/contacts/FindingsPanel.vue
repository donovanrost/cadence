<script setup lang="ts">
import { computed, ref, shallowRef } from "vue";
import { RouterLink } from "vue-router";
import { ApButton, ApCallout, ApListRow, ApPanel, ApSheet } from "@/ui";
import { findingRows, type FindingRow } from "./findingRows.ts";
import type { Findings } from "./findings.ts";

/**
 * D4 · Needs a decision (Contacts.md): one row per finding, the server's sentence, and `Open in
 * Plan` (no fix proposals yet). Same-cause coverage gaps fold into one row with Show all (ux §7).
 * Hidden by the screen when M22 isn't available.
 */
const props = defineProps<{ findings: Findings; label: string; canBook?: boolean }>();
defineEmits<{ book: [prefill: { spacecraftId: string; from: number; to: number }] }>();
const rows = computed(() => findingRows(props.findings.findings));
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const shown = shallowRef<FindingRow | null>(null);
function showAll(row: FindingRow) {
  shown.value = row;
  sheet.value?.open();
}
</script>

<template>
  <ApPanel index="D4" title="Needs a decision" pane flush>
    <ApCallout v-if="rows.length === 0" tone="nominal">
      No conflicts or gaps in the next {{ label }}.
    </ApCallout>
    <ul v-else class="m-0 list-none p-0">
      <ApListRow
        v-for="r in rows"
        :key="r.key"
        :state="r.state"
        :title="r.title"
        :sentence="r.sentence"
      >
        <template #action>
          <!-- qa 11-13: in the narrow D4 pane a row of three buttons squeezed the title until it
               overflowed into them; stacked, the column is only as wide as the widest button. -->
          <span class="flex flex-col items-end gap-1">
            <ApButton
              v-if="canBook && r.book"
              size="compact"
              variant="secondary"
              @click="r.book && $emit('book', r.book)"
              >Book a pass</ApButton
            >
            <ApButton v-if="r.members" size="compact" variant="ghost" @click="showAll(r)"
              >Show all {{ r.members.length }}</ApButton
            >
            <ApButton
              size="compact"
              variant="secondary"
              :to="{ name: 'ops.contacts.plan', query: { day: r.day } }"
              >Open in Plan</ApButton
            >
          </span>
        </template>
      </ApListRow>
    </ul>
    <p
      v-if="findings.truncated"
      class="m-0 border-t border-hairline px-4 py-2 text-sm text-caution-text"
    >
      Too many passes to check them all; narrow the window.
    </p>
    <ApSheet ref="sheet" :title="shown?.sentence ?? ''" width="wide" @closed="shown = null">
      <ul class="m-0 flex list-none flex-col gap-2 p-0">
        <li
          v-for="m in shown?.members ?? []"
          :key="m.key"
          class="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 border-t border-hairline pt-2"
        >
          <RouterLink
            v-if="m.to"
            :to="m.to"
            class="max-md:hit-44 font-mono text-sm text-readout tabular hover:underline"
            @click="sheet?.close()"
            >{{ m.text }}</RouterLink
          >
          <span v-else class="font-mono text-sm text-readout">{{ m.text }}</span>
          <span v-if="m.detail" class="font-mono text-xs text-text-3">{{ m.detail }}</span>
        </li>
      </ul>
      <template #footer>
        <ApButton variant="ghost" @click="sheet?.close()">Close</ApButton>
      </template>
    </ApSheet>
  </ApPanel>
</template>
