<script setup lang="ts">
import { ApTag, formatShort } from "@/ui";
import type { VersionRow } from "../editor/contracts.ts";

/** Version history rows, newest first. Pick two to compare; Restore copies one forward. */
defineProps<{ rows: readonly VersionRow[]; selected: readonly number[]; canRestore: boolean }>();
const emit = defineEmits<{ toggle: [version: number]; restore: [version: number] }>();
const KIND: Readonly<Record<VersionRow["kind"], string>> = {
  unrecognized: "Changed",
  create: "Created",
  save: "Saved",
  revert: "Restored",
  migration: "Migrated",
};
const who = (r: VersionRow) =>
  r.saved_by?.name ?? (r.saved_by?.kind === "system" ? "Cadence" : "Someone");
</script>

<template>
  <ul class="m-0 flex list-none flex-col p-0">
    <li
      v-for="r in rows"
      :key="r.version"
      class="flex items-start gap-3 border-b border-hairline-faint py-2"
    >
      <input
        type="checkbox"
        class="mt-1 size-4 accent-[var(--color-readout)] [color-scheme:dark]"
        :checked="selected.includes(r.version)"
        :aria-label="`Compare v${r.version}`"
        @change="emit('toggle', r.version)"
      />
      <div class="min-w-0 flex-1">
        <p class="m-0 flex flex-wrap items-center gap-2 text-md text-readout">
          <span class="font-mono">v{{ r.version }}</span>
          <ApTag v-if="r.current" state="live" label="Current" />
          <span class="text-text-3">
            {{ KIND[r.kind]
            }}<template v-if="r.kind === 'revert' && r.based_on_version">
              from v{{ r.based_on_version }}</template
            >
            by {{ who(r) }} · {{ formatShort(new Date(r.saved_at)) }}
          </span>
        </p>
        <p v-if="r.message" class="m-0 text-sm text-text-3">{{ r.message }}</p>
      </div>
      <button
        v-if="canRestore && !r.current"
        type="button"
        class="cursor-pointer border-0 bg-transparent p-1 font-display text-xs uppercase tracking-btn text-text-3 hover:text-readout max-md:hit-44"
        :aria-label="`Restore v${r.version}`"
        @click="emit('restore', r.version)"
      >
        Restore
      </button>
    </li>
  </ul>
</template>
