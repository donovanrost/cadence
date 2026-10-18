<script setup lang="ts">
import { computed } from "vue";
import { legacyAlarmHref } from "./contracts";
const props = defineProps<{ mission_id: unknown; query: unknown }>();
const href = computed(() => legacyAlarmHref(props.mission_id, props.query));
</script>
<template>
  <section id="alarm-legacy-destination" class="space-y-3 p-5">
    <template v-if="href"
      ><p class="text-sm">Alarm conditions are available in the mission Ops workspace.</p>
      <a :href="href" class="btn btn-primary btn-sm">Open alarm conditions</a></template
    >
    <p v-else role="alert" class="text-sm">
      Alarm conditions are unavailable for this destination.
    </p>
  </section>
</template>
