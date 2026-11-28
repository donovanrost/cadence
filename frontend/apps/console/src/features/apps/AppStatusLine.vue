<script setup lang="ts">
import { computed } from "vue";
import { ApTag, formatShort } from "@/ui";
import { pendingLine, statusTag, type AppStatus } from "./host.ts";

/** The frame's status (ux AppSurfaces.md + #77): tag and version, and the open activation request. */
const props = defineProps<{ status: AppStatus | null }>();
const pending = computed(() =>
  props.status ? pendingLine(props.status, (iso) => formatShort(new Date(iso)).slice(6)) : null,
);
</script>

<template>
  <div v-if="status" class="flex flex-col items-end gap-1">
    <ApTag
      :state="statusTag[status.state].state"
      :label="`${statusTag[status.state].label}${status.version ? ` · v${status.version}` : ''}`"
    />
    <!-- a11y B6: always mounted, so "Waiting for activation approval…" is announced when it
      appears. -->
    <span role="status" class="text-sm text-caution-text empty:hidden">{{ pending ?? "" }}</span>
  </div>
</template>
