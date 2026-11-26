<script setup lang="ts">
import { computed } from "vue";
import { ApStatusMark, ApTable, ApTag, formatCount, type ApColumn } from "@/ui";
import { compositionTitle, isComposed, madeOfLine } from "@/features/catalog/composition.ts";
import {
  catalogRevText,
  lastChangeText,
  manyOverrides,
  protocolLine,
  type ProfileSummary,
} from "./api.ts";

/** Profile rows; the Name cell links to the profile page (Profile.md list). */
const props = defineProps<{ rows: readonly ProfileSummary[] }>();
/** Overrides / Last changed appear once the list read carries them (asked of api). */
const columns = computed((): readonly ApColumn[] => {
  const overrides = props.rows.some((r) => r.overrideCount !== null);
  const changed = props.rows.some((r) => r.lastChange !== null);
  return [
    { key: "name", label: "Name" },
    { key: "version", label: "Version", mono: true },
    { key: "spacecraft", label: "Spacecraft", mono: true, align: "end" },
    ...(overrides
      ? [{ key: "overrides", label: "Overrides", mono: true, align: "end" as const }]
      : []),
    { key: "catalog", label: "Catalog", mono: true },
    { key: "protocols", label: "Protocols" },
    ...(changed ? [{ key: "changed", label: "Last changed", mono: true }] : []),
  ];
});
</script>

<template>
  <ApTable :columns="columns" :rows="rows" :row-key="(row) => row.id" caption="Profiles">
    <template #cell-name="{ row }">
      <RouterLink
        :to="{ name: 'setup.profile', params: { profileId: row.id } }"
        class="text-readout no-underline hover:text-bright hover:underline max-md:hit-44"
        >{{ row.name }}</RouterLink
      >
    </template>
    <template #cell-version="{ row }">v{{ row.version }}</template>
    <template #cell-spacecraft="{ row }">
      {{ formatCount(row.spacecraftCount) }}
      <span v-if="row.spacecraftOnOlderVersions > 0" class="block font-sans text-xs text-text-3"
        >{{ formatCount(row.spacecraftOnOlderVersions) }} on older versions</span
      >
    </template>
    <template #cell-catalog="{ row }">
      <!-- U109: a composed profile reads Composition 3 with Made of as the muted second line;
        COMPOSED only where it could pass for one catalog (no number, Made of alone). -->
      <template v-if="isComposed(row.composition)">
        <span v-if="compositionTitle(row.composition)">{{
          compositionTitle(row.composition)
        }}</span>
        <ApTag v-else state="neutral" label="Composed" />
        <span class="block font-sans text-xs text-text-3">{{ madeOfLine(row.composition) }}</span>
      </template>
      <span v-else-if="row.catalogRevision">{{
        catalogRevText(row.catalogRevision) ?? "a catalog revision"
      }}</span>
      <span v-else class="font-sans text-text-3">Set per spacecraft</span>
    </template>
    <template #cell-overrides="{ row }">
      <!-- a11y B2: many overrides carry the caution mark and a word, not colour alone. -->
      <span
        class="inline-flex items-center gap-1.5"
        :class="manyOverrides(row) ? 'text-caution-text' : ''"
        ><ApStatusMark v-if="manyOverrides(row)" state="caution" />{{
          formatCount(row.overrideCount ?? 0)
        }}<span v-if="manyOverrides(row)" class="sr-only">, many overrides</span></span
      >
    </template>
    <template #cell-changed="{ row }">{{
      row.lastChange ? lastChangeText(row.lastChange) : "—"
    }}</template>
    <template #cell-protocols="{ row }">
      <span class="text-text-2">{{ protocolLine(row) }}</span>
    </template>
  </ApTable>
</template>
