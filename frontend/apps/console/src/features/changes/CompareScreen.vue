<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useRemoteQuery } from "@/api";
import { useMissionScope } from "@/shell";
import { ApBreadcrumb, ApEmptyState, ApPageHeader, ApRemote, plural, type ApCrumb } from "@/ui";
import EntryList from "./EntryList.vue";
import { fetchComparison } from "./compare.ts";

/** Changes.md §4 Compare (`revisions/r4...r6`): the combined diff, grouped by entity. */
const scope = useMissionScope();
const route = useRoute("setup.revisions.compare");
const from = computed(() => Number(route.params.from));
const to = computed(() => Number(route.params.to));
const key = computed(() => ({ missionId: scope.value.mission.id, from: from.value, to: to.value }));
const { state, refetch } = useRemoteQuery(key, fetchComparison);
const crumbs = computed((): readonly ApCrumb[] => [
  { label: "Revisions", to: { name: "setup.revisions" } },
  { label: `r${from.value} ↔ r${to.value}`, literal: true },
]);
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1100px] flex-col gap-4">
    <ApBreadcrumb :crumbs="crumbs" />
    <ApPageHeader :label="`${scope.mission.name} · configuration`" title="Compare" size="reading">
      <template #title
        >Compare <span class="font-mono normal-case">r{{ from }} ↔ r{{ to }}</span></template
      >
      <template v-if="state.status === 'ready'" #subtitle>
        <span class="text-md text-text-3"
          >{{
            plural(
              state.value.entries.length,
              "part of the configuration",
              "parts of the configuration",
            )
          }}
          changed after r{{ from }}, up to r{{ to }}.</span
        >
      </template>
    </ApPageHeader>
    <ApRemote :state="state" loading-label="Comparing…" @retry="refetch">
      <template #default="{ value }">
        <ApEmptyState
          v-if="value.entries.length === 0"
          headline="Nothing differs"
          :sentence="`r${from} and r${to} have the same configuration.`"
        />
        <EntryList v-else :entries="value.entries" />
      </template>
    </ApRemote>
  </div>
</template>
