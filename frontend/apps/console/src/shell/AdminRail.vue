<script setup lang="ts">
import { useRoute } from "vue-router";
import RailLink from "./RailLink.vue";

/** L7 platform admin rail (ux Admin.md): Organizations · Service identities · Runtime · Audit. */
const route = useRoute();
const items = [
  {
    names: ["admin.organizations", "admin.organization"],
    to: "admin.organizations",
    label: "Organizations",
  },
  {
    names: ["admin.service-identities"],
    to: "admin.service-identities",
    label: "Service identities",
  },
  { names: ["admin.runtime"], to: "admin.runtime", label: "Runtime" },
  { names: ["admin.audit"], to: "admin.audit", label: "Audit" },
] as const;
const active = (names: readonly string[]) =>
  typeof route.name === "string" && names.includes(route.name);
</script>

<template>
  <nav
    aria-label="Platform admin"
    class="hidden w-14 flex-none flex-col overflow-auto border-r border-hairline bg-chrome pt-1.5 pb-3.5 md:flex console:w-[220px]"
  >
    <RailLink
      v-for="(item, i) in items"
      :key="item.to"
      :to="{ name: item.to }"
      :index="String(i + 1).padStart(2, '0')"
      :label="item.label"
      :active="active(item.names)"
    />
  </nav>
</template>
