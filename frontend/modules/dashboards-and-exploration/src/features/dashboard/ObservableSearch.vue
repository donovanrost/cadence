<script setup lang="ts">
import { onBeforeUnmount, ref } from "vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceIconButton from "@cadence/ui/CadenceIconButton.vue";
import CadenceTextField from "@cadence/ui/CadenceTextField.vue";
import type { WidgetFields } from "./contracts";
import { observableLimit } from "./widget-form";

type Choice = { value: string; label: string; description: string };
const props = defineProps<{
  fields: WidgetFields;
  search: (query: string, fields: WidgetFields) => Promise<{ options: Choice[]; more: boolean }>;
}>();
const selected = defineModel<string[]>({ required: true });
const query = ref("");
const results = ref<{ options: Choice[]; more: boolean } | null>(null);
const loading = ref(false);
const error = ref("");
let generation = 0;
onBeforeUnmount(() => generation++);

async function run() {
  const requested = ++generation;
  loading.value = true;
  error.value = "";
  try {
    const found = await props.search(query.value.trim(), props.fields);
    if (requested === generation) results.value = found;
  } catch {
    if (requested === generation) error.value = "Search is unavailable. Try again.";
  } finally {
    if (requested === generation) loading.value = false;
  }
}
function add(value: string) {
  if (selected.value.includes(value)) return;
  const limit = observableLimit(props.fields.type);
  selected.value = limit === 1 ? [value] : [...selected.value, value].slice(0, limit);
}
const remove = (value: string) => (selected.value = selected.value.filter((v) => v !== value));
</script>

<template>
  <div class="space-y-2">
    <span class="hud-label">Observables · up to {{ observableLimit(fields.type) }}</span>
    <ul v-if="selected.length" class="space-y-1">
      <li
        v-for="value in selected"
        :key="value"
        class="flex items-center gap-2 rounded-sm bg-base-300/40 pl-2 font-mono text-xs"
      >
        <span class="min-w-0 flex-1 truncate">{{ value }}</span>
        <CadenceIconButton icon="hero-x-mark" :label="`Remove ${value}`" @click="remove(value)" />
      </li>
    </ul>
    <p v-else class="text-xs text-base-content/60">No observables bound yet.</p>
    <form class="flex items-end gap-2" @submit.prevent="run">
      <div class="min-w-0 flex-1">
        <CadenceTextField
          id="dashboard-observable-query"
          v-model="query"
          label="Find observables"
          placeholder="Point name or ID"
        />
      </div>
      <CadenceButton type="submit" size="sm" :loading="loading">Search</CadenceButton>
    </form>
    <p v-if="error" role="alert" class="text-xs text-error">{{ error }}</p>
    <ul v-if="results" class="max-h-56 space-y-0.5 overflow-auto">
      <li v-for="option in results.options" :key="option.value" class="cadence-menu-item">
        <button
          type="button"
          :disabled="selected.includes(option.value)"
          @click="add(option.value)"
        >
          <span class="min-w-0 flex-1">
            <span class="block truncate">{{ option.label }}</span>
            <span class="block truncate font-mono text-[0.65rem] text-base-content/60">{{
              option.description || option.value
            }}</span>
          </span>
        </button>
      </li>
      <li v-if="!results.options.length" class="px-2 text-xs text-base-content/60">No matches.</li>
      <li v-if="results.more" class="px-2 text-xs text-base-content/60">
        More matches — refine the search.
      </li>
    </ul>
  </div>
</template>
