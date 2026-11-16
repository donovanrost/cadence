<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { computed, ref, shallowRef } from "vue";
import { ApSheet } from "@/ui";
import type { Group, GroupTarget } from "../groups/show.ts";
import HistoryBlock from "./HistoryBlock.vue";

/**
 * A target's History (ux U70): 'EARENDIL-007 · history', one block per command in stack order.
 * Openers call open(target); the sheet returns focus to the opener on close.
 */
const props = defineProps<{ group: Group; missionId: MissionId }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const target = shallowRef<GroupTarget | null>(null);
const name = computed(() => target.value?.name ?? "Unknown spacecraft");
const members = computed(() =>
  [...(target.value?.members ?? [])].sort((a, b) => a.position - b.position),
);
const commandName = (position: number, fallback: string) =>
  props.group.commands.find((c) => c.position === position)?.name ?? fallback;
function open(t: GroupTarget) {
  target.value = t;
  sheet.value?.open();
}
defineExpose({ open });
</script>

<template>
  <ApSheet ref="sheet" :title="`${name} · history`" width="wide">
    <div v-if="target" class="flex flex-col gap-3">
      <HistoryBlock
        v-for="m in members"
        :key="m.request_id"
        :mission-id="missionId"
        :request-id="m.request_id"
        :title="`${m.position + 1} · ${commandName(m.position, m.command_name ?? m.command_id)}`"
        :spacecraft="target.name"
      />
    </div>
  </ApSheet>
</template>
