<script setup lang="ts">
import { ref } from "vue";
import { ApButton, ApCallout } from "@/ui";

/**
 * The plan's review line (U97): sent back to its drafter, or resubmitted after a send-back, each
 * with All decisions. The sent-back line can take focus (#244 A5: PlanScreen moves focus to it
 * after a Send back, when focus was lost).
 */
defineProps<{
  sentBack: string | null;
  resubmitted: Readonly<{ line: string; earlier: string | null }> | null;
}>();
defineEmits<{ history: [] }>();
const box = ref<HTMLElement | null>(null);
defineExpose({ box });
</script>

<template>
  <div v-if="sentBack" ref="box" tabindex="-1">
    <ApCallout tone="caution"
      >{{ sentBack
      }}<template #action
        ><ApButton size="compact" variant="ghost" @click="$emit('history')"
          >All decisions</ApButton
        ></template
      ></ApCallout
    >
  </div>
  <ApCallout v-else-if="resubmitted" tone="info">
    <span class="flex flex-col gap-1">
      <span>{{ resubmitted.line }}</span>
      <span v-if="resubmitted.earlier" class="text-sm text-text-3">{{ resubmitted.earlier }}</span>
    </span>
    <template #action
      ><ApButton size="compact" variant="ghost" @click="$emit('history')"
        >All decisions</ApButton
      ></template
    >
  </ApCallout>
</template>
