<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useSession } from "@/shell";
import { ApCallout, ApTabLinks } from "@/ui";

/**
 * L7 platform admin (ux screens/Admin.md), outside org and mission scope. Until lead's 'admin' shell
 * mode lands, the area's nav is in-page; outside admin mode nothing renders behind the notice.
 */
const route = useRoute();
const session = useSession();
const links = [
  { key: "admin.organizations", label: "Organizations", to: { name: "admin.organizations" } },
  {
    key: "admin.service-identities",
    label: "Service identities",
    to: { name: "admin.service-identities" },
  },
  { key: "admin.runtime", label: "Runtime", to: { name: "admin.runtime" } },
];
const active = computed(() =>
  String(route.name ?? "").startsWith("admin.organization")
    ? "admin.organizations"
    : String(route.name ?? ""),
);
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <p class="m-0 font-mono text-xs text-text-3 uppercase">Platform admin</p>
    <ApTabLinks :links="links" :active="active" label="Platform administration" />
    <ApCallout v-if="!session.admin_mode" tone="info">
      Platform administration needs admin mode. Turn it on from the account menu, then come back.
    </ApCallout>
    <RouterView v-else />
  </div>
</template>
