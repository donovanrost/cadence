<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import CadenceBadge from "@cadence/ui/CadenceBadge.vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceCheckbox from "@cadence/ui/CadenceCheckbox.vue";
import CadenceDialog from "@cadence/ui/CadenceDialog.vue";
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";
import type { VersionComparison, VersionList } from "./contracts";
import type { DashboardPageState } from "./useDashboardPage";
import { formatUtc } from "./time-range";
import ChangeList from "./ChangeList.vue";
import JsonDiffView from "./JsonDiffView.vue";

/** Grafana's Versions view: history, compare two, restore as a new version. */
const props = defineProps<{ state: DashboardPageState; author: boolean }>();
const list = ref<VersionList | null>(null);
const error = ref("");
const selected = ref<number[]>([]);
const comparison = ref<VersionComparison | null>(null);
const showJson = ref(false);
const restoring = ref<number | null>(null);

async function load() {
  error.value = "";
  try {
    list.value = await props.state.versions();
  } catch {
    error.value = "Version history is unavailable. Try again.";
  }
}
onMounted(load);

function toggle(version: number, on: boolean) {
  selected.value = on
    ? [...selected.value.filter((v) => v !== version), version].slice(-2)
    : selected.value.filter((v) => v !== version);
}
const pair = computed(() => {
  const [a, b] = selected.value;
  return a !== undefined && b !== undefined ? ([Math.min(a, b), Math.max(a, b)] as const) : null;
});
async function compare() {
  if (!pair.value) return;
  error.value = "";
  try {
    comparison.value = await props.state.compare(pair.value[0], pair.value[1]);
    showJson.value = false;
  } catch {
    error.value = "These versions could not be compared.";
  }
}
async function restore() {
  const version = restoring.value;
  restoring.value = null;
  if (version !== null && (await props.state.restore(version))) {
    comparison.value = null;
    selected.value = [];
    await load();
  }
}
const editingDirty = computed(() => props.state.dirty.value);
</script>

<template>
  <div class="space-y-4">
    <p v-if="error" role="alert" class="text-sm text-error">{{ error }}</p>
    <template v-if="comparison">
      <header class="flex flex-wrap items-center gap-2">
        <button
          type="button"
          class="cadence-icon-button"
          aria-label="Back to versions"
          @click="comparison = null"
        >
          <CadenceIcon name="hero-arrow-left" />
        </button>
        <h3 class="text-sm font-semibold">
          Comparing v{{ comparison.from }} ↔ v{{ comparison.to }}
        </h3>
        <CadenceButton
          v-if="author && comparison.from !== list?.current_version"
          class="ml-auto"
          size="sm"
          variant="danger"
          @click="restoring = comparison.from"
        >
          <CadenceIcon name="hero-arrow-uturn-left" />Restore to v{{ comparison.from }}
        </CadenceButton>
      </header>
      <ChangeList :changes="comparison.changes" />
      <CadenceButton size="sm" variant="quiet" @click="showJson = !showJson">
        {{ showJson ? "Hide JSON diff" : "View JSON diff" }}
      </CadenceButton>
      <JsonDiffView v-if="showJson" :before="comparison.from_json" :after="comparison.to_json" />
    </template>
    <template v-else-if="list">
      <p class="text-xs text-base-content/70">Select two versions to compare them.</p>
      <ul class="divide-y divide-base-300/60 border-y border-base-300/60">
        <li v-for="row in list.versions" :key="row.version" class="flex items-start gap-3 py-2.5">
          <CadenceCheckbox
            :model-value="selected.includes(row.version)"
            @update:model-value="(on) => toggle(row.version, on)"
          >
            <span class="sr-only">Select version {{ row.version }}</span>
          </CadenceCheckbox>
          <div class="min-w-0 flex-1">
            <p class="flex items-center gap-2">
              <span class="font-mono text-sm font-semibold">v{{ row.version }}</span>
              <CadenceBadge v-if="row.current" tone="success">Current</CadenceBadge>
            </p>
            <p class="break-words text-sm">
              {{
                row.message ??
                (row.restored_from ? `Restored from version ${row.restored_from}` : "No note")
              }}
            </p>
            <p class="font-mono text-xs text-base-content/60">
              {{ row.saved_at ? `${formatUtc(row.saved_at)} UTC` : "—" }}
              <template v-if="row.saved_by"> · {{ row.saved_by }}</template>
            </p>
          </div>
          <CadenceButton
            v-if="author && !row.current"
            size="xs"
            variant="outline"
            @click="restoring = row.version"
          >
            <CadenceIcon name="hero-arrow-uturn-left" size="xs" />Restore
          </CadenceButton>
        </li>
      </ul>
      <CadenceButton size="sm" :disabled="!pair" @click="compare">
        <CadenceIcon name="hero-arrows-right-left" />Compare versions
      </CadenceButton>
    </template>
    <p v-else-if="!error" class="text-sm text-base-content/70">Loading versions…</p>
    <CadenceDialog
      :open="restoring !== null"
      tone="danger"
      :title="`Restore version ${restoring}?`"
      :description="`This saves a copy of version ${restoring} as the new current version. History is kept.${editingDirty ? ' Your unsaved changes will be lost.' : ''}`"
      @update:open="(open) => !open && (restoring = null)"
    >
      <template #actions>
        <CadenceButton variant="quiet" size="sm" @click="restoring = null">Cancel</CadenceButton>
        <CadenceButton variant="danger" size="sm" :loading="state.pending.value" @click="restore">
          Restore version {{ restoring }}
        </CadenceButton>
      </template>
    </CadenceDialog>
  </div>
</template>
