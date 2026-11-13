<script setup lang="ts">
import { computed } from "vue";
import MoreMenu from "../viewer/MoreMenu.vue";
import type { DirectoryRow } from "./api.ts";

/** A row's secondary actions. Star is anyone's; duplicate and archive need dashboard.author. */
const props = defineProps<{ row: DirectoryRow; canEdit: boolean }>();
type Action = "star" | "unstar" | "duplicate" | "archive" | "restore";
const emit = defineEmits<{ action: [action: Action] }>();
const items = computed(() => {
  const list: { id: Action; label: string }[] = [
    props.row.starred ? { id: "unstar", label: "Unstar" } : { id: "star", label: "Star" },
  ];
  if (props.canEdit) {
    list.push({ id: "duplicate", label: "Duplicate…" });
    list.push(
      props.row.archived
        ? { id: "restore", label: "Restore" }
        : { id: "archive", label: "Archive…" },
    );
  }
  return list;
});
</script>

<template>
  <MoreMenu :items="items" :label="`Actions for ${row.name}`" @select="emit('action', $event)" />
</template>
