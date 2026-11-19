<script setup lang="ts">
import type { PlatformAuditEvent } from "./api.ts";

/** An audit row's organization: a link to it, "Platform" for none, blank when unreadable. */
defineProps<{ event: PlatformAuditEvent | null }>();
</script>

<template>
  <template v-if="event">
    <RouterLink
      v-if="event.organization"
      :to="{ name: 'admin.organization', params: { orgId: event.organization.id } }"
      class="text-readout hover:underline"
      >{{ event.organization.name }}</RouterLink
    >
    <span v-else class="text-text-3">Platform</span>
  </template>
</template>
