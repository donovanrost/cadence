<script setup lang="ts">
import type { MissionId } from "@/api/index.ts";
import { ref } from "vue";
import { ApButton } from "@/ui";
import ResolveSheet from "./ResolveSheet.vue";
import type { ResolvablePass } from "./types.ts";

/**
 * ux U32 row actions for an unconfirmed pass (DECISIONS #53): Mark booked / Mark not booked.
 * Screens put this in UnconfirmedCallout's `row-actions` slot for org admins only.
 */
defineProps<{ missionId: MissionId; planId: string; pass: ResolvablePass }>();
const emit = defineEmits<{ resolved: [] }>();
const sheet = ref<InstanceType<typeof ResolveSheet> | null>(null);
</script>

<template>
  <span class="flex items-center gap-2">
    <ApButton size="compact" @click="sheet?.open('booked')">Mark booked</ApButton>
    <ApButton size="compact" @click="sheet?.open('not_booked')">Mark not booked</ApButton>
  </span>
  <ResolveSheet
    ref="sheet"
    :mission-id="missionId"
    :plan-id="planId"
    :pass="pass"
    @resolved="emit('resolved')"
  />
</template>
