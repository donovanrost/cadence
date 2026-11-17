<script setup lang="ts">
import type { Pass } from "@/features/contacts/index.ts";
import { computed } from "vue";
import { attentionMeta, attentionWords, UnshownCallout } from "@/features/now/index.ts";
import { ApCallout, plural } from "@/ui";

/**
 * U31 for K1's day: "2 pass resolutions need you · 1 acknowledged", each linking to its contact
 * (drawer). Acknowledged items stay (U21) and sort last with Now's "ACK SAM T." meta.
 */
const props = defineProps<{ passes: readonly Pass[] }>();
/** U86: passes whose item this console couldn't read: counted in the total, listed in the line. */
const unshown = computed(() => props.passes.flatMap((p) => p.attention_unshown ?? []));
const readable = computed(() => props.passes.filter((p) => p.attention));
const acknowledged = computed(
  () => props.passes.filter((p) => p.attention?.state === "acknowledged").length,
);

function what(p: Pass): string {
  return p.attention ? attentionWords(p.attention).what : "";
}
/** `SVA · ACK SAM T. · 00:13Z`, Now's meta plus the AOS. */
function meta(p: Pass): string {
  const m = p.attention ? attentionMeta(p.attention) : null;
  return `${m ? `${m} · ` : ""}${p.starts_at.slice(11, 16)}Z`;
}
</script>

<template>
  <UnshownCallout :unshown="unshown" />
  <ApCallout v-if="passes.length > 0" tone="caution">
    <span class="flex flex-col gap-1">
      <span
        >{{ plural(passes.length, "pass resolution") }}
        {{ passes.length === 1 ? "needs" : "need" }} you<template v-if="acknowledged > 0">
          · {{ acknowledged }} acknowledged</template
        ></span
      >
      <RouterLink
        v-for="p in readable"
        :key="p.id"
        :to="{ name: 'ops.contacts', query: { contact: p.id } }"
        class="max-md:hit-44 text-sm text-readout underline-offset-2 hover:underline"
        >{{ p.spacecraft?.name ?? p.spacecraft_id ?? "Unknown spacecraft" }} · {{ what(p) }}
        <span class="font-mono text-text-3">{{ meta(p) }}</span></RouterLink
      >
    </span>
  </ApCallout>
</template>
