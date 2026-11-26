<script setup lang="ts">
import { computed, ref, useId } from "vue";
import { ApButton } from "@/ui";
import { madeOfLine, madeOfParts, type Composition } from "../composition.ts";
import { composedByLine, composedImportersLine } from "./words.ts";
import type { ModelRevision } from "./api.ts";

/**
 * U109, a composed base's page: Made of (up to three, then "and N more" with Show all, a
 * disclosure: B3, A5), "Composed by … at …", and who imported each catalog. A one-catalog page
 * never shows this.
 */
const props = defineProps<{ revision: ModelRevision; composition: Composition }>();
const all = ref(false);
const listId = useId();
const many = computed(() => madeOfParts(props.composition).length > 3);
const composedBy = computed(() => composedByLine(props.composition));
const importers = computed(() => composedImportersLine(props.revision));
</script>

<template>
  <div class="flex flex-col gap-1">
    <p :id="listId" data-made-of class="m-0 text-md text-text-2">
      {{ madeOfLine(composition, all) }}
      <ApButton
        v-if="many"
        size="compact"
        variant="ghost"
        :aria-expanded="all"
        :aria-controls="listId"
        @click="all = !all"
        >{{ all ? "Show first 3" : `Show all ${madeOfParts(composition).length}` }}</ApButton
      >
    </p>
    <p v-if="composedBy" data-composed-by class="m-0 text-sm text-text-2">{{ composedBy }}</p>
    <p v-if="importers" data-composed-importers class="m-0 text-sm text-text-2">{{ importers }}</p>
  </div>
</template>
