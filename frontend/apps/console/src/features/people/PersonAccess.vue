<script setup lang="ts">
import { ApPanel } from "@/ui";
import { accessGroups } from "./admin.ts";

/** People.md person page · Access: capabilities as plain sentences, grouped, YES/NO. */
defineProps<{ capabilities: readonly string[] }>();
</script>

<template>
  <ApPanel index="P1" title="Access">
    <dl class="m-0 grid grid-cols-1 gap-x-8 gap-y-3 md:grid-cols-2">
      <div v-for="g in accessGroups(capabilities)" :key="g.group">
        <dt class="ap-label mb-1">{{ g.group }}</dt>
        <dd v-for="l in g.lines" :key="l.text" class="m-0 flex justify-between gap-4 text-md">
          <span class="text-text-2">{{ l.text }}</span>
          <span class="font-mono" :class="l.yes ? 'text-readout' : 'text-text-4'">{{
            l.yes ? "YES" : "NO"
          }}</span>
        </dd>
      </div>
    </dl>
  </ApPanel>
</template>
