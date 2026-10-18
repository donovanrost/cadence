<script setup lang="ts">
import { useManagementHeader } from "@cadence/plugin-sdk/page-header";
import { href } from "@cadence/plugin-sdk/routes";
import ProviderAccountCards from "./ProviderAccountCards.vue";
import type { ProviderAccountDirectory } from "./list.contracts";
const props = defineProps<ProviderAccountDirectory>();
useManagementHeader("/provider-accounts", () => ({
  description:
    "Organization-owned ground network control planes. Grant access to missions without copying credentials.",
  facts: [`${props.count} registered`],
  primary: {
    id: "new-provider-account",
    label: "New account",
    icon: "hero-plus",
    href: href("/provider-accounts/new"),
  },
}));
</script>

<template>
  <div id="provider-accounts-page" class="space-y-6">
    <div
      v-if="count === 0"
      id="provider-accounts-empty-state"
      class="rounded border border-dashed border-base-300/60 bg-base-100/30 p-8 text-center"
    >
      <span class="hero-globe-alt mx-auto h-10 w-10 text-base-content/30 block"></span>
      <p class="hud-label mt-3">No provider accounts</p>
      <p class="mt-2 max-w-md mx-auto text-sm text-base-content/70">
        Register the simulator or a commercial ground network once, then grant it to the missions
        that need it.
      </p>
      <div class="mt-5">
        <a href="/provider-accounts/new" class="btn btn-primary btn-sm"
          ><span class="hero-plus -ml-0.5 mr-1 h-4 w-4"></span>Register provider account</a
        >
      </div>
    </div>
    <div id="provider-accounts" class="grid gap-4 xl:grid-cols-2">
      <div id="provider-accounts-empty" class="hidden only:block"></div>
      <div v-for="card in provider_accounts" :id="card.__dom_id" :key="card.__dom_id">
        <div :id="`${card.__dom_id}-component`"><ProviderAccountCards :card="card" /></div>
      </div>
    </div>
  </div>
</template>
