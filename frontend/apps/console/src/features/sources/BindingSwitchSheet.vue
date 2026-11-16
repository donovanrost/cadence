<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref } from "vue";
import { ApButton, ApCallout, ApSelect, ApSheet } from "@/ui";
import type { DataSource } from "./api.ts";
import { sourceFailure } from "./present.ts";
import { switchBinding } from "./writes.ts";

/** W3 for a mission's own binding: pick another source serving the same logical source. */
export type SwitchTarget = Readonly<{ id: string; logical_source: string; data_source_id: string }>;
const props = defineProps<{ missionId: MissionId; sources: readonly DataSource[] }>();
const emit = defineEmits<{ done: [note: { tone: "nominal" | "crit"; text: string }] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const picked = ref<SwitchTarget | null>(null);
const target = ref("");
const failure = ref<string | null>(null);
const busy = ref(false);
const nameOf = (id: string) => props.sources.find((s) => s.id === id)?.display_name ?? id;
const choices = computed(() =>
  props.sources
    // The server takes only an active source serving the same logical source (422
    // incompatible_data_source), so only those are offered (and the current one).
    .filter(
      (s) =>
        s.id === picked.value?.data_source_id ||
        (s.state !== "disabled" && s.logical_source?.key === picked.value?.logical_source),
    )
    .map((s) => ({ value: s.id, label: s.display_name })),
);
function open(b: SwitchTarget) {
  picked.value = b;
  target.value = b.data_source_id;
  failure.value = null;
  sheet.value?.open();
}
defineExpose({ open });
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
  <ApSheet
    ref="sheet"
    :title="`Switch ${picked?.logical_source ?? ''}`"
    width="narrow"
    initial-focus="select"
  >
    <div class="flex flex-col gap-3">
      <ApSelect v-model="target" label="Read from" :options="choices" required />
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
