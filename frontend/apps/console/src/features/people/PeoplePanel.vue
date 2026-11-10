<script setup lang="ts">
import { computed, ref } from "vue";
import { ApField, ApPanel, formatCount } from "@/ui";
import PeopleTable from "./PeopleTable.vue";
import { matchesPerson, type Member } from "./api.ts";

/** U1 · People: filter + table (names link to the person page). */
const props = defineProps<{ members: readonly Member[] }>();
const query = ref("");
const shown = computed(() => props.members.filter((m) => matchesPerson(m, query.value)));
</script>

<template>
  <ApPanel index="U1" title="People" flush>
    <template #header
      ><div class="w-[260px]">
        <ApField
          v-model="query"
          label="Filter people"
          hidden-label
          type="search"
          placeholder="Filter by name, email or role"
        /></div
    ></template>
    <template #meta>{{ formatCount(shown.length) }} of {{ formatCount(members.length) }}</template>
    <PeopleTable :rows="shown" />
  </ApPanel>
</template>
