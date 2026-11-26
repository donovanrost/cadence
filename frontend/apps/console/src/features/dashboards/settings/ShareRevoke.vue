<script setup lang="ts">
import { ref, watch } from "vue";
import { ApButton, ApInlineConfirm } from "@/ui";

/**
 * A share row's Revoke… (ux): the kit's in-place confirm. It opens on Cancel and Esc backs out
 * (A1, A4). After the action, the row turns revoked on the reload: the confirm closes then, and
 * focus goes to `returnFocus`, since Revoke… is gone (A5). A refusal is read under the question.
 */
const props = defineProps<{
  active: boolean;
  busy: boolean;
  refusal: string | null;
  returnFocus: () => HTMLElement | null;
}>();
const emit = defineEmits<{ revoke: [] }>();
const open = ref(false);
watch(
  () => props.active,
  (now) => {
    if (!now) open.value = false;
  },
);
</script>

<template>
  <ApInlineConfirm
    v-model:open="open"
    action="Revoke the link"
    :busy="busy"
    busy-reason="Revoking…"
    :refusal="refusal"
    :return-focus="returnFocus"
    @confirm="emit('revoke')"
  >
    <template v-if="active" #trigger="{ attrs }">
      <ApButton size="compact" variant="ghost" v-bind="attrs">Revoke…</ApButton>
    </template>
    Revoke this share link? Anyone who has it loses the view now.
  </ApInlineConfirm>
</template>
