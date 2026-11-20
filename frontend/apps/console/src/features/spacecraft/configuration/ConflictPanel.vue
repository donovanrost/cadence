<script setup lang="ts">
import { computed } from "vue";
import { ApButton, ApCallout } from "@/ui";
import type { ConfigurationDocument, ConfigurationSnapshot } from "./api.ts";
import { conflictRows } from "./draft-words.ts";

/**
 * #595a (U94): someone saved this craft's configuration after these edits started (a stale
 * token). The edits are kept; the rows say where the two differ ("Saved: TM → Yours: AOS"), and
 * the person chooses: `Use the saved version` drops the edits, `Keep my edits` saves over it next.
 */
const props = defineProps<{
  snapshot: ConfigurationSnapshot;
  saved: ConfigurationDocument;
  mine: ConfigurationDocument;
}>();
const emit = defineEmits<{ useSaved: []; keepMine: [] }>();
const rows = computed(() => conflictRows(props.snapshot, props.saved, props.mine));
</script>

<template>
  <ApCallout tone="caution" role="alert" data-config-conflict>
    Someone saved {{ snapshot.name }}'s configuration after you started editing. Your edits are
    kept.
    <ul v-if="rows.length" class="m-0 mt-1 ps-5">
      <li v-for="r in rows" :key="r.key">
        {{ r.label }}: Saved: {{ r.saved }} → Yours: {{ r.mine }}
      </li>
    </ul>
    <template #action>
      <ApButton size="compact" @click="emit('useSaved')">Use the saved version</ApButton>
      <ApButton size="compact" variant="ghost" @click="emit('keepMine')">Keep my edits</ApButton>
    </template>
  </ApCallout>
</template>
