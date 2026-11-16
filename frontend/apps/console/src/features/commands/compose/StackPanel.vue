<script setup lang="ts">
import { ref } from "vue";
import { ApButton, ApEmptyState, ApPanel, ApTag } from "@/ui";
import type { FleetSpacecraft } from "@/features/fleet/index.ts";
import type { VerifierGroup } from "../groups/api.ts";
import { verifiersDiffer } from "../groups/verifierGroups.ts";
import CatalogSearch from "./CatalogSearch.vue";
import CommandForm from "./CommandForm.vue";
import { argSummary, checkItem, type StackItem } from "./stack.ts";

/**
 * C2 · Command stack: ordered commands from the catalog; one row open for editing. Reorder by
 * the ↑/↓ buttons, the ⠿ drag handle, or Alt+↑/↓ in a row (Command.md C2).
 */
const props = defineProps<{
  items: readonly StackItem[];
  revision: string | null;
  /** "Catalog rev 14" when the catalog revision is recorded (backlog §2). */
  catalogRev?: string | null;
  adding: boolean;
  /** U51: each stack position's verifier groups (preflight), and target names for them. */
  groupsAt?: ((position: number) => readonly VerifierGroup[]) | undefined;
  nameOf?: ((spacecraftId: string) => string) | undefined;
  /** U51: `rev 14 · 15` when the targets span catalog revisions. */
  span?: string | null | undefined;
  /** The request's targets, for B2 per-target values. */
  targets: readonly FleetSpacecraft[];
}>();
const emit = defineEmits<{
  add: [commandId: string];
  change: [key: string, values: Record<string, string>];
  perTarget: [key: string, perTarget: StackItem["perTarget"]];
  move: [index: number, by: -1 | 1];
  reorder: [from: number, to: number];
  remove: [key: string];
}>();
/** The row whose form is open (owned by Compose so a newly added command opens itself). */
const open = defineModel<string | null>("open", { required: true });
/** Command.md C2 reorder: drag the ⠿ handle, or Alt+↑/↓ anywhere in a row. */
const dragFrom = ref<number | null>(null);
const dragOver = ref<number | null>(null);
function drop(to: number) {
  const from = dragFrom.value;
  dragFrom.value = null;
  dragOver.value = null;
  if (from !== null && from !== to) emit("reorder", from, to);
}
function altMove(e: KeyboardEvent, i: number) {
  if (!e.altKey || (e.key !== "ArrowUp" && e.key !== "ArrowDown")) return;
  const by = e.key === "ArrowUp" ? -1 : 1;
  if (i + by < 0 || i + by >= props.items.length) return;
  e.preventDefault();
  emit("move", i, by);
}
</script>

<template>
  <ApPanel
    index="C2"
    title="Command stack"
    :meta="revision ? (span ? `Catalog ${span}` : (catalogRev ?? 'active catalog')) : undefined"
    flush
  >
    <ApEmptyState
      v-if="items.length === 0"
      headline="Empty"
      sentence="Pick a command from the catalog below."
    />
    <ol v-else class="m-0 list-none p-0">
      <li
        v-for="(item, i) in items"
        :key="item.key"
        class="border-t border-hairline first:border-t-0"
        :class="{ 'border-t-readout': dragOver === i && dragFrom !== i }"
        @keydown="altMove($event, i)"
        @dragover.prevent="dragOver = i"
        @drop.prevent="drop(i)"
      >
        <div class="flex flex-wrap items-center gap-3 px-4 py-2">
          <span
            v-if="items.length > 1"
            draggable="true"
            class="cursor-grab font-mono text-text-4 select-none max-md:hidden"
            aria-hidden="true"
            title="Drag to reorder (or Alt+↑/↓)"
            @dragstart="dragFrom = i"
            @dragend="dragFrom = dragOver = null"
            >⠿</span
          >
          <span class="font-mono text-xs text-text-4">{{ String(i + 1).padStart(2, "0") }}</span>
          <button
            type="button"
            class="max-md:hit-44 cursor-pointer font-mono font-semibold text-readout"
            :aria-expanded="open === item.key"
            :aria-label="`${item.command.name}: edit arguments`"
            @click="open = open === item.key ? null : item.key"
          >
            {{ item.command.name }}
          </button>
          <ApTag v-if="item.command.hazardous" state="crit" label="Hazardous" />
          <ApTag
            v-if="
              !checkItem(
                item,
                targets.map((t) => t.id),
              ).ok
            "
            state="caution"
            label="Needs values"
          />
          <!-- U51: the chip keeps it after the form closes. -->
          <ApTag
            v-if="groupsAt && verifiersDiffer(groupsAt(i))"
            state="caution"
            label="Verifiers differ"
          />
          <!-- ux Compose ruling #1: the value summary reopens the form. -->
          <button
            v-if="item.command.arguments.length"
            type="button"
            class="order-last min-w-0 basis-full cursor-pointer truncate text-left font-mono text-sm text-text-3 hover:text-readout hover:underline"
            :aria-label="`Edit ${item.command.name} values: ${argSummary(item).join(', ') || 'none set'}`"
            :aria-expanded="open === item.key"
            @click="open = item.key"
          >
            {{ argSummary(item).join(" · ") || "Set values" }}
          </button>
          <span aria-hidden="true" class="flex-1" />
          <span class="flex flex-none gap-1">
            <ApButton
              size="compact"
              variant="ghost"
              :disabled="i === 0"
              disabled-reason="Already first"
              :aria-label="`Move ${item.command.name} up`"
              @click="emit('move', i, -1)"
              >↑</ApButton
            >
            <ApButton
              size="compact"
              variant="ghost"
              :disabled="i === items.length - 1"
              disabled-reason="Already last"
              :aria-label="`Move ${item.command.name} down`"
              @click="emit('move', i, 1)"
              >↓</ApButton
            >
            <ApButton
              size="compact"
              variant="ghost"
              :aria-label="`Remove ${item.command.name}`"
              @click="emit('remove', item.key)"
              >✕</ApButton
            >
          </span>
        </div>
        <CommandForm
          v-if="open === item.key"
          :item="item"
          :targets="targets"
          :groups="groupsAt ? groupsAt(i) : []"
          :name-of="nameOf"
          @change="(v) => emit('change', item.key, v)"
          @per-target="(p) => emit('perTarget', item.key, p)"
          @done="open = null"
        />
      </li>
    </ol>
    <div class="border-t border-hairline p-4">
      <p v-if="adding" role="status" class="m-0 pb-2 font-mono text-xs text-text-4">ADDING…</p>
      <CatalogSearch @add="(id) => emit('add', id)" />
    </div>
  </ApPanel>
</template>
