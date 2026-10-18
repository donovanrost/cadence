<script setup lang="ts">
import { computed } from "vue";
import CadenceBadge from "@cadence/ui/CadenceBadge.vue";
import CadenceIcon from "@cadence/ui/CadenceIcon.vue";
import CadenceTooltip from "@cadence/ui/CadenceTooltip.vue";
import type { WorkspacePlacement, WorkspaceSnapshot } from "../workspace/contracts";
import { hasData, latestSampleMs, limitLabel, limitTone, worstLimitState } from "./widget-data";
import WidgetMenu from "./WidgetMenu.vue";
import WidgetBody from "./WidgetBody.vue";

const props = defineProps<{
  placement: WorkspacePlacement;
  context: WorkspaceSnapshot["context"];
  editing: boolean;
  live: boolean;
  now: number;
  staleAfterMs: number;
  domId: string;
  group: string;
}>();
const emit = defineEmits<{ inspect: []; configure: []; remove: [] }>();

const title = computed(() => props.placement.widget?.title || props.placement.authored_id);
const limit = computed(() => worstLimitState(props.placement));
const stale = computed(() => {
  if (!props.live || !hasData(props.placement)) return false;
  const latest = latestSampleMs(props.placement);
  return latest !== null && props.now - latest > props.staleAfterMs;
});
const warnings = computed(() =>
  props.placement.warnings.map((w) => `${w.severity}: ${w.code.replaceAll("_", " ")}`).join("\n"),
);
</script>

<template>
  <article :id="domId" class="flex h-full min-h-0 flex-col" :data-placement-id="placement.id">
    <header
      class="cadence-dashboard-widget-header flex items-center gap-2 pl-2.5 pr-1"
      :class="editing ? 'cursor-move' : ''"
      :data-drag-handle="editing ? '' : undefined"
    >
      <CadenceIcon v-if="editing" name="hero-arrows-pointing-out" size="xs" />
      <h3 class="min-w-0 flex-1 truncate text-xs font-medium">{{ title }}</h3>
      <CadenceBadge v-if="limit && limit !== 'green'" :tone="limitTone[limit]">
        {{ limitLabel[limit] }}
      </CadenceBadge>
      <CadenceBadge v-if="stale" tone="warning">Stale</CadenceBadge>
      <CadenceTooltip v-if="warnings" :content="warnings">
        <span class="text-warning" tabindex="0">
          <CadenceIcon name="hero-exclamation-triangle" :label="`Warnings: ${warnings}`" />
        </span>
      </CadenceTooltip>
      <div class="cadence-dashboard-widget-actions">
        <WidgetMenu
          :id="`${domId}-menu`"
          :title="title"
          :editing="editing"
          :inspectable="hasData(placement)"
          @inspect="emit('inspect')"
          @configure="emit('configure')"
          @remove="emit('remove')"
        />
      </div>
    </header>
    <WidgetBody
      :placement="placement"
      :context="context"
      :live="live"
      :now="now"
      :group="group"
      :chart-id="`${domId}-chart`"
    />
  </article>
</template>
