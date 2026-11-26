<script setup lang="ts">
import { computed, ref, useId } from "vue";
import { usePagedQuery, type PageFetcher } from "@/api/index.ts";
import { ApButton, ApCallout, ApTag, formatCount } from "@/ui";
import {
  firstStartLine,
  groupHeading,
  namesLine,
  noChangesLine,
  rowLine,
  showNamesLabel,
  unnamedSourceIds,
} from "./changesWords.ts";
import {
  craftName,
  fetchGroupNames,
  type ChangeGroup,
  type CraftRef,
  type GroupNamesKey,
} from "./configurationChanges.ts";
import type { DetailKey } from "./api.ts";

/** #235 (ux U94): one group of craft with identical changes, or the no-change group. */
const props = defineProps<{ group: ChangeGroup; requestKey: DetailKey; fleet: boolean }>();
const unchanged = computed(
  () => props.group.rows.items.length === 0 && props.group.rows.unshown.length === 0,
);

/** The names route pages by offset (100 a page); its next offset is the page's cursor. */
const fetchNames: PageFetcher<Omit<GroupNamesKey, "offset">, CraftRef, undefined> = async (
  key,
  cursor,
  signal,
) => {
  const r = await fetchGroupNames({ ...key, offset: cursor === null ? 0 : Number(cursor) }, signal);
  if (!r.ok) return r;
  const next = r.value.next_offset;
  return {
    ok: true,
    value: {
      items: r.value.spacecraft,
      next: next === null ? null : String(next),
      meta: undefined,
    },
  };
};

/**
 * #176 (U72): the names are read through usePagedQuery the first time the disclosure opens, a page
 * at a time with Load more, never every page in one click. They stay loaded when it closes.
 * #244 (B3, A5): the toggle is a disclosure that stays mounted with aria-expanded, so focus is
 * never dropped.
 */
const opened = ref(false);
const expanded = ref(false);
const names = usePagedQuery(
  computed(() => (opened.value ? { ...props.requestKey, group: props.group.index } : null)),
  fetchNames,
  (craft) => craft.spacecraft_id,
);
const namesId = useId();
const shown = computed(() =>
  expanded.value && names.state.value.status === "ready" ? names.state.value.value : null,
);
function toggle() {
  if (expanded.value) return void (expanded.value = false);
  opened.value = true;
  expanded.value = true;
}
</script>

<template>
  <section class="flex flex-col gap-2 border-t border-line pt-3 first:border-t-0 first:pt-0">
    <p v-if="unchanged" class="m-0 text-md text-text-2">
      {{
        shown
          ? `No changes on ${formatCount(group.count)} spacecraft:`
          : noChangesLine(group, fleet)
      }}
    </p>
    <div v-else class="flex flex-wrap items-center gap-2">
      <h3 v-if="fleet" class="m-0 text-md text-bright">{{ groupHeading(group) }}</h3>
      <ApTag v-if="!group.telemetry_enabled" state="off" label="Telemetry off" />
    </div>
    <p v-if="!unchanged && fleet && group.count > 1 && !shown" class="m-0 text-sm text-text-2">
      {{ namesLine(group) }}
    </p>
    <ul
      v-if="shown"
      :id="namesId"
      class="m-0 flex list-none flex-col gap-0.5 p-0 text-sm text-text-2"
    >
      <li v-for="craft in shown.items" :key="craft.spacecraft_id">{{ craftName(craft) }}</li>
    </ul>
    <div v-if="shown && shown.next !== null" class="flex flex-wrap items-center gap-3">
      <span class="font-mono text-xs text-text-3 uppercase">
        Showing {{ formatCount(shown.items.length) }} of {{ formatCount(group.count) }}
      </span>
      <ApButton
        size="compact"
        variant="ghost"
        :disabled="names.moreBusy.value"
        disabled-reason="Loading…"
        @click="names.more()"
        >Load more</ApButton
      >
      <!-- U72, B6: mounted with the row, before any failure, so a failed Load more is announced. -->
      <span role="alert" class="text-sm text-caution-text">{{
        names.moreError.value ? "More names couldn't load. Try Load more again." : ""
      }}</span>
    </div>
    <p
      v-if="expanded && names.state.value.status === 'loading'"
      role="status"
      class="m-0 font-mono text-xs text-text-3 uppercase"
    >
      Loading names…
    </p>
    <div v-if="showNamesLabel(group, expanded)">
      <ApButton
        size="compact"
        variant="ghost"
        :aria-expanded="expanded"
        :aria-controls="shown ? namesId : undefined"
        @click="toggle"
        >{{ showNamesLabel(group, expanded) }}</ApButton
      >
    </div>
    <!-- B6: it answers the person's own click. -->
    <ApCallout v-if="expanded && names.state.value.status === 'failed'" tone="caution" role="alert">
      The names couldn't be loaded.
      <template #action>
        <ApButton size="compact" variant="secondary" @click="names.refetch()">Try again</ApButton>
      </template>
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
