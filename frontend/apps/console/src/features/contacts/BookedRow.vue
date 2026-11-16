<script setup lang="ts">
import type { RouteLocationRaw } from "vue-router";
import { computed } from "vue";
import { RouterLink } from "vue-router";
import type { Pass } from "./api.ts";

/**
 * D2's 'Booked' row (ux U74): 'From the 11-14 plan (R3) · for Block 1 daily', both links. A plan
 * without a day reads 'From a contact plan (R3)'; without a requirement the 'for' part is left out.
 * Off-plan bookings keep their own line, so this shows only for plan bookings.
 */
const props = defineProps<{ pass: Pick<Pass, "plan" | "requirement"> }>();
const plan = computed(() => props.pass.plan);
const planWords = computed(() => {
  const p = plan.value;
  if (!p) return null;
  const r = p.version === null ? "" : ` (R${p.version})`;
  return p.day ? `the ${p.day.slice(5, 10)} plan${r}` : `a contact plan${r}`;
});
const planTo = computed<RouteLocationRaw | null>(() => {
  const p = plan.value;
  if (!p) return null;
  return {
    name: "ops.contacts.plan",
    query: {
      plan: p.id,
      ...(p.day ? { day: p.day.slice(0, 10) } : {}),
      ...(p.version === null ? {} : { version: String(p.version) }),
    },
  };
});
const requirement = computed(() => props.pass.requirement ?? null);
</script>

<template>
  <p v-if="plan && planTo" class="m-0 text-sm text-text-2">
    <span class="text-text-4">Booked</span>
    From <RouterLink :to="planTo" class="text-readout hover:underline">{{ planWords }}</RouterLink
    ><template v-if="requirement">
      · for
      <RouterLink
        :to="{
          name: 'setup.contact-planning.requirement',
          params: { requirementId: requirement.id },
        }"
        class="text-readout hover:underline"
        >{{ requirement.name }}</RouterLink
      ></template
    >
  </p>
</template>
