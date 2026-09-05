<script setup lang="ts">
defineProps<{
  wrapperClass: string;
  number: string;
  numberClass: string;
  title: string;
  titleClass: string;
  dividerClass: string;
}>();
</script>

<template>
  <div :class="wrapperClass">
    <span :class="numberClass">{{ number }}</span>
    <h2 :class="titleClass">{{ title }}</h2>
    <div :class="dividerClass"></div>
  </div>
</template>
