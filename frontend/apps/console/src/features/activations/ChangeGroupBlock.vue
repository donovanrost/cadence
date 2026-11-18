<script setup lang="ts">
import { computed, ref } from "vue";
import { ApButton, ApCallout, ApTag } from "@/ui";
import {
  firstStartLine,
  groupHeading,
  namesLine,
  noChangesLine,
  rowLine,
  showAllLabel,
} from "./changesWords.ts";
import { fetchGroupNames, type ChangeGroup, type CraftRef } from "./configurationChanges.ts";
import type { DetailKey } from "./api.ts";

/** #235 (ux U94): one group of craft with identical changes, or the no-change group. */
const props = defineProps<{ group: ChangeGroup; requestKey: DetailKey; fleet: boolean }>();
const unchanged = computed(
  () => props.group.rows.items.length === 0 && props.group.rows.unshown.length === 0,
);
/** Every name, once Show all has paged them in from the names route. */
const all = ref<readonly CraftRef[] | null>(null);
const loading = ref(false);
const failed = ref(false);
async function showAll() {
  loading.value = true;
  failed.value = false;
  const names: CraftRef[] = [];
  let offset: number | null = 0;
  try {
    while (offset !== null) {
      const r = await fetchGroupNames(
        { ...props.requestKey, group: props.group.index, offset },
        new AbortController().signal,
      );
      if (!r.ok) return void (failed.value = true);
      names.push(...r.value.spacecraft);
      offset = r.value.next_offset;
    }
    all.value = names;
  } finally {
    loading.value = false;
  }
}
</script>

<template>
  <section class="flex flex-col gap-2 border-t border-line pt-3 first:border-t-0 first:pt-0">
    <p v-if="unchanged" class="m-0 text-md text-text-2">
      {{ all ? `No changes on ${all.length} spacecraft:` : noChangesLine(group) }}
    </p>
    <div v-else class="flex flex-wrap items-center gap-2">
      <h3 v-if="fleet" class="m-0 text-md text-bright">{{ groupHeading(group) }}</h3>
      <ApTag v-if="!group.telemetry_enabled" state="off" label="Telemetry off" />
    </div>
    <p v-if="!unchanged && fleet && group.count > 1 && !all" class="m-0 text-sm text-text-2">
      {{ namesLine(group) }}
    </p>
    <p v-if="all" class="m-0 text-sm text-text-2">{{ all.map((s) => s.name).join(", ") }}</p>
    <div v-if="showAllLabel(group) && !all">
      <ApButton
        size="compact"
        variant="ghost"
        :disabled="loading"
        disabled-reason="Loading…"
        @click="showAll"
        >{{ showAllLabel(group) }}</ApButton
      >
    </div>
    <ApCallout v-if="failed" tone="caution"> The names couldn't be loaded. Try again. </ApCallout>
    <p v-if="group.first_start" class="m-0 text-md text-text-2">{{ firstStartLine(group) }}</p>
    <ul v-if="!unchanged" class="m-0 flex list-none flex-col gap-1 p-0">
      <li v-for="row in group.rows.items" :key="row.field" class="text-md">
        {{ rowLine(row, group.first_start) }}
      </li>
    </ul>
  </section>
</template>
