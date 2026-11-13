<script setup lang="ts">
import { computed } from "vue";
import { ApTag } from "@/ui";
import { gapText, type FocusDay } from "./focus-day.ts";

/** K1 C rule chips: contacts (GO/HOLD), longest gap and requested uplink passes (measures until a rule sets a limit or need). */
const props = defineProps<{ view: FocusDay }>();
/** A verdict only once a rule carries a gap limit (max_gap_seconds); until then a measure. */
const gapMet = computed(() => {
  const v = props.view;
  return v.gapLimitSeconds !== null && v.longestGapSeconds !== null
    ? v.longestGapSeconds <= v.gapLimitSeconds
    : null;
});
const contactsMet = computed(() => {
  const c = props.view.contacts;
  return c && c.need !== null ? c.have >= c.need : null;
});
</script>

<template>
  <ul class="m-0 flex list-none flex-wrap items-center gap-x-4 gap-y-2 p-0">
    <li v-if="view.contacts" class="flex items-center gap-2 font-mono text-sm text-text-2">
      Contacts {{ view.contacts.have
      }}{{ view.contacts.need === null ? "" : `/${view.contacts.need}` }}
      <ApTag
        v-if="contactsMet !== null"
        :state="contactsMet ? 'nominal' : 'caution'"
        :label="contactsMet ? 'GO' : 'HOLD'"
      />
    </li>
    <li
      v-if="view.longestGapSeconds !== null"
      class="flex items-center gap-2 font-mono text-sm text-text-2"
    >
      Longest gap {{ gapText(view.longestGapSeconds)
      }}{{ view.gapLimitSeconds === null ? "" : ` · max ${gapText(view.gapLimitSeconds)}` }}
      <ApTag
        v-if="gapMet !== null"
        :state="gapMet ? 'nominal' : 'caution'"
        :label="gapMet ? 'GO' : 'HOLD'"
      />
    </li>
    <li v-if="view.uplink" class="flex items-center gap-2 font-mono text-sm text-text-2">
      Uplink passes {{ view.uplink.have
      }}{{ view.uplink.need === null ? " requested" : `/${view.uplink.need}` }}
      <ApTag
        v-if="view.uplink.need !== null"
        :state="view.uplink.have >= view.uplink.need ? 'nominal' : 'caution'"
        :label="view.uplink.have >= view.uplink.need ? 'GO' : 'HOLD'"
      />
    </li>
  </ul>
</template>
