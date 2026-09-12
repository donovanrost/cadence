<script setup lang="ts">
import { computed, onBeforeUnmount, ref, watch } from "vue";
import type { OpsPageContext, OpsPagePort } from "@cadence/plugin-sdk/ops-pages";
import type { WidgetFields } from "./contracts";
import { readObservableChoices, record } from "./validation";
const props = defineProps<{
  modelValue: string;
  fields: WidgetFields;
  context: OpsPageContext;
  documentVersion: number;
  stagingRevision: number;
  port: OpsPagePort;
  disabled: boolean;
}>();
const emit = defineEmits<{ "update:modelValue": [value: string] }>();
const query = ref(""),
  loading = ref(false),
  notice = ref("");
const results = ref<ReturnType<typeof readObservableChoices> | null>(null);
const selected = computed(() =>
  props.modelValue
    .split(/[\n,]/)
    .map((s) => s.trim())
    .filter(Boolean),
);
const limit = computed(() =>
  ["value_tile", "state_timeline"].includes(props.fields.type)
    ? 1
    : props.fields.type === "time_series"
      ? 8
      : 24,
);
let generation = 0;
function invalidate() {
  generation++;
  loading.value = false;
  results.value = null;
  notice.value = "";
}
watch(
  () => [
    query.value,
    JSON.stringify(props.fields),
    props.context.organizationId,
    props.context.missionId,
    props.context.resourceId,
    props.documentVersion,
    props.stagingRevision,
    props.disabled,
  ],
  invalidate,
  { flush: "sync" },
);
onBeforeUnmount(invalidate);
async function search() {
  if (props.disabled || loading.value) return;
  const requested = ++generation,
    value = query.value.trim(),
    version = props.documentVersion,
    revision = props.stagingRevision;
  results.value = null;
  notice.value = "";
  if (new TextEncoder().encode(value).length > 256) {
    notice.value = "Use a shorter search.";
    return;
  }
  loading.value = true;
  try {
    const response = record(
      await props.port.execute("search_observables", {
        query: value,
        fields: { ...props.fields },
        expected_version: version,
        expected_revision: revision,
      }),
    );
    if (requested !== generation) return;
    if (response.status !== "ok") throw Error("Unavailable choices");
    results.value = readObservableChoices(
      response.choices,
      props.context,
      version,
      value,
      revision,
    );
  } catch {
    if (requested === generation)
      notice.value =
        "Observable choices are unavailable. Retry the search or reload the saved draft if it changed.";
  } finally {
    if (requested === generation) loading.value = false;
  }
}
function add(value: string) {
  if (
    props.disabled ||
    !results.value?.options.some((o) => o.value === value) ||
    selected.value.includes(value) ||
    selected.value.length >= limit.value
  )
    return;
  emit("update:modelValue", [...selected.value, value].join("\n"));
}
function remove(index: number) {
  if (!props.disabled)
    emit("update:modelValue", selected.value.filter((_, i) => i !== index).join("\n"));
}
</script>
<template>
  <section
    id="editor-observable-picker"
    class="space-y-3 border-t border-base-300 pt-4"
    aria-labelledby="editor-observable-heading"
  >
    <div class="flex justify-between gap-2 text-xs">
      <h3 id="editor-observable-heading" class="font-mono uppercase tracking-wider">Observables</h3>
      <span>{{ selected.length }} / {{ limit }} selected</span>
    </div>
    <ol v-if="selected.length" class="space-y-1" aria-label="Selected observables">
      <li
        v-for="(id, index) in selected"
        :key="`${index}:${id}`"
        class="flex items-center gap-2 border border-base-300 p-2 text-xs"
      >
        <span class="font-mono break-all flex-1">{{ id }}</span
        ><button
          type="button"
          class="btn btn-ghost btn-xs"
          :disabled="disabled"
          :aria-label="`Remove ${id}`"
          :data-remove-observable="index"
          @click="remove(index)"
        >
          Remove
        </button>
      </li>
    </ol>
    <label for="editor-observable-query" class="editor-field"
      >Find an observable
      <input
        id="editor-observable-query"
        v-model="query"
        type="search"
        maxlength="256"
        :disabled="disabled"
        class="input input-bordered input-sm w-full"
        placeholder="Name, ID, or description"
        @keydown.enter.prevent="search"
      />
    </label>
    <button
      id="editor-observable-search"
      type="button"
      class="btn btn-sm btn-outline w-full"
      :disabled="disabled || loading"
      @click="search"
    >
      {{ loading ? "Searching…" : "Search catalog" }}
    </button>
    <p v-if="notice" id="editor-observable-error" role="status" class="text-xs text-warning">
      {{ notice }}
    </p>
    <div v-if="results" id="editor-observable-results" :aria-busy="loading" class="space-y-2">
      <p v-if="!results.options.length" role="status" class="text-xs text-base-content/60">
        No matching observables for this widget and scope.
      </p>
      <ul class="max-h-64 overflow-y-auto space-y-1" aria-label="Observable search results">
        <li v-for="option in results.options" :key="option.value">
          <button
            type="button"
            class="w-full text-left border border-base-300 p-2 hover:border-primary disabled:opacity-50"
            :data-add-observable="option.value"
            :disabled="disabled || selected.includes(option.value) || selected.length >= limit"
            @click="add(option.value)"
          >
            <span class="block text-xs font-semibold">{{ option.label }}</span
            ><span class="block text-xs font-mono break-all text-base-content/70">{{
              option.value
            }}</span
            ><span class="block text-xs text-base-content/50">{{ option.description }}</span>
          </button>
        </li>
      </ul>
      <p v-if="results.more" role="status" class="text-xs text-base-content/60">
        More matches are available. Refine your search.
      </p>
    </div>
    <details class="text-xs text-base-content/60">
      <summary class="cursor-pointer">Enter IDs directly</summary>
      <label for="editor-observables" class="editor-field mt-2"
        >Observable IDs<textarea
          id="editor-observables"
          :value="modelValue"
          :disabled="disabled"
          rows="3"
          maxlength="6168"
          spellcheck="false"
          class="textarea textarea-bordered font-mono text-xs w-full"
          @input="emit('update:modelValue', ($event.target as HTMLTextAreaElement).value)"
        />
      </label>
      <p>
        One ID per line. Existing IDs remain selected even if they are no longer in the catalog.
        Saving validates the binding.
      </p>
    </details>
  </section>
</template>
<style scoped>
.editor-field {
  display: flex;
  flex-direction: column;
  gap: 0.375rem;
  font-size: 0.75rem;
}
</style>
