<script setup lang="ts">
import StatusBadge from "./StatusBadge.vue";

type ProviderAccountCard = {
  id: string;
  display_name: string;
  provider_account_id: string;
  status: "info" | "ready" | "attention" | "blocked";
  status_label: string;
  provider: string;
  config: string;
  credential: string;
  events: string;
  endpoint: string;
  href: string;
};

const props = defineProps<{ card: ProviderAccountCard }>();

const metrics = [
  ["Provider", "provider"],
  ["Config", "config"],
  ["Credential", "credential"],
  ["Events", "events"],
] as const;
</script>

<template>
  <a
    :href="props.card.href"
    data-phx-link="redirect"
    data-phx-link-state="push"
    class="group block border border-base-300 bg-base-200 transition-colors hover:border-primary/50"
  >
    <div class="flex items-start justify-between gap-4 border-b border-base-300 px-5 py-4">
      <div class="min-w-0">
        <p class="hud-label">Ground Network Control Plane</p>
        <h2 class="mt-1 truncate text-lg font-semibold group-hover:text-primary">
          {{ props.card.display_name }}
        </h2>
        <p class="mt-1 truncate font-mono text-xs text-base-content/50">
          {{ props.card.provider_account_id }}
        </p>
      </div>
      <StatusBadge :status="props.card.status" :label="props.card.status_label" />
    </div>

    <div class="grid grid-cols-2 gap-px bg-base-300 sm:grid-cols-4">
      <div v-for="[label, key] in metrics" :key="key" class="bg-base-200 px-4 py-3">
        <p class="hud-label">{{ label }}</p>
        <p class="mt-1 truncate font-mono text-sm">{{ props.card[key] }}</p>
      </div>
    </div>

    <div class="flex items-center justify-between gap-4 px-5 py-3 text-xs text-base-content/60">
      <span class="font-mono">{{ props.card.endpoint }}</span>
      <span class="inline-flex items-center gap-1 text-primary">
        Inspect <span aria-hidden="true">→</span>
      </span>
    </div>
  </a>
</template>
