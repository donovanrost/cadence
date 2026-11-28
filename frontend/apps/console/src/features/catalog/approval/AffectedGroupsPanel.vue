<script setup lang="ts">
import { computed } from "vue";
import { ApPanel } from "@/ui";
import type { ModelRevision } from "./api.ts";
import {
  AFFECTED_INTRO,
  AFFECTED_NONE,
  affectedMeta,
  craftLine,
  goLine,
} from "./affected-words.ts";

/**
 * E2c (#546, #1054): a withdrawn revision's GO'd requests still waiting to go out on craft that
 * run it (the withdraw answer and the withdrawn read both carry them), each linked to its request,
 * where Abort is. Past 50, the request list opens filtered to them (the server resolves the craft).
 */
const props = defineProps<{ revision: ModelRevision }>();
const groups = computed(() => props.revision.affected_groups ?? []);
const total = computed(() => props.revision.affected_groups_count ?? groups.value.length);
</script>

<template>
  <ApPanel
    v-if="revision.affected_groups !== null"
    index="W1"
    title="Requests still waiting to go out"
    :meta="affectedMeta(groups.length, total)"
    flush
  >
    <p v-if="groups.length === 0" class="m-0 px-4 py-3 text-md text-text-3">{{ AFFECTED_NONE }}</p>
    <template v-else>
      <p class="m-0 px-4 pt-3 text-md text-text-2">{{ AFFECTED_INTRO }}</p>
      <ul class="m-0 list-none p-0">
        <li
          v-for="g in groups"
          :key="g.group_id"
          class="flex flex-col gap-0.5 border-t border-hairline px-4 py-2.5 first:border-t-0"
        >
          <span class="flex flex-wrap items-baseline gap-2">
            <RouterLink
              :to="{ name: 'ops.commands.request', params: { requestId: g.group_id } }"
              class="font-semibold text-readout no-underline hover:underline max-md:hit-44"
              >{{ g.name }}</RouterLink
            >
            <span class="font-mono text-xs text-text-3">{{ goLine(g) }}</span>
          </span>
          <span class="text-sm text-text-2">{{ craftLine(g) }}</span>
        </li>
      </ul>
      <p v-if="groups.length < total" class="m-0 border-t border-hairline px-4 py-2.5 text-sm">
        <RouterLink
          :to="{
            name: 'ops.commands',
            query: { withdrawn_revision: revision.id, stage: 'queued_for_contact' },
          }"
          class="text-readout underline"
          >See all {{ total }} in Commands</RouterLink
        >
      </p>
    </template>
  </ApPanel>
</template>
