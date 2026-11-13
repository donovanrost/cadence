<script setup lang="ts">
import { computed, ref } from "vue";
import { ApButton, ApSelect } from "@/ui";
import { selectionLabel, type TimeSelection } from "../model/time-range.ts";
import RangeSheet from "./RangeSheet.vue";
import ScopeSelect from "./ScopeSelect.vue";
import { refreshChoices, type RefreshChoice } from "./useDashboardView.ts";

/** Header controls: spacecraft scope, range, refresh interval. Edit and ⋯ join in later slices. */
const props = defineProps<{
  scopeOptions: readonly { id: string; name: string }[];
  spacecraft: string;
  selection: TimeSelection;
  refresh: RefreshChoice;
}>();
const emit = defineEmits<{
  spacecraft: [id: string];
  range: [selection: TimeSelection];
  refresh: [choice: RefreshChoice];
}>();
const rangeSheet = ref<InstanceType<typeof RangeSheet> | null>(null);
const spacecraft = computed({
  get: () => props.spacecraft,
  set: (id: string) => emit("spacecraft", id),
});
const refreshModel = computed({
  get: () => props.refresh,
  set: (v: RefreshChoice) => emit("refresh", v),
});
const refreshOptions = refreshChoices.map((c) => ({ value: c.value, label: `Refresh ${c.label}` }));
</script>

<template>
  <div class="flex items-center gap-2">
    <ScopeSelect v-model="spacecraft" :options="scopeOptions" />
    <ApButton variant="secondary" size="compact" @click="rangeSheet?.open()">
      <span class="font-mono normal-case tracking-normal">{{ selectionLabel(selection) }}</span>
    </ApButton>
    <ApSelect
      v-model="refreshModel"
      label="Refresh interval"
      hidden-label
      size="compact"
      mono
      :options="refreshOptions"
    />
    <RangeSheet ref="rangeSheet" :selection="selection" @pick="emit('range', $event)" />
  </div>
</template>
