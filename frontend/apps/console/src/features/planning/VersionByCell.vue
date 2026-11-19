<script setup lang="ts">
import { computed } from "vue";
import type { Actor } from "@/api";
import { tableActor } from "@/features/changes/index.ts";
import { ApTag } from "@/ui";

/**
 * A version's author in a History table (#308/U25, ca-ux after #472): a person by name or a muted
 * "Not known" when their name isn't shown (a non-member), the Service tag for a service, never the
 * id. No actor at all means nothing was recorded.
 */
const props = defineProps<{ actor: Actor | null }>();
const cell = computed(() => tableActor(props.actor));
</script>

<template>
  <template v-if="cell"
    ><span :class="cell.muted ? 'text-text-3' : ''">{{ cell.text }}</span
    ><ApTag v-if="cell.service" class="ml-2" label="Service"
  /></template>
  <template v-else>Not recorded</template>
</template>
