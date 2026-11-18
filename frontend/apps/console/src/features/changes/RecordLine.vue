<script setup lang="ts">
import { AdminModeTag } from "@/shell";
import type { HeaderPart } from "./revision-record.ts";

/** A four-eyes record line (U89): its text, with the ADMIN MODE tag right after a name that needs it. */
defineProps<{ parts: readonly HeaderPart[] }>();
</script>

<template>
  <template v-for="(part, i) in parts" :key="i"
    ><template v-if="'text' in part">{{ part.text }}</template
    ><template v-else
      >{{ part.actor.name
      }}<AdminModeTag v-if="part.actor.adminMode" class="ml-1.5 align-middle" /></template
  ></template>
</template>
