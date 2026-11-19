<script setup lang="ts">
import { computed } from "vue";
import { ApEmptyState, ApOption, plural } from "@/ui";
import { protocolLine } from "@/features/profiles/index.ts";
import { useDraft } from "./context.ts";

/** Profile cards. Every new spacecraft pins the chosen profile (a manifest row may name another). */
const { draft, set, profiles, proposal } = useDraft();
const choices = computed(() => profiles());
const error = computed(() => {
  const p = proposal();
  return p.status === "incomplete" ? (p.errors.profileId ?? null) : null;
});
const selected = computed({
  get: () => (draft.profileId === "" ? null : draft.profileId),
  set: (value: string | null) => set("profileId", value ?? ""),
});
</script>

<template>
  <ApEmptyState
    v-if="choices.length === 0"
    state="off"
    headline="No profiles yet"
    sentence="New spacecraft pin a profile, so create one first. This draft is kept."
  >
    <RouterLink :to="{ name: 'setup.profile.new' }" class="text-md text-readout hover:underline"
      >New profile</RouterLink
    >
  </ApEmptyState>
  <fieldset v-else class="m-0 flex flex-col gap-2 border-0 p-0">
    <legend class="ap-label mb-2">Profile</legend>
    <ApOption
      v-for="choice in choices"
      :key="choice.id"
      v-model="selected"
      :value="choice.id"
      name="profile"
      :title="`${choice.name} · v${choice.version}`"
      :description="`${protocolLine(choice)} · ${plural(choice.spacecraftCount, 'spacecraft', 'spacecraft')} use it`"
    />
    <p v-if="error && draft.profileId !== ''" class="m-0 text-sm text-caution-text">{{ error }}</p>
    <!-- AddSpacecraft.md step 01: opens in place of the flow; the draft is kept (session storage). -->
    <RouterLink
      :to="{ name: 'setup.profile.new' }"
      class="self-start text-md text-readout hover:underline"
      >New profile</RouterLink
    >
  </fieldset>
</template>
