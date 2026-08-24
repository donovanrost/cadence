<script setup lang="ts">
import {ref} from "vue"

defineProps<{message: string}>()

const localCount = ref(0)
</script>

<template>
  <section id="livevue-demo" class="card border border-primary/30 bg-base-200 p-4">
    <p id="livevue-demo-message">{{ message }}</p>
    <p id="livevue-demo-count">Local Vue count: {{ localCount }}</p>
    <button id="livevue-demo-increment" class="btn btn-primary" type="button" @click="localCount++">
      Increment locally
    </button>
  </section>
</template>
