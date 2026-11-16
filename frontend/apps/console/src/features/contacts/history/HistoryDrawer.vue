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
  /** The read failed for another reason than not found (fe-ops 22b1e653a): D2 offers Try again. */
  failed: boolean;
  spacecraft: { name: string; scid: Scid | null } | null;
}>();
defineEmits<{ changed: [] }>();
</script>

<template>
  <ContactRecordPanel
    v-if="handStarted"
    :mission-id="missionId"
    :contact-id="handStarted.realized_contact_id"
    :contact="handStarted"
  />
  <ApPanel v-else-if="missing" index="D2" title="Contact record" pane>
    <ApEmptyState state="off" headline="No contact record with this id." />
  </ApPanel>
  <SelectedPassPanel
    v-else
    :mission-id="missionId"
    :pass="pass"
    :loading="loading"
    :failed="failed"
    :spacecraft="spacecraft"
    @changed="$emit('changed')"
  />
</template>
