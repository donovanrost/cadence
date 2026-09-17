<script setup lang="ts">
import { computed, ref, watch } from "vue";
import CadenceInfiniteScroll from "@cadence/ui/CadenceInfiniteScroll.vue";
import type { CatalogResults } from "./useCatalogResults";
import CadencePane from "@cadence/ui/CadencePane.vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceSelectionTile from "@cadence/ui/CadenceSelectionTile.vue";
import { targetBasis, type Catalog, type Target } from "../../shared/command-draft/contracts";
import SpacecraftSchematic from "./SpacecraftSchematic.vue";
const props = defineProps<{
  catalog: Catalog | null;
  results: CatalogResults<Target>;
  selected: readonly Target[];
  names: Readonly<Record<string, string>>;
  disabled: boolean;
}>();
const emit = defineEmits<{
  toggle: [target: Target];
  clear: [];
  selectVisible: [];
  search: [value: string];
  loadMore: [];
  retry: [];
}>();
const pane = ref<InstanceType<typeof CadencePane>>();
watch(
  () => props.results.scrollKey,
  () => pane.value?.scrollToStart(),
  { flush: "post" },
);
function search(event: Event) {
  if (event.target instanceof HTMLInputElement) emit("search", event.target.value);
}
const selectedIds = computed(() => new Set(props.selected.map((item) => item.id)));
function title(target: Target) {
  return target.spacecraft_id
    ? props.names[target.spacecraft_id] || target.spacecraft_id
    : target.name || target.id;
}
</script>
<template>
  <CadencePane
    ref="pane"
    id="command-workspace-fleet"
    title="Spacecraft & endpoints"
    icon="hero-square-3-stack-3d"
    :count="`${selected.length} selected`"
  >
    <template #toolbar>
      <div class="cw-search" role="search" aria-label="Spacecraft and endpoints">
        <span class="hero-magnifying-glass cw-icon" aria-hidden="true" />
        <input
          id="workspace-target-search"
          :value="results.query"
          @input="search"
          type="search"
          aria-label="Find spacecraft or endpoints"
          placeholder="Find spacecraft or endpoint…"
          maxlength="240"
          :disabled="disabled"
        />
      </div>
      <div class="cw-inline-actions">
        <CadenceButton
          size="xs"
          variant="quiet"
          :disabled="disabled || !results.entries.length || results.loading"
          @click="emit('selectVisible')"
          >{{ results.entries.length > 25 ? "Select first 25" : "Select visible" }}</CadenceButton
        ><CadenceButton
          size="xs"
          variant="quiet"
          :disabled="disabled || !selected.length"
          @click="emit('clear')"
          >Clear</CadenceButton
        ><span class="cw-subtle">Up to 25 endpoints</span>
      </div>
    </template>
    <div class="cw-fleet-grid">
      <CadenceSelectionTile
        v-for="target in results.entries"
        :key="target.id"
        layout="responsive"
        :selected="selectedIds.has(target.id)"
        :label="`Select ${title(target)} · ${target.name || target.id}`"
        :disabled="disabled"
        :data-workspace-target="target.id"
        @click="emit('toggle', target)"
      >
        <template #title>{{ title(target) }}</template>
        <template #visual
          ><SpacecraftSchematic
            v-if="target.spacecraft_id"
            :selected="selectedIds.has(target.id)" /><span
            v-else
            class="hero-cpu-chip cw-endpoint-visual"
            aria-hidden="true"
        /></template>
        <strong>{{ target.name || "Command endpoint" }}</strong>
        <span class="cw-subtle cw-truncate">{{ target.source_ref || target.id }}</span>
        <span v-if="catalog?.target_bases" class="cw-subtle">{{
          !targetBasis(catalog, target.id)
            ? "Commanding not active"
            : targetBasis(catalog, target.id)?.compatible
              ? "Catalog compatible"
              : "Different command definition"
        }}</span>
        <template #footer
          ><span>SCID {{ target.scid ?? "—" }}</span
          ><span>{{ target.spacecraft_id ? "Spacecraft" : "Unassigned endpoint" }}</span></template
        >
      </CadenceSelectionTile>
      <p
        v-if="catalog && !results.entries.length && !results.loading && !results.error"
        class="cw-empty"
      >
        No endpoints match this search.
      </p>
      <p v-if="!catalog" class="cw-empty">
        Activate a command model to browse targets and commands.
      </p>
    </div>
    <CadenceInfiniteScroll
      :root="pane?.scrollElement ?? null"
      :has-more="results.hasMore"
      :loading="results.loading"
      :error="results.error"
      :disabled="disabled"
      label="Loading endpoints…"
      @load-more="emit('loadMore')"
      @retry="emit('retry')"
    />
    <template #footer
      ><span>{{ results.entries.length }} endpoints</span></template
    >
  </CadencePane>
</template>
