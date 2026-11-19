<script setup lang="ts">
import type { DirectoryRow } from "./api.ts";
import NameCell from "./NameCell.vue";
import RowActions from "./RowActions.vue";
import { spacecraftText, updatedText } from "./row-words.ts";

/**
 * The directory on a phone (qa §6 a11y: the table scrolled the page sideways at 390): ux Mobile
 * rows, ≥ 56px, the name link over one subtitle line. Phone is view-only, so the ⋯ only stars.
 */
defineProps<{ rows: readonly DirectoryRow[] }>();
const emit = defineEmits<{ action: [action: "star" | "unstar", row: DirectoryRow] }>();
const onAction = (action: string, row: DirectoryRow) => {
  if (action === "star" || action === "unstar") emit("action", action, row);
};
</script>

<template>
  <ul class="m-0 flex list-none flex-col p-0" aria-label="Dashboards">
    <li
      v-for="row in rows"
      :key="row.id"
      class="flex min-h-14 items-center gap-3 border-b border-hairline-faint py-2"
    >
      <div class="flex min-w-0 flex-1 flex-col gap-0.5">
        <NameCell :row="row" />
        <p v-if="spacecraftText(row) || updatedText(row)" class="m-0 truncate text-sm text-text-3">
          <template v-if="spacecraftText(row)">{{ spacecraftText(row) }}</template
          ><template v-if="spacecraftText(row) && updatedText(row)"> · </template
          ><span v-if="updatedText(row)" class="font-mono">{{ updatedText(row) }}</span>
        </p>
      </div>
      <RowActions :row="row" :can-edit="false" @action="(a) => onAction(a, row)" />
    </li>
  </ul>
</template>
