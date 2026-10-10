<script setup lang="ts">
import { useManagementHeader } from "@cadence/plugin-sdk/page-header";
import { href } from "@cadence/plugin-sdk/routes";
import type { Page } from "./spacecraft-routing.contracts";

const props = defineProps<{ page: Page; missionId: string; spacecraftId: string }>();
useManagementHeader("/missions/:mission_id/spacecraft/:spacecraft_id/routing", () => ({
  title: props.page.title,
  description: props.page.subtitle,
  primary: {
    id: props.page.new_rule.id,
    label: props.page.new_rule.label,
    icon: "hero-plus",
    href: href(
      "/missions/:mission_id/comms/routing/new",
      { mission_id: props.missionId },
      { spacecraft_id: props.spacecraftId },
    ),
  },
}));
</script>

<template>
  <div class="space-y-6">
    <div
      v-if="page.rows.length === 0"
      class="rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center"
    >
      <p class="hud-label">{{ page.empty_state.title }}</p>
      <p class="mt-2 max-w-md mx-auto text-sm text-base-content/70">
        {{ page.empty_state.description }}
      </p>
    </div>

    <div v-else :id="page.rules_id" class="grid gap-3 md:grid-cols-2">
      <a
        v-for="row in page.rows"
        :id="row.id"
        :key="row.id"
        :href="row.href"
        data-phx-link="redirect"
        data-phx-link-state="push"
        class="card bg-base-200 border border-base-300 hud-corners hover:border-primary/50 hover-glow-cyan transition-glow"
      >
        <div class="card-body p-5">
          <p class="hud-label">{{ row.purpose_label }}</p>
          <h2 class="mt-2 font-semibold">{{ row.display_name }}</h2>
          <p class="mt-2 text-sm text-base-content/60">
            {{ row.direction }} via {{ row.transport_name
            }}<span v-if="row.transport_version" class="font-mono text-xs">
              · v{{ row.transport_version }}</span
            >
          </p>
          <p class="mt-2 font-mono text-xs text-base-content/60">
            {{ row.role }} · {{ row.state }}
          </p>
        </div>
      </a>
    </div>
  </div>
</template>
