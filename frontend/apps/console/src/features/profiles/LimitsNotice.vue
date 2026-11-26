<script setup lang="ts">
import { ApCallout, ApPanel } from "@/ui";

/** Profile.md P1 Limits: read-only notice; limits live in the Limits app, per point, mission-wide. */
</script>

<template>
  <ApPanel index="P1" title="Limits">
    <ApCallout tone="info"
      >Limits apply mission-wide per point; per-profile limits aren't supported yet. They're set in
      the Limits app:
      <!-- P7 (#313): the Limits app by name, not the Apps list. -->
      <RouterLink
        :to="{ name: 'setup.app', params: { appKey: 'limits' } }"
        class="text-readout hover:underline"
        >Limits</RouterLink
      >.</ApCallout
    >
  </ApPanel>
</template>
