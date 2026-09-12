<script setup lang="ts">
import type { SetupPhase } from "./mission-form-port";
defineProps<{ phase: SetupPhase; href: string }>();
</script>
<template>
  <div
    v-if="phase !== 'editing'"
    id="comms-setup-outcome"
    role="status"
    class="mb-4 rounded border border-warning/40 bg-base-200 p-4"
  >
    <p v-if="phase === 'completed'">This form was saved. It cannot be submitted again.</p>
    <p v-else>The save outcome is unknown. This form is locked to prevent a repeated save.</p>
    <a id="comms-setup-review-records" :href="href" class="link">Review mission records</a>
  </div>
</template>
