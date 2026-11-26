<script setup lang="ts">
import { computed } from "vue";
import { ApButton, ApCallout, formatClock } from "@/ui";
import type { Playlist } from "./api.ts";

/** 409 version_conflict on a playlist save (§D24): who changed it, then theirs or mine. */
const props = defineProps<{ current: Playlist }>();
const emit = defineEmits<{ theirs: [current: Playlist]; mine: [current: Playlist] }>();
const line = computed(() => {
  const who = props.current.updated_by?.name ?? "Someone";
  const at = props.current.updated_at
    ? ` at ${formatClock(new Date(props.current.updated_at)).slice(0, 5)}Z`
    : "";
  return `${who} changed this playlist${at} while you were editing.`;
});
</script>

<template>
  <ApCallout tone="caution" role="alert">
    {{ line }}
    <template #action>
      <span class="flex gap-2">
        <ApButton size="compact" variant="secondary" @click="emit('theirs', current)"
          >Use theirs</ApButton
        >
        <ApButton size="compact" variant="primary" @click="emit('mine', current)"
          >Keep mine</ApButton
        >
      </span>
    </template>
  </ApCallout>
</template>
