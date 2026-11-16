<script setup lang="ts">
import { computed } from "vue";
import type { RouteLocationRaw } from "vue-router";
import { ApTakeoverHeader } from "@/ui";
import { useConsoleScope } from "./scope.ts";

/**
 * Takeover screens' banner (U19): replaces the shell top bar. The context line starts with
 * `ORG / MISSION`, then the screen's own context. Teleports out of <main> into the shell target.
 */
const props = defineProps<{
  title: string;
  context?: string | undefined;
  close: RouteLocationRaw;
  closeLabel?: string | undefined;
  /** h1 when the header title is the page title (wizards); p when the screen has its own h1. */
  titleAs?: "h1" | "p" | undefined;
  /** False: no UTC clock (a phone layout, see ApTakeoverHeader). */
  clock?: boolean | undefined;
}>();
const scope = useConsoleScope();
const fullContext = computed(() => {
  const s = scope.value;
  const where = s.kind === "mission" ? `${s.organization.name} / ${s.mission.name}` : null;
  return [where, props.context].filter(Boolean).join(" · ");
});
</script>

<template>
  <Teleport to="#ap-takeover-header" defer>
    <ApTakeoverHeader
      :title="title"
      :context="fullContext"
      :close="close"
      :close-label="closeLabel"
      :title-as="titleAs ?? 'p'"
      :clock="clock ?? true"
    >
      <template v-if="$slots.title" #title><slot name="title" /></template>
      <template v-if="$slots.steps" #steps><slot name="steps" /></template>
      <template v-if="$slots.clocks" #clocks><slot name="clocks" /></template>
      <template v-if="$slots.actions" #actions><slot name="actions" /></template>
      <template v-if="$slots.subrow" #subrow><slot name="subrow" /></template>
    </ApTakeoverHeader>
  </Teleport>
</template>
