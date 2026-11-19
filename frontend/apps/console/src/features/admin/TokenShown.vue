<script setup lang="ts">
import { ApButton, ApCallout } from "@/ui";

/** The token, once (Admin.md): copy it now; "I've stored the token" unlocks Done. */
const props = defineProps<{ token: string }>();
const stored = defineModel<boolean>({ required: true });
const copy = () => void navigator.clipboard.writeText(props.token).catch(() => undefined);
</script>

<template>
  <div class="flex flex-col gap-3">
    <ApCallout tone="caution">Copy this token now. Cadence won't show it again.</ApCallout>
    <div
      class="flex items-center gap-2 border border-line bg-well p-3 font-mono text-sm break-all text-readout"
    >
      <span class="min-w-0 flex-1">{{ token }}</span
      ><ApButton size="compact" @click="copy">Copy</ApButton>
    </div>
    <label class="flex items-center gap-2 text-md text-readout"
      ><input v-model="stored" type="checkbox" class="size-4" />I've stored the token</label
    >
  </div>
</template>
