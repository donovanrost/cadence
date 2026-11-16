<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { ApPanel } from "@/ui";
import ContactRecordView from "./ContactRecordView.vue";

/**
 * U78: the drawer for a hand-started contact (no reservation): the A13 record alone, with no
 * reservation section and no pass actions. `contactId` is its realized contact id.
 */
defineProps<{ missionId: MissionId; contactId: string }>();
</script>

<template>
  <ApPanel index="D2" title="Contact record" pane flush>
    <div class="p-3">
      <ContactRecordView :mission-id="missionId" :contact-id="contactId" alone />
    </div>
  </ApPanel>
</template>
