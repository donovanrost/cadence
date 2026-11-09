<script setup lang="ts">
import type { Pass } from "@/features/contacts/index.ts";
import { attentionWords } from "@/features/now/index.ts";
import { ApCallout, plural } from "@/ui";

/** U31 for K1's day: "2 pass resolutions need you", each linking to its contact (drawer). */
defineProps<{ passes: readonly Pass[] }>();

function what(p: Pass): string {
  return p.attention ? attentionWords(p.attention).what : "";
}
</script>

<template>
  <ApCallout v-if="passes.length > 0" tone="caution">
    <span class="flex flex-col gap-1">
      <span
        >{{ plural(passes.length, "pass resolution") }}
        {{ passes.length === 1 ? "needs" : "need" }} you</span
      >
      <RouterLink
        v-for="p in passes"
        :key="p.id"
        :to="{ name: 'ops.contacts', query: { contact: p.id } }"
        class="max-md:hit-44 text-sm text-readout underline-offset-2 hover:underline"
        >{{ p.spacecraft?.name ?? p.spacecraft_id ?? "Unknown spacecraft" }} · {{ what(p) }}
        <span class="font-mono text-text-3"
          >{{ p.station.code ?? p.station.name ?? p.station.ref ?? "?" }} ·
          {{ p.starts_at.slice(11, 16) }}Z</span
        ></RouterLink
      >
    </span>
  </ApCallout>
</template>
