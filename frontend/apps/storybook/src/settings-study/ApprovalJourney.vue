<script setup lang="ts">
import type { ApprovalMode } from "./fixtures";
defineProps<{ approval: ApprovalMode }>();
</script>
<template>
  <ol class="st-journey" aria-label="Activation steps">
    <li>
      <span class="hero-document-text" aria-hidden="true" /><strong>Prepare</strong
      ><small>Save a revision</small>
    </li>
    <li>
      <span
        :class="approval === 'independent' ? 'hero-user-group' : 'hero-magnifying-glass'"
        aria-hidden="true"
      /><strong>{{ approval === "independent" ? "Independent review" : "Review changes" }}</strong
      ><small>{{ approval === "independent" ? "A different person" : "The same operator" }}</small>
    </li>
    <li>
      <span class="hero-bolt" aria-hidden="true" /><strong>Activate</strong
      ><small>Apply the revision</small>
    </li>
  </ol>
</template>
