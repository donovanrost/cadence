<script setup lang="ts">
import { computed } from "vue";
import { useRoute } from "vue-router";
import { paramText, useMissionScope } from "@/shell";
import { ApPageHeader, ApTabLinks, type ApTabLink } from "@/ui";
import RoutingRulesPanel from "./RoutingRulesPanel.vue";
import TransportEditor from "./TransportEditor.vue";
import TransportsPanel from "./TransportsPanel.vue";

/** Setup › Comms & routing (rail 05): Routing rules · Transports (ux U4). */
const route = useRoute();
const scope = useMissionScope();
const transportId = computed(() =>
  typeof paramText(route.params, "transportId") === "string" &&
  paramText(route.params, "transportId")
    ? paramText(route.params, "transportId")
    : null,
);
const active = computed(() => (route.name === "setup.comms.transports" ? "transports" : "routing"));
const links: readonly ApTabLink[] = [
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
    <TransportEditor
      v-if="active === 'transports' && transportId"
      :key="transportId"
      :mission-id="scope.mission.id"
      :transport-id="transportId"
    />
    <TransportsPanel v-if="active === 'transports'" />
    <RoutingRulesPanel v-else />
  </div>
</template>
