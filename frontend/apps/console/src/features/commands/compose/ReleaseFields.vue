<script setup lang="ts">
import { computed } from "vue";
import { ApOption, ApSegmented, ApTimePicker } from "@/ui";
import type { Release } from "./draft.ts";
import { PRIORITY_HINT, expiryProblem, priorityChoices } from "../priority.ts";

/**
 * C5's Release block: when each uplink may go (next AOS or held), an optional expiry and the
 * priority (ux U68). Normal and High are offered; a resend's low priority stays as 'Low (as before)'.
 */
const release = defineModel<Release>({ required: true });
const set = (patch: Partial<Release>) => (release.value = { ...release.value, ...patch });

const mode = computed({
  get: () => release.value.mode,
  set: (m: Release["mode"] | null) => {
    if (m) set({ mode: m });
  },
});
const notBefore = computed({
  get: () => release.value.notBefore,
  set: (t: number | null) => set({ notBefore: t }),
});
const expires = computed({
  get: () => release.value.expiresAt !== null,
  // Ticking it starts at an hour after the hold (or now); unticking clears it.
  set: (on: boolean) =>
    set({ expiresAt: on ? (release.value.notBefore ?? Date.now()) + 3_600_000 : null }),
});
const expiresAt = computed({
  get: () => release.value.expiresAt,
  set: (t: number | null) => set({ expiresAt: t }),
});
const expiryWarn = (at: number) =>
  expiryProblem(
    at,
    release.value.mode === "not_before" ? release.value.notBefore : null,
    Date.now(),
  );
const choices = computed(() => priorityChoices(release.value.priority));
const priority = computed({
  get: () => String(release.value.priority),
  set: (v: string) => set({ priority: Number(v) }),
});
</script>

<template>
  <fieldset class="m-0 flex flex-col gap-2 border-0 p-0">
    <legend class="ap-label pb-2">Release</legend>
    <ApOption
      v-model="mode"
      name="release"
      value="next_contact"
      title="At each target's next AOS"
      description="Recommended. Each uplink waits for its own target's contact."
    />
    <ApOption
      v-model="mode"
      name="release"
      value="not_before"
      title="Hold until a set time"
      description="Then the first AOS after it."
    />
    <ApTimePicker
      v-if="mode === 'not_before'"
      v-model="notBefore"
      label="Not before"
      future
      past-message="That time has passed; the release would go at the next AOS."
    />
    <!-- Raw checkbox: the kit has none; same pattern as scheduling/SubmitSheet's. -->
    <label class="flex items-center gap-2 pt-1 text-md text-text-2">
      <input
        v-model="expires"
        type="checkbox"
        class="accent-[var(--color-readout)] [color-scheme:dark]"
      />
      Expire if not released by
    </label>
    <template v-if="expires">
      <ApTimePicker v-model="expiresAt" label="Expires at" :warn="expiryWarn" />
      <p class="m-0 text-sm text-text-3">Uplinks not released by then end as Expired.</p>
    </template>
    <span class="ap-label pt-2">Priority</span>
    <ApSegmented v-model="priority" :options="choices" label="Priority" />
    <p class="m-0 text-sm text-text-3">{{ PRIORITY_HINT }}</p>
  </fieldset>
</template>
