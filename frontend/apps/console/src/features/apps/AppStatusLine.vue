<script setup lang="ts">
import { computed } from "vue";
import { ApTag, formatShort } from "@/ui";
import { pendingLine, statusTag, type AppStatus } from "./host.ts";
import { saveMode } from "./saveOutcome.ts";

/**
 * The frame's status (ux AppSurfaces.md + #77): tag and version, `SAVES IMMEDIATELY` for apps whose
 * saves apply at once, and the open activation request for apps that wait for approval.
 */
const props = defineProps<{ appKey: string; status: AppStatus | null }>();
const mode = computed(() => saveMode(props.appKey));
const pending = computed(() =>
  props.status ? pendingLine(props.status, (iso) => formatShort(new Date(iso)).slice(6)) : null,
);
</script>

<template>
  <div v-if="status" class="flex flex-col items-end gap-1">
    <div class="flex items-center gap-2">
      <ApTag
        :state="statusTag[status.state].state"
        :label="`${statusTag[status.state].label}${status.version ? ` · v${status.version}` : ''}`"
      />
      <span v-if="mode === 'immediate'" class="font-mono text-xs text-text-3 uppercase"
        >Saves immediately</span
      >
    </div>
    <span v-if="pending" class="text-sm text-caution-text">{{ pending }}</span>
  </div>
</template>
