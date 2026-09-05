<script setup lang="ts">
import { CStatus } from "@cadence/ui";
</script>

<template>
  <main class="mission-catalog-standalone">
    <header class="mission-catalog-standalone__masthead">
      <div>
        <p class="mission-catalog-eyebrow">CADENCE / DOMAIN REMOTE</p>
        <h1>Mission &amp; Catalog</h1>
      </div>
      <CStatus tone="nominal" pulse>STANDALONE PREVIEW</CStatus>
    </header>
    <p class="mission-catalog-standalone__intro">
      A first-party remote for mission identity, setup, application lifecycle, and catalog
      provenance. Phoenix supplies the authenticated data and actions at composition time.
    </p>
  </main>
</template>
