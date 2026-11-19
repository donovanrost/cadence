<script setup lang="ts" generic="Id extends string">
import { ApMenuButton, ApMenuItem } from "@/ui";

/**
 * The dashboards' ⋯ (viewer, directory rows, library, playlists, section headings): the kit menu
 * button (design-language §6). A disabled item stays focusable and says why, so 'It's already
 * first.' is reachable by keyboard and read. A chosen item hands focus back to the ⋯ first, so a
 * sheet the action opens returns focus there when it closes.
 */
withDefaults(
  defineProps<{
    /** `disabled`: why the item can't run now, shown on it (ux: disabled reasons, not silence). */
    items: readonly { id: Id; label: string; disabled?: string | undefined }[];
    label?: string;
  }>(),
  { label: "More dashboard actions" },
);
const emit = defineEmits<{ select: [id: Id] }>();
</script>

<template>
  <ApMenuButton :label="label">
    <ApMenuItem
      v-for="item in items"
      :key="item.id"
      :disabled="item.disabled || undefined"
      @select="emit('select', item.id)"
      >{{ item.label }}</ApMenuItem
    >
  </ApMenuButton>
</template>
