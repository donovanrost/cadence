<script setup lang="ts">
defineProps<{
  missionId: string;
  missionName: string;
  componentCount: number;
}>();
</script>

<template>
  <section id="ops-console-surface" class="card border border-base-300 bg-base-200">
    <div class="card-body p-8">
      <p class="font-mono text-xs font-semibold uppercase tracking-wide text-primary">
        Mission Operations
      </p>
      <h1 class="card-title mt-2 text-2xl tracking-tight text-base-content">{{ missionName }}</h1>
      <p class="mt-1 max-w-2xl text-sm leading-6 text-base-content/70">
        Phoenix selected this Ops Console surface for mission
        <code class="font-mono text-base-content">{{ missionId }}</code>.
      </p>
      <div class="mt-6 flex items-center gap-2 text-sm text-success" role="status">
        <span class="h-2 w-2 rounded-full bg-success" aria-hidden="true"></span>
        <span>Server authority connected · {{ componentCount }} domain components available</span>
      </div>
    </div>
  </section>
</template>
