<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed } from "vue";
import { RouterLink } from "vue-router";
import { useRemoteQuery } from "@/api/index.ts";
import { useMissionInvalidation } from "@/live/index.ts";
import { plural } from "@/ui";
import { fetchGroups } from "@/features/commands/index.ts";

/**
 * D2 Uplink (Contacts.md): the command requests bound to this pass (a group's U33 `uplink.pass`),
 * "Low power safe · 2 cmds" linking to the request, or "None queued". Requests still awaiting a GO
 * count: they'll go on this pass once approved.
 */
const props = defineProps<{ missionId: MissionId; passId: string }>();
const groups = useRemoteQuery(
  computed(() => props.missionId),
  (m, signal) => fetchGroups(m, { states: ["queued", "approval_pending"] }, signal),
);
useMissionInvalidation(
  computed(() => props.missionId),
  ["commanding", "contacts"],
  groups.refetch,
);
const bound = computed(() =>
  groups.state.value.status === "ready"
    ? groups.state.value.value.filter(
        (g) => g.finished !== true && g.uplink?.pass?.reservation_id === props.passId,
      )
    : null,
);
</script>

<template>
  <div class="flex flex-col gap-1">
    <p class="ap-label m-0">Uplink</p>
    <p v-if="bound === null" class="m-0 font-mono text-xs text-text-4 uppercase">Loading…</p>
    <p v-else-if="bound.length === 0" class="m-0 text-md text-text-3">None queued</p>
    <ul v-else class="m-0 flex list-none flex-col gap-1 p-0">
      <li v-for="g in bound" :key="g.id" class="text-md">
        <RouterLink
          :to="{ name: 'ops.commands.request', params: { requestId: g.id } }"
          class="max-md:hit-44 text-readout hover:underline"
          >{{ g.title }}</RouterLink
        >
        <span class="text-text-3">
          · {{ plural(g.command_count, "cmd")
          }}{{ g.state === "approval_pending" ? " · awaiting GO" : "" }}</span
        >
      </li>
    </ul>
  </div>
</template>
