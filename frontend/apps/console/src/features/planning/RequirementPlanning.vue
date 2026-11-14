<script setup lang="ts">
import { computed } from "vue";
import { SINGLE_BOOKINGS_LIVE } from "@/features/contacts/index.ts";
import { useCommandAccess } from "@/features/commands/index.ts";
import { ApButton } from "@/ui";
import { planningDay, type RequirementDetail } from "./requirements.ts";

/**
 * ux P4 "Planning it" (director 11-14: whole-day planning): `Plan 11-14` opens Contacts › Plan for
 * the requirement's day, for every member as Plan itself does; book a pass instead for a one-off,
 * behind Contacts' own Book a pass gate. 'Open plan R41' waits for api's held_by.
 */
const props = defineProps<{ requirement: RequirementDetail }>();
const access = useCommandAccess();
const day = computed(() => planningDay(props.requirement, Date.now()));
const canBook = computed(() => SINGLE_BOOKINGS_LIVE && access.value.abort);
</script>

<template>
  <div v-if="day" class="flex flex-col items-start gap-2">
    <ApButton :to="{ name: 'ops.contacts.plan', query: { day: day.iso } }"
      >Plan {{ day.md }}</ApButton
    >
    <p class="m-0 text-md text-text-3">
      Cadence plans a whole day at a time: this requirement is planned with the rest of
      {{ day.md }}'s requirements, so it can't take capacity another one needs.
      <template v-if="canBook">
        For a one-off pass outside any plan,
        <RouterLink
          :to="{
            name: 'ops.contacts',
            query: {
              book: requirement.spacecraft.id,
              book_from: day.from,
              book_to: day.to,
            },
          }"
          class="text-readout hover:underline"
          >book a pass</RouterLink
        >
        instead.
      </template>
    </p>
  </div>
</template>
