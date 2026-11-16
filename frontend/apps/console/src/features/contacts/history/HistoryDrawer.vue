<script setup lang="ts">
import type { MissionId, Scid } from "@/api/index.ts";
import { ApEmptyState, ApPanel } from "@/ui";
import type { Pass } from "../api.ts";
import type { HandStartedContact } from "../handStarted.ts";
import SelectedPassPanel from "../SelectedPassPanel.vue";
import ContactRecordPanel from "../ContactRecordPanel.vue";

/**
 * History's drawer (U78), one URL (`?contact=`, lead's ruling): a hand-started contact shows its
 * Contact record alone (fe-ops' panel); an id the read can't find says so; else D2 for the pass.
 */
defineProps<{
  missionId: MissionId;
  pass: Pass | null;
  handStarted: HandStartedContact | null;
  loading: boolean;
  missing: boolean;
  spacecraft: { name: string; scid: Scid | null } | null;
}>();
defineEmits<{ changed: [] }>();
</script>

<template>
  <ContactRecordPanel
    v-if="handStarted"
    :mission-id="missionId"
    :contact-id="handStarted.realized_contact_id"
  />
  <ApPanel v-else-if="missing" index="D2" title="Contact record" pane>
    <ApEmptyState state="off" headline="No contact record with this id." />
  </ApPanel>
  <SelectedPassPanel
    v-else
    :mission-id="missionId"
    :pass="pass"
    :loading="loading"
    :spacecraft="spacecraft"
    @changed="$emit('changed')"
  />
</template>
