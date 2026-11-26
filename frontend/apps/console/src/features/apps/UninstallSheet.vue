<script setup lang="ts">
import { ref, useId } from "vue";
import { ApButton, ApSheet } from "@/ui";
import {
  uninstallLines,
  uninstallTitle,
  uninstallVerb,
  type UninstallScope,
} from "./uninstall-words.ts";

/** Confirms Uninstall (#679): the consequence lines describe the dialog; `Uninstall {app}` (danger). */
const props = defineProps<{
  appName: string;
  scope: UninstallScope;
  /** Where focus lands on close when the Uninstall button that opened it is gone (a11y A5). */
  returnFocus: () => HTMLElement | null;
}>();
const emit = defineEmits<{ confirm: [] }>();
const sheet = ref<InstanceType<typeof ApSheet> | null>(null);
const linesId = useId();
defineExpose({ open: () => sheet.value?.open(), close: () => sheet.value?.close() });
</script>

<template>
  <ApSheet
    ref="sheet"
    :title="uninstallTitle(props.appName)"
    width="narrow"
    :described-by="linesId"
    :return-focus="returnFocus"
  >
    <div :id="linesId" class="flex flex-col gap-2">
      <p v-for="line in uninstallLines(props.scope)" :key="line" class="m-0 text-md text-text-2">
        {{ line }}
      </p>
    </div>
    <template #footer>
      <ApButton variant="ghost" @click="sheet?.close()">Cancel</ApButton>
      <ApButton variant="danger" @click="emit('confirm')">{{
        uninstallVerb(props.appName)
      }}</ApButton>
    </template>
  </ApSheet>
</template>
