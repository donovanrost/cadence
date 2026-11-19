<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import RailLink from "./RailLink.vue";

/** `mission` is null on org pages reached without a mission in the URL. */
const props = defineProps<{ org: string; mission: string | null; canAdminOrg: boolean }>();
const route = useRoute();

const missionItems = [
  { nav: "readiness", to: "setup.readiness", label: "Readiness" },
  { nav: "spacecraft", to: "setup.spacecraft", label: "Spacecraft" },
  { nav: "profiles", to: "setup.profiles", label: "Profiles" },
  { nav: "catalog", to: "setup.catalog", label: "Catalog" },
  { nav: "comms", to: "setup.comms", label: "Comms & routing" },
  { nav: "stations", to: "setup.stations", label: "Ground stations" },
  { nav: "contact-planning", to: "setup.contact-planning", label: "Contact planning" },
  { nav: "data-sources", to: "setup.data-sources", label: "Data sources" },
  { nav: "apps", to: "setup.apps", label: "Apps" },
  { nav: "mission-settings", to: "setup.settings", label: "Mission settings" },
] as const;

const orgItems = [
  { nav: "people", to: "org.people", label: "People & access", adminOnly: false },
  { nav: "missions", to: "org.missions", label: "Missions", adminOnly: false },
  {
    nav: "provider-accounts",
    to: "org.provider-accounts",
    label: "Provider accounts",
    adminOnly: true,
  },
  { nav: "org-settings", to: "org.settings", label: "Settings", adminOnly: true },
  { nav: "audit", to: "org.audit", label: "Audit log", adminOnly: true },
] as const;
const shownOrgItems = computed(() => orgItems.filter((i) => props.canAdminOrg || !i.adminOnly));
const groupClass =
  "max-console:sr-only font-display text-xs font-semibold tracking-[.22em] text-text-4 uppercase px-3.5 pt-3.5 pb-1.5 m-0";
</script>

<template>
  <nav
    aria-label="Setup"
    class="hidden w-14 flex-none flex-col md:flex console:w-[220px] overflow-auto border-r border-hairline bg-chrome pt-1.5 pb-3.5"
  >
    <template v-if="mission">
      <p :class="groupClass">Mission</p>
      <RailLink
        v-for="(item, i) in missionItems"
        :key="item.nav"
        :to="{ name: item.to, params: { org, mission } }"
        :index="String(i + 1).padStart(2, '0')"
        :label="item.label"
        :active="route.meta.nav === item.nav"
      />
    </template>
    <!-- Members see People and Missions; the admin-only items need organization_admin (decision 2;
         server enforces). A member who opens one by URL still has this rail (qa §6). -->
    <template v-if="shownOrgItems.length > 0">
      <p :class="groupClass">Organization</p>
      <RailLink
        v-for="item in shownOrgItems"
        :key="item.nav"
        :to="{ name: item.to, params: { org } }"
        index="··"
        :label="item.label"
        :active="route.meta.nav === item.nav"
      />
    </template>
  </nav>
</template>
