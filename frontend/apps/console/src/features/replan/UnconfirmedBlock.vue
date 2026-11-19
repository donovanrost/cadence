<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { ResolveBookingActions } from "@/features/resolutions/index.ts";
import {
  UnconfirmedCallout,
  type PlanDetail,
  type SpacecraftName,
} from "@/features/scheduling/index.ts";

/** U30 + U32 in K2: the unconfirmed list, with Mark booked / Mark not booked for org admins. */
defineProps<{
  missionId: MissionId;
  plan: PlanDetail;
  nameOf: (id: string | null) => SpacecraftName | null;
  isAdmin: boolean;
}>();
const emit = defineEmits<{ resolved: [] }>();
</script>

<template>
  <UnconfirmedCallout :plan="plan" :name-of="nameOf" :member-note="!isAdmin">
    <template v-if="isAdmin" #row-actions="{ pass }">
      <ResolveBookingActions
        :mission-id="missionId"
        :plan-id="plan.id"
        :pass="pass"
        @resolved="emit('resolved')"
      />
    </template>
  </UnconfirmedCallout>
</template>
