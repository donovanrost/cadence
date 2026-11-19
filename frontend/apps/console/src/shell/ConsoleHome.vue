<script setup lang="ts">
import { onMounted } from "vue";
import { useRoute, useRouter } from "vue-router";
import { ApPageHeader, ApPanel } from "@/ui";
import { defaultMission } from "./last-mission.ts";
import { paramText } from "./route-params.ts";
import { useSession } from "./session.ts";

/** `/console` and `/console/:org`: go to the last (or first) mission's Now. */
const session = useSession();
const route = useRoute();
const router = useRouter();
const org = paramText(route.params, "org") || undefined;
const target = defaultMission(session, org);

onMounted(() => {
  if (target) void router.replace({ name: "ops.now", params: target }).catch(() => undefined);
});
</script>

<template>
  <div v-if="!target" class="flex flex-col gap-3">
    <ApPageHeader label="Cadence" title="No missions yet" />
    <ApPanel>
      <p class="m-0 text-base text-text-3">
        Your account can't open any mission yet. Ask an organization admin to add you to one.
      </p>
    </ApPanel>
  </div>
  <h1 v-else class="sr-only">Opening your mission</h1>
</template>
