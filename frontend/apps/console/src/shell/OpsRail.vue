<script setup lang="ts">
import { useRoute } from "vue-router";
import { formatCount } from "@/ui";
import type { OpsCounts } from "./counts.ts";
import RailLink from "./RailLink.vue";

const props = defineProps<{
  org: string;
  mission: string;
  canAdminOrg: boolean;
  counts: OpsCounts | null;
}>();
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

/** Rail counts (IA §2): omitted, never zero-filled, when the server can't compute them. */
function count(
  nav: (typeof items)[number]["nav"],
): { text: string; tone?: "crit" | "live" } | null {
  const c = props.counts;
  if (!c) return null;
  switch (nav) {
    case "fleet":
      return c.fleet ? { text: formatCount(c.fleet.total) } : null;
    case "alarms":
      // ux #18 / U13: 0 is only shown when something can raise alarms (ground limits configured).
      if (!c.alarms || (c.alarms.active === 0 && !c.alarms.limits_configured)) return null;
      return {
        text: formatCount(c.alarms.active),
        ...(c.alarms.critical > 0 ? { tone: "crit" as const } : {}),
      };
    case "commands":
      return c.commands ? { text: formatCount(c.commands.open) } : null;
    case "contacts":
      return c.contacts
        ? { text: `${formatCount(c.contacts.in_contact)} AOS`, tone: "live" }
        : null;
    case "now":
    case "telemetry":
    case "timeline":
      return null;
  }
}
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
      :count="count(item.nav)?.text"
      :count-tone="count(item.nav)?.tone"
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
