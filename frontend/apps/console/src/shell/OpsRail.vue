<script setup lang="ts">
import { useRoute } from "vue-router";
import RailLink from "./RailLink.vue";

defineProps<{ org: string; mission: string; canAdminOrg: boolean }>();
const route = useRoute();

const items = [
  { nav: "now", to: "ops.now", label: "Now" },
  { nav: "fleet", to: "ops.fleet", label: "Fleet" },
  { nav: "alarms", to: "ops.alarms", label: "Alarms" },
  { nav: "commands", to: "ops.commands", label: "Commands" },
  { nav: "contacts", to: "ops.contacts", label: "Contacts" },
  { nav: "telemetry", to: "ops.telemetry", label: "Telemetry" },
  { nav: "timeline", to: "ops.timeline", label: "Timeline" },
] as const;
</script>

<template>
  <nav
    aria-label="Ops"
    class="hidden w-14 flex-none md:flex console:w-[var(--apogee-rail-w)] flex-col gap-0.5 overflow-auto border-r border-hairline bg-chrome py-3.5"
  >
    <RailLink
      v-for="(item, i) in items"
      :key="item.nav"
      :to="{ name: item.to, params: { org, mission } }"
      :index="String(i + 1).padStart(2, '0')"
      :label="item.label"
      :active="route.meta.nav === item.nav"
    />
    <div class="my-3 h-px bg-hairline" />
    <RailLink
      :to="{ name: 'setup.readiness', params: { org, mission } }"
      index="··"
      label="Setup"
      :active="false"
    />
    <RailLink
      v-if="canAdminOrg"
      :to="{ name: 'org.people', params: { org } }"
      index="··"
      label="Organization"
      :active="false"
    />
  </nav>
</template>
