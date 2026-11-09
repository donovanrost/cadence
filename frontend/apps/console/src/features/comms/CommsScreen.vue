<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useMissionScope } from "@/shell";
import { ApPageHeader, ApTabLinks } from "@/ui";
import RoutingRulesPanel from "./RoutingRulesPanel.vue";
import TransportsPanel from "./TransportsPanel.vue";

/** Setup › Comms & routing (rail 05): Routing rules · Transports (ux U4). */
const route = useRoute();
const scope = useMissionScope();
const active = computed(() => (route.name === "setup.comms.transports" ? "transports" : "routing"));
const links = [
  { key: "routing", label: "Routing rules", to: { name: "setup.comms" } },
  { key: "transports", label: "Transports", to: { name: "setup.comms.transports" } },
];
</script>

<template>
  <div class="mx-auto flex w-full max-w-[1400px] flex-col gap-4">
    <ApPageHeader
      :label="`${scope.mission.name} · comms & routing`"
      title="Comms & routing"
      size="reading"
    />
    <ApTabLinks :links="links" :active="active" label="Comms sections" />
    <TransportsPanel v-if="active === 'transports'" />
    <RoutingRulesPanel v-else />
  </div>
</template>
