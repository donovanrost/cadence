<script setup lang="ts">
import { computed } from "vue";
import { ApStatusMark } from "@/ui";
import { ephemerisSummary, membersLink, type Ephemeris } from "./ephemeris.ts";

/**
 * #975: how a provider gets orbits and its spacecraft's orbit counts, every non-zero one. A
 * caution is mark, color and word; zero counts never show. A caution's count links to its
 * spacecraft (#972's member list).
 */
const props = defineProps<{ ephemeris: Ephemeris; providerId: string }>();
const summary = computed(() => ephemerisSummary(props.ephemeris));
</script>

<template>
  <div class="flex flex-col gap-0.5" data-ephemeris>
    <span>{{ summary.lead }}</span>
    <span class="text-sm text-text-3">{{ summary.total }}</span>
    <ul v-if="summary.lines.length > 0" class="m-0 flex list-none flex-col gap-0.5 p-0">
      <li
        v-for="line in summary.lines"
        :key="line.key"
        class="flex items-center gap-2 text-sm"
        :class="line.caution ? 'text-caution-text' : 'text-text-2'"
        :data-bucket="line.key"
      >
        <ApStatusMark v-if="line.caution" state="caution" /><span
          ><RouterLink
            v-if="membersLink(providerId, line.key)"
            :to="membersLink(providerId, line.key)!"
            class="text-caution-text underline hover:text-bright max-md:hit-44"
            >{{ line.text }}</RouterLink
          ><template v-else>{{ line.text }}</template
          ><span v-if="line.note" class="text-text-3"> · {{ line.note }}</span></span
        >
      </li>
    </ul>
  </div>
</template>
