<script setup lang="ts">
import { ApButton, ApEmptyState, ApPanel } from "@/ui";
import type { ProfileDetail } from "./detail.ts";

/** P2 Routing and P3 Overrides, honest while routing is still per spacecraft (DECISIONS #3). */
defineProps<{ detail: ProfileDetail; part: "routing" | "overrides" }>();
</script>

<template>
  <ApPanel v-if="part === 'routing'" index="P2" title="Routing rule" flush>
    <ApEmptyState
      v-if="detail.routing_model === 'per_spacecraft'"
      state="off"
      headline="Routing is still set per spacecraft"
      sentence="Profile routing rules (one rule generating routes for every spacecraft) arrive with the profile routing work. Until then each spacecraft carries its own rules."
    >
      <ApButton size="compact" :to="{ name: 'setup.comms' }">Open comms &amp; routing</ApButton>
    </ApEmptyState>
  </ApPanel>
  <ApPanel
    v-else
    index="P3"
    title="Overrides"
    :meta="`${detail.override_count} of ${detail.inherit_count} differ`"
    flush
  >
    <ApEmptyState
      v-if="detail.routing_model === 'per_spacecraft'"
      headline="Overrides aren't tracked yet"
      sentence="Spacecraft-level differences from the profile are recorded once profile routing lands."
    />
    <ApEmptyState
      v-else-if="detail.override_count === 0"
      state="off"
      :headline="`All ${detail.inherit_count} spacecraft match the profile`"
    />
  </ApPanel>
</template>
