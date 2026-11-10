<script setup lang="ts">
import { computed } from "vue";
import type { Pass } from "@/features/contacts/index.ts";
import { useNow } from "@/ui";
import { coveredLine, type CoveredPass } from "./covered.ts";

/** C · Changes: lost bookings a separate booking already covers (domain #56); none are re-sent. */
const props = defineProps<{
  covered: readonly CoveredPass[];
  bookings: readonly Pass[];
  name: (id: string | null) => string;
}>();
const now = useNow();
const lines = computed(() => {
  const today = now.value.toISOString().slice(0, 10);
  return props.covered.map((c) => ({
    key: c.snapshot_id,
    text: coveredLine(c, props.bookings, props.name(c.spacecraft_id), today),
  }));
});
</script>

<template>
  <template v-if="lines.length > 0">
    <h3 class="ap-label px-4 pt-3">Covered</h3>
    <ul class="m-0 list-none p-0 font-mono text-sm text-text-2">
      <li
        v-for="l in lines"
        :key="l.key"
        class="border-t border-hairline-faint px-4 py-1.5 first:border-t-0"
      >
        {{ l.text }}
      </li>
    </ul>
  </template>
</template>
