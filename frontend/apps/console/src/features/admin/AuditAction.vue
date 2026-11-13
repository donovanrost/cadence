<script setup lang="ts">
import type { PlatformAuditEvent } from "./api.ts";

/** An audit row's What: the server's sentence and its target, or "Unreadable entry" (lead 11-13). */
defineProps<{ event: PlatformAuditEvent | null }>();
</script>

<template>
  <span v-if="!event" class="text-text-3">Unreadable entry</span>
  <template v-else
    >{{ event.action
    }}<span v-if="event.target?.label" class="text-text-3">
      · {{ event.target.label }}</span
    ></template
  >
</template>
