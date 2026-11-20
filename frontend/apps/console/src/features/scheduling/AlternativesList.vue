<script setup lang="ts">
import type { RemoteState } from "@/api";
import { ApButton, ApEmptyState, ApRemote, plural } from "@/ui";
import { distinctWindows, stationCode, type Alternative, type Alternatives } from "./api.ts";
import { gapEffect } from "./focus-day.ts";

/**
 * Other windows for the focused spacecraft (S4) with their effect from the server's evaluator.
 * Nothing visible → plain words and no disabled Add (ScheduleFlow: "uncoverable").
 */
defineProps<{ state: RemoteState<Alternatives>; editable: boolean; busy: boolean; name: string }>();
defineEmits<{ add: [snapshotId: string]; select: [snapshotId: string]; retry: [] }>();
const when = (a: Alternative) => `${a.starts_at.slice(11, 16)}–${a.ends_at.slice(11, 16)}Z`;
</script>

<template>
  <section :aria-label="`Other windows for ${name}`" class="mt-4 border-t border-hairline pt-3">
    <h3 class="ap-label mb-2">Other windows for {{ name }}</h3>
    <ApRemote :state="state" loading-label="Looking for windows…" @retry="$emit('retry')">
      <template #default="{ value }">
        <ApEmptyState
          v-if="distinctWindows(value.alternatives).length === 0"
          state="off"
          headline="Nothing else is visible"
          sentence="No other window from the network that day. Accept the gap when you submit."
        />
        <ul v-else class="m-0 flex list-none flex-col p-0">
          <li
            v-for="alt in distinctWindows(value.alternatives)"
            :key="alt.snapshot_id"
            class="flex items-center gap-3 border-t border-hairline-faint py-2 first:border-t-0"
          >
            <button
              type="button"
              class="max-md:hit-44 min-w-0 flex-1 cursor-pointer border-0 bg-transparent p-0 text-left"
              @click="$emit('select', alt.snapshot_id)"
            >
              <span class="block font-mono text-sm text-readout"
                >{{ when(alt) }} · {{ stationCode(alt.station) }}</span
              >
              <span
                v-if="gapEffect(value.longest_gap?.seconds, alt.effect.longest_gap_after_seconds)"
                class="block font-mono text-sm text-text-2"
                >{{
                  gapEffect(value.longest_gap?.seconds, alt.effect.longest_gap_after_seconds)
                }}</span
              >
              <span
                class="block text-sm"
                :class="
                  alt.effect.clashes_with.length > 0
                    ? 'text-caution-text'
                    : alt.effect.rule_met_after
                      ? 'text-nominal-text'
                      : 'text-text-3'
                "
              >
                {{
                  alt.effect.clashes_with.length > 0
                    ? `Clashes with ${plural(alt.effect.clashes_with.length, "drafted pass", "drafted passes")}`
                    : alt.effect.rule_met_after
                      ? "Meets the rule"
                      : `${alt.effect.contacts_after.have} / ${alt.effect.contacts_after.need ?? "?"} contacts after adding`
                }}
              </span>
            </button>
            <ApButton
              v-if="editable"
              size="compact"
              :disabled="busy"
              disabled-reason="Working…"
              :aria-label="`Add, ${name}, ${when(alt)}, ${stationCode(alt.station)}`"
              @click="$emit('add', alt.snapshot_id)"
              >Add</ApButton
            >
          </li>
        </ul>
      </template>
    </ApRemote>
  </section>
</template>
