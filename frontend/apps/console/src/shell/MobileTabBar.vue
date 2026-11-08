<script setup lang="ts">
import { useRoute } from "vue-router";

/** Below 768px: Ops on-call tabs at the bottom (J6). Setup is desktop-only. */
defineProps<{ org: string; mission: string }>();
const route = useRoute();
const items = [
  { nav: "now", to: "ops.now", label: "Now" },
  { nav: "alarms", to: "ops.alarms", label: "Alarms" },
  { nav: "fleet", to: "ops.fleet", label: "Fleet" },
  { nav: "contacts", to: "ops.contacts", label: "Contacts" },
  { nav: "commands", to: "ops.commands", label: "Commands" },
] as const;
</script>

<template>
  <nav aria-label="Ops" class="flex h-14 flex-none border-t border-hairline bg-chrome md:hidden">
    <RouterLink
      v-for="item in items"
      :key="item.nav"
      :to="{ name: item.to, params: { org, mission } }"
      :aria-current="route.meta.nav === item.nav ? 'page' : undefined"
      class="flex flex-1 items-center justify-center font-display text-sm font-semibold tracking-btn uppercase no-underline"
      :class="
        route.meta.nav === item.nav
          ? 'bg-raised text-readout shadow-[inset_0_2px_0_var(--color-readout)]'
          : 'text-text-3 hover:text-readout'
      "
      >{{ item.label }}</RouterLink
    >
  </nav>
</template>
