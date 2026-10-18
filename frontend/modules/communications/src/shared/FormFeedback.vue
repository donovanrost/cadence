<script setup lang="ts">
import type { FormFeedback } from "./form-workflow.contracts";
defineProps<{ feedback?: FormFeedback; id: string }>();
defineEmits<{ retry: [] }>();
</script>
<template>
  <div
    v-if="feedback"
    :id="id"
    role="status"
    aria-live="polite"
    class="text-sm text-base-content/70"
  >
    <p>
      {{
        feedback.saving
          ? "Saving…"
          : feedback.validating
            ? "Checking the current draft…"
            : (feedback.message ??
              (feedback.canSubmit
                ? "Current draft validated. Ready to save."
                : "Complete the form to validate this draft."))
      }}
    </p>
    <button
      v-if="feedback.canRevalidate"
      :id="id + '-retry'"
      type="button"
      class="btn btn-sm btn-ghost mt-2"
      @click="$emit('retry')"
    >
      Recheck draft
    </button>
  </div>
</template>
