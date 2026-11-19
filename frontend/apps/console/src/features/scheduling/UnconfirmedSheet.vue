<script setup lang="ts">
import { ref } from "vue";
import { ApButton, ApSheet } from "@/ui";
import type { UnconfirmedPass } from "./unconfirmed.ts";

/**
 * Every unconfirmed pass (ux U30 cap: the callout shows the soonest 5). The `row-actions` slot is
 * the callout's, passed through, so U32's actions sit on these rows too (fe-setup).
 */
defineProps<{ title: string; passes: readonly UnconfirmedPass[] }>();
defineSlots<{ "row-actions"?: (props: { pass: UnconfirmedPass }) => unknown }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const open = () => sheet.value?.open();
defineExpose({ open });
</script>

<template>
  <ApSheet ref="sheet" :title="title" width="wide">
    <ul class="m-0 flex list-none flex-col gap-2 p-0">
      <li
        v-for="pass in passes"
        :key="pass.snapshot_id"
        class="flex flex-wrap items-center gap-x-3 gap-y-1 border-t border-hairline pt-2"
      >
        <span class="font-mono text-sm text-text-2 tabular">{{ pass.text }}</span>
        <span class="font-mono text-xs text-text-3">{{ pass.provider?.name ?? "" }}</span>
        <slot name="row-actions" :pass="pass" />
      </li>
    </ul>
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">Close</ApButton>
    </template>
  </ApSheet>
</template>
