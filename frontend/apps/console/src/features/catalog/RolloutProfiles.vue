<script setup lang="ts">
import { profileCard, type RolloutProfile } from "./rollout.ts";

/** C3 by profile: a checkbox per profile; older versions are a separate, explicit choice (ux). */
type Chosen = Readonly<{ id: string; allVersions: boolean }>;
defineProps<{
  profiles: readonly RolloutProfile[];
  /** The profile's current version, for "They move to v7…" (profiles list). */
  versions: ReadonlyMap<string, number>;
}>();
const chosen = defineModel<readonly Chosen[]>({ required: true });
const picked = (id: string) => chosen.value.find((c) => c.id === id) ?? null;
function toggle(id: string, on: boolean) {
  chosen.value = on
    ? [...chosen.value, { id, allVersions: false }]
    : chosen.value.filter((c) => c.id !== id);
}
function setAll(id: string, on: boolean) {
  chosen.value = chosen.value.map((c) => (c.id === id ? { id, allVersions: on } : c));
}
const checked = (e: Event) => e.target instanceof HTMLInputElement && e.target.checked;
</script>

<template>
  <div v-for="p in profiles" :key="p.id" class="flex flex-col gap-1.5">
    <label class="flex items-center gap-2 text-md text-readout">
      <input
        type="checkbox"
        class="size-4 accent-[var(--color-readout)]"
        :checked="picked(p.id) !== null"
        @change="toggle(p.id, checked($event))"
      />
      {{ profileCard(p) }}
    </label>
    <div v-if="picked(p.id) && p.on_older_versions > 0" class="ml-6 flex flex-col gap-1">
      <label class="flex items-start gap-2 text-sm text-text-2">
        <input
          type="checkbox"
          class="mt-0.5 size-4 accent-[var(--color-readout)]"
          :checked="picked(p.id)?.allVersions === true"
          @change="setAll(p.id, checked($event))"
        />
        Also move the {{ p.on_older_versions }} on older versions. They move to v{{
          versions.get(p.id) ?? "?"
        }}
        with every profile change since their version, not only the catalog.
      </label>
      <RouterLink
        class="ml-6 text-sm text-readout hover:underline"
        :to="{ name: 'setup.profile', params: { profileId: p.id, section: 'history' } }"
        >See its history</RouterLink
      >
    </div>
  </div>
</template>
