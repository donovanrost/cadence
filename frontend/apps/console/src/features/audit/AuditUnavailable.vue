<script setup lang="ts">
import { ApEmptyState, ApPanel } from "@/ui";

/** The audit log can't show here: a member (org admins only) or a server without the read. */
defineProps<{ member: boolean }>();
</script>

<template>
  <ApPanel index="L1" title="Audit log" flush>
    <ApEmptyState v-if="member" state="off" headline="Org admins see this." />
    <ApEmptyState
      v-else
      state="off"
      headline="The audit log isn't available in the console yet"
      sentence="Configuration revisions are in Setup › Revisions in the meantime."
    />
  </ApPanel>
</template>
