<script setup lang="ts">
import { computed, ref } from "vue";
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceCheckbox from "@cadence/ui/CadenceCheckbox.vue";
import CadenceSegmentedControl from "@cadence/ui/CadenceSegmentedControl.vue";
import CadenceTextArea from "@cadence/ui/CadenceTextArea.vue";
import type { VersionComparison } from "./contracts";
import type { DashboardPageState } from "./useDashboardPage";
import ChangeList from "./ChangeList.vue";
import JsonDiffView from "./JsonDiffView.vue";

/** Grafana's save drawer: an optional note, the pending changes, and opt-in defaults. */
const props = defineProps<{ state: DashboardPageState }>();
const emit = defineEmits<{ close: [] }>();

const tab = ref("details");
const message = ref("");
const saveTime = ref(false);
const saveScope = ref(false);
const diff = ref<VersionComparison | null>(null);
const diffError = ref("");

const changes = computed(() =>
  props.state.page.value.mode === "edit" ? props.state.page.value.edit.changes : [],
);
const params = computed(
  () => new URLSearchParams(typeof window === "undefined" ? "" : window.location.search),
);
const timeSelected = computed(() => params.value.has("from") && params.value.has("to"));
const scopeSelected = computed(() => params.value.has("spacecraft"));
const savable = computed(() => props.state.dirty.value || saveTime.value || saveScope.value);
const tabs = computed(() => [
  { value: "details", label: "Details" },
  { value: "changes", label: `Changes (${changes.value.length})` },
]);

async function showDiff() {
  diffError.value = "";
  try {
    diff.value = await props.state.compareStaged();
  } catch {
    diffError.value = "The JSON diff is unavailable. Try again.";
  }
}

async function save() {
  const defaults =
    saveTime.value || saveScope.value
      ? { time: saveTime.value, scope: saveScope.value }
      : undefined;
  const saved = await props.state.save({
    ...(message.value.trim() ? { message: message.value.trim() } : {}),
    ...(defaults ? { defaults } : {}),
  });
  if (saved) emit("close");
}
</script>

<template>
  <form class="space-y-4" @submit.prevent="save">
    <CadenceSegmentedControl v-model="tab" label="Save dashboard" :options="tabs" />
    <section v-if="tab === 'details'" class="space-y-4">
      <CadenceTextArea
        id="dashboard-save-message"
        v-model="message"
        label="Message"
        :maxlength="1000"
        placeholder="Add a note to describe your changes (optional)."
      />
      <div v-if="timeSelected || scopeSelected" class="space-y-2">
        <CadenceCheckbox v-if="timeSelected" v-model="saveTime">
          Make the current time range the dashboard default
        </CadenceCheckbox>
        <CadenceCheckbox v-if="scopeSelected" v-model="saveScope">
          Make the selected spacecraft the dashboard default
        </CadenceCheckbox>
      </div>
      <p v-if="!savable" class="text-sm text-base-content/70">No changes to save.</p>
    </section>
    <section v-else class="space-y-4">
      <ChangeList :changes="changes" />
      <CadenceButton v-if="!diff && changes.length" size="sm" variant="quiet" @click="showDiff">
        View JSON diff
      </CadenceButton>
      <p v-if="diffError" role="alert" class="text-xs text-error">{{ diffError }}</p>
      <JsonDiffView v-if="diff" :before="diff.from_json" :after="diff.to_json" />
    </section>
    <footer class="flex justify-end gap-2 border-t border-base-300/60 pt-4">
      <CadenceButton variant="quiet" size="sm" @click="emit('close')">Cancel</CadenceButton>
      <CadenceButton
        type="submit"
        variant="primary"
        size="sm"
        :loading="state.pending.value"
        :disabled="!savable"
      >
        Save
      </CadenceButton>
    </footer>
  </form>
</template>
