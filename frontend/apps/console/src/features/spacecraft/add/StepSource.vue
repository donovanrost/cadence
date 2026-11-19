<script setup lang="ts">
import { computed } from "vue";
import { ApPanel, ApSegmented, type ApSegment } from "@/ui";
import ManifestSource from "./ManifestSource.vue";
import ProfilePicker from "./ProfilePicker.vue";
import { useDraft } from "./context.ts";
import type { Draft } from "./draft.ts";

/** A1 Source: one profile for a generated batch, or a manifest of rows. */
const { draft, set } = useDraft();
const sources: readonly ApSegment<Draft["source"]>[] = [
  { value: "profile", label: "From a profile" },
  { value: "manifest", label: "From a manifest" },
];
const source = computed({
  get: () => draft.source,
  set: (value: Draft["source"]) => {
    set("source", value);
    if (value === "profile" && draft.planeMode === "manifest") set("planeMode", "none");
  },
});
</script>

<template>
  <ApPanel index="A1" title="Source">
    <div class="flex flex-col gap-4">
      <ApSegmented v-model="source" :options="sources" label="Source type" />
      <ManifestSource v-if="draft.source === 'manifest'" />
      <ProfilePicker />
    </div>
  </ApPanel>
</template>
