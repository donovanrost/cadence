<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref, watch } from "vue";
import { ApButton, ApEmptyState, ApPanel, ApTable, ApTag, refocusFirst, type ApColumn } from "@/ui";
import type { DataSource } from "./api.ts";
import BindingHistorySheet from "./BindingHistorySheet.vue";
import BindingSwitchSheet from "./BindingSwitchSheet.vue";
import PlatformSwitchSheet from "./PlatformSwitchSheet.vue";
import { ADMIN_ONLY } from "./platform.ts";
import { usePlatformSwitch } from "./usePlatformSwitch.ts";
import type { SourceBinding } from "./writes.ts";

/**
 * S2 · which logical sources read from this source. W3 switches a mission's own binding; a
 * platform-wide one (U53, #90) only a platform admin in admin mode, through the danger sheet.
 */
const props = defineProps<{
  missionId: MissionId;
  bindings: readonly SourceBinding[];
  sources: readonly DataSource[];
  editable: boolean;
}>();
const emit = defineEmits<{ done: [note: { tone: "nominal" | "crit"; text: string }] }>();
const platformAdmin = usePlatformSwitch();
const canSwitch = (b: SourceBinding) => (b.shared === true ? platformAdmin.value : props.editable);
const anyAction = computed(() => props.bindings.some(canSwitch));
const columns = computed<readonly ApColumn[]>(() => [
  { key: "logical", label: "Logical source", mono: true },
  { key: "reads", label: "Reads from" },
  { key: "status", label: "Status" },
  ...(anyAction.value ? [{ key: "switch", label: "Switch", hiddenLabel: true }] : []),
  { key: "history", label: "History", hiddenLabel: true },
]);
const BINDING_WORDS: Readonly<Record<SourceBinding["status"], string>> = {
  active: "Active",
  disabled: "Disabled",
  superseded: "Superseded",
  unrecognized: "Unknown",
};
const nameOf = (id: string) => props.sources.find((s) => s.id === id)?.display_name ?? id;
const lockedPlatform = computed(() =>
  props.bindings.some((b) => b.shared === true && !canSwitch(b)),
);
const own = ref<InstanceType<typeof BindingSwitchSheet> | null>(null);
const platform = ref<InstanceType<typeof PlatformSwitchSheet> | null>(null);
const history = ref<InstanceType<typeof BindingHistorySheet> | null>(null);
function openSwitch(b: SourceBinding) {
  if (b.shared === true) platform.value?.open(b);
  else own.value?.open(b);
}
// a11y A5: switching a binding away removes its row and the Switch… the sheet returned focus to;
// once the bindings re-read, land on a remaining Switch…, else the panel's heading.
let settle = false;
watch(
  () => props.bindings,
  () => {
    if (!settle) return;
    settle = false;
    const panel = document.querySelector<HTMLElement>("[data-source-bindings]");
    refocusFirst(
      panel?.querySelector<HTMLElement>("[data-binding-switch]"),
      panel?.querySelector<HTMLElement>("h2"),
    );
  },
  { flush: "post" },
);
const relay = (n: { tone: "nominal" | "crit"; text: string }) => {
  if (n.tone === "nominal") settle = true;
  emit("done", n);
};
</script>

<template>
  <ApPanel index="S2" title="Bindings" flush data-source-bindings>
    <ApEmptyState
      v-if="bindings.length === 0"
      state="off"
      headline="Nothing reads from it"
      sentence="No logical source is bound to this source."
    />
    <ApTable v-else :columns="columns" :rows="bindings" :row-key="(b) => b.id" caption="Bindings">
      <template #cell-logical="{ row }"
        ><span class="inline-flex items-center gap-2"
          >{{ row.logical_source
          }}<ApTag v-if="row.shared === true" state="neutral" label="PLATFORM" /></span
      ></template>
      <template #cell-reads="{ row }">{{ nameOf(row.data_source_id) }}</template>
      <template #cell-status="{ row }"
        ><span class="text-text-2">{{ BINDING_WORDS[row.status] }}</span></template
      >
      <template #cell-switch="{ row }"
        ><ApButton
          v-if="canSwitch(row)"
          data-binding-switch
          size="compact"
          variant="ghost"
          @click="openSwitch(row)"
          >Switch…</ApButton
        ></template
      >
      <template #cell-history="{ row }"
        ><ApButton size="compact" variant="ghost" @click="history?.open(row)"
          >History</ApButton
        ></template
      >
    </ApTable>
    <p v-if="lockedPlatform" class="m-0 px-4 py-2 text-sm text-text-3">{{ ADMIN_ONLY }}</p>
  </ApPanel>
  <BindingSwitchSheet ref="own" :mission-id="missionId" :sources="sources" @done="relay" />
  <PlatformSwitchSheet ref="platform" :mission-id="missionId" :sources="sources" @done="relay" />
  <BindingHistorySheet ref="history" :mission-id="missionId" />
</template>
