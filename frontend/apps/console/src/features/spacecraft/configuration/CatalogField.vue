<script setup lang="ts">
import { computed, ref } from "vue";
import { ApButton } from "@/ui";
import type { ConfigurationDocument, ConfigurationSnapshot, WorkspaceKey } from "./api.ts";
import CatalogPickerSheet from "./CatalogPickerSheet.vue";
import { profileSetsLine } from "./catalog-words.ts";
import { catalogWord } from "./words.ts";

/**
 * #595b (U94): the draft's catalog revision, "catalog rev 14", with Change… (Choose… when none).
 * When the craft's profile sets it (catalog_set_by), Change… is off with U94's reason and Open
 * profile; the server's refusal is the backstop for an older snapshot.
 */
const props = defineProps<{
  workspace: WorkspaceKey;
  snapshot: ConfigurationSnapshot;
  doc: ConfigurationDocument;
}>();
const emit = defineEmits<{ edit: [patch: Partial<ConfigurationDocument>] }>();
const picker = ref<InstanceType<typeof CatalogPickerSheet> | null>(null);
const byProfile = computed(() => props.snapshot.catalog_set_by === "profile");
const profileId = computed(() => props.snapshot.profile?.id ?? null);
</script>

<template>
  <div class="flex flex-col gap-1.5">
    <span class="ap-label">Catalog revision</span>
    <div class="flex flex-wrap items-center gap-2">
      <span class="text-md text-readout">{{ catalogWord(snapshot, doc.catalog_revision_id) }}</span>
      <ApButton
        size="compact"
        variant="ghost"
        :disabled="byProfile"
        :disabled-reason="byProfile ? profileSetsLine(snapshot.name) : undefined"
        @click="picker?.open()"
        >{{ doc.catalog_revision_id ? "Change…" : "Choose…" }}</ApButton
      >
      <ApButton
        v-if="byProfile && profileId"
        size="compact"
        variant="ghost"
        :to="{ name: 'setup.profile', params: { profileId } }"
        >Open profile</ApButton
      >
    </div>
    <CatalogPickerSheet
      ref="picker"
      :workspace="workspace"
      :snapshot="snapshot"
      :doc="doc"
      @choose="emit('edit', $event)"
    />
  </div>
</template>
