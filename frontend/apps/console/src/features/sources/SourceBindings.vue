<script setup lang="ts">
import { computed, ref } from "vue";
import {
  ApButton,
  ApCallout,
  ApEmptyState,
  ApPanel,
  ApSelect,
  ApSheet,
  ApTable,
  type ApColumn,
} from "@/ui";
import type { DataSource } from "./api.ts";
import { sourceFailure } from "./present.ts";
import { switchBinding, type SourceBinding } from "./writes.ts";

/** S2 · which logical sources read from this source; W3 switches one to another source. */
const props = defineProps<{
  missionId: string;
  bindings: readonly SourceBinding[];
  sources: readonly DataSource[];
  editable: boolean;
}>();
const emit = defineEmits<{ done: [note: { tone: "nominal" | "crit"; text: string }] }>();
const columns = computed<readonly ApColumn[]>(() => [
  { key: "logical", label: "Logical source", mono: true },
  { key: "reads", label: "Reads from" },
  { key: "status", label: "Status" },
  ...(props.editable ? [{ key: "switch", label: "Switch", hiddenLabel: true }] : []),
]);
const nameOf = (id: string) => props.sources.find((s) => s.id === id)?.display_name ?? id;
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const picked = ref<SourceBinding | null>(null);
const target = ref("");
const failure = ref<string | null>(null);
const busy = ref(false);
const choices = computed(() =>
  props.sources
    .filter((s) => s.shared !== true || s.id === picked.value?.data_source_id)
    .map((s) => ({ value: s.id, label: s.display_name })),
);
function open(b: SourceBinding) {
  picked.value = b;
  target.value = b.data_source_id;
  failure.value = null;
  sheet.value?.open();
}
async function submit() {
  const b = picked.value;
  if (!b || busy.value || target.value === b.data_source_id) return;
  busy.value = true;
  try {
    const r = await switchBinding(props.missionId, b.id, {
      data_source_id: target.value,
      expected_data_source_id: b.data_source_id,
    });
    if (!r.ok) return void (failure.value = sourceFailure(r.error));
    sheet.value?.close();
    emit("done", {
      tone: "nominal",
      text: `${b.logical_source} now reads from ${nameOf(target.value)}.`,
    });
  } finally {
    busy.value = false;
  }
}
</script>

<template>
  <ApPanel index="S2" title="Bindings" flush>
    <ApEmptyState
      v-if="bindings.length === 0"
      state="off"
      headline="Nothing reads from it"
      sentence="No logical source is bound to this source."
    />
    <ApTable v-else :columns="columns" :rows="bindings" :row-key="(b) => b.id" caption="Bindings">
      <template #cell-reads="{ row }">{{ nameOf(row.data_source_id) }}</template>
      <template #cell-status="{ row }"
        ><span class="text-text-2">{{ row.status.replaceAll("_", " ") }}</span></template
      >
      <template #cell-switch="{ row }"
        ><ApButton size="compact" variant="ghost" @click="open(row)">Switch…</ApButton></template
      >
    </ApTable>
  </ApPanel>
  <ApSheet ref="sheet" :title="`Switch ${picked?.logical_source ?? ''}`" width="narrow">
    <div class="flex flex-col gap-3">
      <ApSelect v-model="target" label="Read from" :options="choices" />
      <ApCallout v-if="failure" tone="crit">{{ failure }}</ApCallout>
    </div>
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
      <ApButton
        variant="primary"
        :disabled="busy || target === picked?.data_source_id"
        :disabled-reason="busy ? 'Switching…' : 'Choose another source.'"
        @click="submit"
        >Switch</ApButton
      >
    </template>
  </ApSheet>
</template>
