<script setup lang="ts">
import { computed } from "vue";
import { ApButton, ApPanel } from "@/ui";
import type { WorkspacePlacement, WorkspaceSnapshot } from "../model/snapshot.ts";
import { widgetTitle } from "../model/widget-data.ts";
import WidgetBody from "../widgets/WidgetBody.vue";

/** One widget in an ApPanel (ux: no index letters; errors stay inside the panel). */
const props = defineProps<{
  placement: WorkspacePlacement;
  context: WorkspaceSnapshot["context"];
  now: number;
  group: string;
  /** Its place in its section, in reading order: names an untitled widget (B7). */
  position?: number | undefined;
}>();
const emit = defineEmits<{ inspect: [placement: WorkspacePlacement] }>();
const title = computed(() => widgetTitle(props.placement, props.position));
const warning = computed(() =>
  props.placement.warnings.some((w) => w.severity !== "info") ? "PARTIAL DATA" : undefined,
);
</script>

<template>
  <ApPanel :title="title" :meta="warning" :heading-level="3" flush pane class="h-full">
    <template #meta>
      <span class="flex items-center gap-2">
        <span v-if="warning" class="text-caution-text">{{ warning }}</span>
        <ApButton
          v-if="placement.status === 'ready'"
          variant="ghost"
          size="compact"
          :aria-label="`Inspect ${title}`"
          @click="emit('inspect', placement)"
          >Inspect</ApButton
        >
      </span>
    </template>
    <WidgetBody
      :placement="placement"
      :name="title"
      :context="context"
      :now="now"
      :group="group"
      :chart-id="`chart-${placement.id}`"
    />
  </ApPanel>
</template>
