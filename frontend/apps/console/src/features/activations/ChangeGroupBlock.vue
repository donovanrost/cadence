<script setup lang="ts">
import { computed, ref, useId } from "vue";
import { ApButton, ApCallout, ApTag } from "@/ui";
import {
  firstStartLine,
  groupHeading,
  namesLine,
  noChangesLine,
  rowLine,
  showAllLabel,
  unnamedSourceIds,
} from "./changesWords.ts";
import {
  craftName,
  fetchGroupNames,
  type ChangeGroup,
  type CraftRef,
} from "./configurationChanges.ts";
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
/**
 * #244 (B3, A5): Show all is a disclosure. It stays mounted with aria-expanded (it used to unmount
 * on success, dropping focus), reads "Show fewer" while open, and keeps the names once loaded.
 */
const expanded = ref(false);
const namesId = useId();
const shown = computed(() => (expanded.value ? all.value : null));
async function toggleAll() {
  if (expanded.value) return void (expanded.value = false);
  if (all.value) return void (expanded.value = true);
  await showAll();
  if (all.value) expanded.value = true;
}
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
      {{ shown ? `No changes on ${shown.length} spacecraft:` : noChangesLine(group, fleet) }}
    </p>
    <div v-else class="flex flex-wrap items-center gap-2">
      <h3 v-if="fleet" class="m-0 text-md text-bright">{{ groupHeading(group) }}</h3>
      <ApTag v-if="!group.telemetry_enabled" state="off" label="Telemetry off" />
    </div>
    <p v-if="!unchanged && fleet && group.count > 1 && !shown" class="m-0 text-sm text-text-2">
      {{ namesLine(group) }}
    </p>
    <p v-if="shown" :id="namesId" class="m-0 text-sm text-text-2">
      {{ shown.map(craftName).join(", ") }}
    </p>
    <div v-if="showAllLabel(group)">
      <ApButton
        size="compact"
        variant="ghost"
        :aria-expanded="expanded"
        :aria-controls="shown ? namesId : undefined"
        :disabled="loading"
        disabled-reason="Loading…"
        @click="toggleAll"
        >{{ expanded ? "Show fewer" : showAllLabel(group) }}</ApButton
      >
    </div>
    <!-- B6: it answers the person's own click. -->
    <ApCallout v-if="failed" tone="caution" role="alert">
      The names couldn't be loaded. Try again.
    </ApCallout>
    <p v-if="group.first_start" class="m-0 text-md text-text-2">{{ firstStartLine(group) }}</p>
    <ul v-if="!unchanged" class="m-0 flex list-none flex-col gap-1 p-0">
      <li v-for="row in group.rows.items" :key="row.field" class="text-md">
        {{ rowLine(row, group.first_start) }}
      </li>
    </ul>
    <details v-if="unnamedSourceIds(group).length" class="text-xs text-text-3">
      <summary class="cursor-pointer font-mono uppercase">Technical details</summary>
      <p v-for="id in unnamedSourceIds(group)" :key="id" class="m-0 pt-1 font-mono break-all">
        packet source id: {{ id }}
      </p>
    </details>
  </section>
</template>
