<script setup lang="ts">
import { computed, ref } from "vue";
import { ApButton, ApSelect } from "@/ui";
import { selectionLabel, shortSelectionLabel, type TimeSelection } from "../model/time-range.ts";
import RangeSheet from "./RangeSheet.vue";
import ScopeSelect from "./ScopeSelect.vue";
import { refreshChoices, type RefreshChoice } from "./useDashboardView.ts";

/**
 * Header controls: spacecraft scope, range, refresh interval. `phone` is the header's second row
 * (ux Dashboards.md §Phone): the scope fills the row, the range button is short, and refresh lives
 * in ⋯ instead.
 */
const props = defineProps<{
  scopeOptions: readonly { id: string; name: string }[];
  spacecraft: string;
  selection: TimeSelection;
  refresh: RefreshChoice;
  phone?: boolean | undefined;
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
  <div class="flex items-center gap-2" :class="phone ? 'w-full' : 'flex-wrap'">
    <ScopeSelect
      v-model="spacecraft"
      :options="scopeOptions"
      :keys="!phone"
      :class="phone ? 'min-w-0 flex-1' : ''"
    />
    <!-- Alone (no scope) it sits right (ux). -->
    <ApButton
      variant="secondary"
      size="compact"
      :class="phone ? 'ml-auto flex-none' : ''"
      data-range
      :aria-label="phone && selection.kind === 'default' ? selectionLabel(selection) : undefined"
      @click="rangeSheet?.open()"
    >
      <span class="font-mono normal-case tracking-normal">{{
        phone ? shortSelectionLabel(selection) : selectionLabel(selection)
      }}</span>
    </ApButton>
    <ApSelect
      v-if="!phone"
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
