<script setup lang="ts">
import { ref, watch } from "vue";
import CadencePane from "@cadence/ui/CadencePane.vue";
import CadenceInfiniteScroll from "@cadence/ui/CadenceInfiniteScroll.vue";
import type { CatalogResults } from "./useCatalogResults";
import type { Catalog, Command, Query } from "../../shared/command-draft/contracts";
const props = defineProps<{
  catalog: Catalog | null;
  results: CatalogResults<Command>;
  selectedCount: number;
  disabled: boolean;
}>();
const emit = defineEmits<{
  browse: [query: Partial<Query>];
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
const list = ref<HTMLElement>(),
  searchInput = ref<HTMLInputElement>();
function focusCommand(id: string) {
  const button = Array.from(list.value?.querySelectorAll<HTMLButtonElement>("button") ?? []).find(
    (element) => element.dataset.workspaceCommand === id,
  );
  (button ?? searchInput.value)?.focus();
}
defineExpose({ focusCommand });
</script>
<template>
  <CadencePane
    ref="pane"
    id="command-workspace-catalog"
    title="Command catalog"
    icon="hero-command-line"
    :count="results.entries.length"
  >
    <template #toolbar>
      <div class="cw-search" role="search" aria-label="Commands">
        <span class="hero-magnifying-glass cw-icon" aria-hidden="true" /><input
          id="workspace-command-search"
          ref="searchInput"
          :value="results.query"
          @input="search"
          type="search"
          aria-label="Find commands"
          placeholder="Find a command…"
          maxlength="240"
          :disabled="disabled"
        />
      </div>
      <p class="cw-context">
        <span class="hero-cursor-arrow-rays cw-icon" aria-hidden="true" />{{
          selectedCount
            ? `${selectedCount} endpoints selected · validated together on preview`
            : "Select spacecraft and endpoints, then prepare a command."
        }}
      </p>
    </template>
    <div ref="list" class="cw-command-list">
      <button
        v-for="command in results.entries"
        :key="command.id"
        type="button"
        class="cw-command"
        :data-workspace-command="command.id"
        :aria-pressed="catalog?.selected_command?.id === command.id"
        :disabled="disabled"
        @click="emit('browse', { command: command.id })"
      >
        <span class="hero-command-line cw-command-icon" aria-hidden="true" /><span
          class="cw-command-copy"
          ><strong>{{ command.display_name || command.name }}</strong
          ><code>{{ command.name }}</code
          ><span v-if="catalog?.selected_command?.id === command.id" class="cw-subtle">{{
            `${catalog.selected_command.arguments.length} arguments · ${catalog.selected_command.hazardous ? "Hazardous" : catalog.selected_command.critical ? "Critical" : "Standard"}`
          }}</span></span
        ><span class="hero-chevron-right cw-icon" aria-hidden="true" />
      </button>
      <p v-if="!results.entries.length && !results.loading && !results.error" class="cw-empty">
        {{ catalog ? "No commands match this search." : "No active command model is available." }}
      </p>
    </div>
    <CadenceInfiniteScroll
      :root="pane?.scrollElement ?? null"
      :has-more="results.hasMore"
      :loading="results.loading"
      :error="results.error"
      :disabled="disabled"
      label="Loading commands…"
      @load-more="emit('loadMore')"
      @retry="emit('retry')"
    />
    <template #footer>
      <span
        >Mission model catalog<span v-if="catalog">
          · generation {{ catalog.basis.generation }}</span
        ></span
      >
    </template>
  </CadencePane>
</template>
