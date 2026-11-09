<script setup lang="ts">
import { computed } from "vue";
import { useConsoleScope } from "@/shell";
import { ApEmptyState, ApPageHeader, ApPanel, ApTable, plural, type ApColumn } from "@/ui";

/** Organization › Missions: the org's missions from the session bootstrap (no extra request). */
const scope = useConsoleScope();
const organization = computed(() =>
  scope.value.kind === "organization" || scope.value.kind === "mission"
    ? scope.value.organization
    : null,
);
const columns: readonly ApColumn[] = [
  { key: "name", label: "Mission" },
  { key: "slug", label: "Slug", mono: true },
  { key: "open", label: "Open", hiddenLabel: true },
];
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApPageHeader
      :label="`${organization?.name ?? ''} · organization`"
      :title="organization ? plural(organization.missions.length, 'mission') : 'Missions'"
      size="reading"
    />
    <ApPanel index="M1" title="Missions" flush>
      <ApEmptyState
        v-if="!organization || organization.missions.length === 0"
        state="off"
        headline="No missions yet"
        sentence="A mission groups the spacecraft, profiles and catalog operated together."
      />
      <ApTable
        v-else
        :columns="columns"
        :rows="organization.missions"
        :row-key="(m) => m.id"
        caption="Missions"
      >
        <template #cell-name="{ row }">
          <RouterLink
            :to="{ name: 'setup.readiness', params: { org: organization.slug, mission: row.slug } }"
            class="font-semibold text-readout no-underline hover:text-bright hover:underline max-md:hit-44"
            >{{ row.name }}</RouterLink
          >
        </template>
        <template #cell-open="{ row }">
          <RouterLink
            :to="{ name: 'ops.now', params: { org: organization.slug, mission: row.slug } }"
            class="text-text-3 no-underline hover:text-readout max-md:hit-44"
            >Open in Ops →</RouterLink
          >
        </template>
      </ApTable>
    </ApPanel>
  </div>
</template>
