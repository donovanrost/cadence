<script setup lang="ts">
import { ApStatusMark } from "@/ui";
import { NO_PREDICTED_PASS, noPredictedPass, type OfferGeometry } from "./geometry.ts";

/**
 * #895: on an offer or alternative that prediction covers but no predicted pass backs (a stale
 * element set, a wrong station location or a provider error). A caution, mark and word; the offer
 * stays bookable. false and null say nothing.
 */
defineProps<{ geometry: OfferGeometry }>();
</script>

<template>
  <!-- A span (phrasing content): it also sits inside an alternative's button. -->
  <span
    v-if="noPredictedPass(geometry)"
    class="flex items-center gap-2 text-sm text-caution-text"
    data-no-predicted-pass
  >
    <ApStatusMark state="caution" />{{ NO_PREDICTED_PASS }}
  </span>
</template>
