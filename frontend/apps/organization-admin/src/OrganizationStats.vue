<script setup lang="ts">
import CadenceCard from "./ui/components/CadenceCard.vue"

defineProps<{
  mission_count: number
  spacecraft_count: number
  member_count: number
}>()
</script>

<template>
  <div id="organization-stats" class="grid gap-4 md:grid-cols-3">
    <CadenceCard
      id="organization-stat-missions"
      class="card bg-base-200 border border-base-300 hud-corners hover-glow-cyan transition-glow hover:bg-[linear-gradient(var(--state-hover),var(--state-hover))]"
      body-class="card-body p-6"
    >
        <p class="hud-label">Missions</p>
        <p class="mt-2 font-mono text-3xl font-bold">{{ mission_count }}</p>
    </CadenceCard>

    <CadenceCard
      id="organization-stat-spacecraft"
      class="card bg-base-200 border border-base-300 hud-corners hover-glow-cyan transition-glow hover:bg-[linear-gradient(var(--state-hover),var(--state-hover))]"
      body-class="card-body p-6"
    >
        <p class="hud-label">Spacecraft</p>
        <p class="mt-2 font-mono text-3xl font-bold">{{ spacecraft_count }}</p>
    </CadenceCard>

    <CadenceCard
      id="organization-stat-members"
      class="card bg-base-200 border border-base-300 hud-corners hover-glow-cyan transition-glow hover:bg-[linear-gradient(var(--state-hover),var(--state-hover))]"
      body-class="card-body p-6"
    >
        <p class="hud-label">Members</p>
        <p class="mt-2 font-mono text-3xl font-bold">{{ member_count }}</p>
    </CadenceCard>
  </div>
</template>
