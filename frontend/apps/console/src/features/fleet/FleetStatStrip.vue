<script setup lang="ts">
import { computed } from "vue";
import { ApStatStrip, ApStatTile } from "@/ui";
import type { Fleet } from "./api.ts";
import { statTiles } from "./stats.ts";

/**
 * Six stat tiles (Now spec, Stat strip). Counts partition the fleet; unknowns render `—`. `linked`
 * (Now): each tile opens the list behind its number.
 */
const props = defineProps<{ fleet: Fleet; linked?: boolean }>();
const tiles = computed(() => statTiles(props.fleet));
</script>

<template>
  <ApStatStrip label="Fleet status" :columns="6" class="flex-none">
    <ApStatTile
      v-for="tile in tiles"
      :key="tile.label"
      :label="tile.label"
      :value="tile.value"
      :caption="tile.caption"
      :state="tile.state"
      v-bind="{
        ...(tile.denominator === undefined ? {} : { denominator: tile.denominator }),
        ...(tile.captionState === undefined ? {} : { captionState: tile.captionState }),
        ...(linked ? { to: tile.to } : {}),
      }"
    />
  </ApStatStrip>
</template>
