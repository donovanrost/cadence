<script setup lang="ts">
import { useRoute } from "vue-router";
import RailLink from "./RailLink.vue";

/** `mission` is null on org pages reached without a mission in the URL. */
defineProps<{ org: string; mission: string | null }>();
const route = useRoute();

const missionItems = [
  { nav: "readiness", to: "setup.readiness", label: "Readiness" },
  { nav: "spacecraft", to: "setup.spacecraft", label: "Spacecraft" },
  { nav: "profiles", to: "setup.profiles", label: "Profiles" },
  { nav: "catalog", to: "setup.catalog", label: "Catalog" },
  { nav: "comms", to: "setup.comms", label: "Comms & routing" },
  { nav: "stations", to: "setup.stations", label: "Ground stations" },
  { nav: "data-sources", to: "setup.data-sources", label: "Data sources" },
  { nav: "apps", to: "setup.apps", label: "Apps" },
  { nav: "mission-settings", to: "setup.settings", label: "Mission settings" },
] as const;

const orgItems = [
  { nav: "people", to: "org.people", label: "People & access" },
  { nav: "missions", to: "org.missions", label: "Missions" },
  { nav: "provider-accounts", to: "org.provider-accounts", label: "Provider accounts" },
  { nav: "org-settings", to: "org.settings", label: "Settings" },
  { nav: "audit", to: "org.audit", label: "Audit log" },
] as const;
const groupClass =
  "max-[1100px]:sr-only font-display text-xs font-semibold tracking-[.22em] text-text-4 uppercase px-3.5 pt-3.5 pb-1.5 m-0";
</script>

<template>
  <nav
    aria-label="Setup"
    class="hidden w-14 flex-none flex-col md:flex min-[1100px]:w-[220px] overflow-auto border-r border-hairline bg-chrome pt-1.5 pb-3.5"
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
    <p :class="groupClass">Organization</p>
    <RailLink
      v-for="item in orgItems"
      :key="item.nav"
      :to="{ name: item.to, params: { org } }"
      index="··"
      :label="item.label"
      :active="route.meta.nav === item.nav"
    />
  </nav>
</template>
