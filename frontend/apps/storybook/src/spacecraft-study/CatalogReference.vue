<script setup lang="ts">
import CadenceLink from "@cadence/ui/CadenceLink.vue";
import { revisions } from "./fixtures";
import "./spacecraft-study.css";
</script>

<template>
  <main class="spacecraft-study sc-reference">
    <p class="sc-eyebrow">DESIGN STUDY / SAMPLE CATALOG REFERENCE</p>
    <div class="sc-section-heading">
      <div>
        <h1>Kestrel FSW</h1>
        <p class="sc-muted">Imported flight software definitions · onboard computer</p>
      </div>
      <CadenceLink
        href="/iframe.html?id=design-studies-spacecraft-configuration--explore&viewMode=story"
        >Explore spacecraft setup<template #icon><span class="hero-arrow-right" /></template
      ></CadenceLink>
    </div>
    <section
      v-for="revision in [revisions['3.4'], revisions['3.3']]"
      :id="`revision-${revision.id}`"
      :key="revision.id"
      class="sc-surface"
    >
      <header class="sc-block-heading">
        <h2>Revision {{ revision.id }}</h2>
        <span class="sc-muted">{{ revision.software }} · {{ revision.date }}</span>
      </header>
      <div class="sc-block-body sc-stack">
        <div class="sc-mini-metrics">
          <span
            ><strong>{{ revision.packets }}</strong
            >packets</span
          ><span
            ><strong>{{ revision.parameters }}</strong
            >parameters</span
          ><span
            ><strong>{{ revision.commands }}</strong
            >commands</span
          >
        </div>
        <h3>Definition highlights</h3>
        <ul class="sc-definition-list">
          <li v-for="addition in revision.additions" :key="addition">
            <span class="hero-plus-small sc-icon-sm" aria-hidden="true" />{{ addition }}
          </li>
        </ul>
        <h3>Initial sample usage</h3>
        <p>
          <strong>{{ revision.id === "3.4" ? "KESTREL-01" : "KESTREL-02" }}</strong> · active OBC
          binding · Telemetry Decom and Commanding
        </p>
        <p class="sc-muted">
          This reference uses the study’s initial fixtures. Edits in another Storybook tab are local
          to that tab.
        </p>
      </div>
    </section>
  </main>
</template>

<style scoped>
.sc-reference {
  height: auto;
  min-height: 100dvh;
  gap: 24px;
  padding: 28px;
}
.sc-reference h1 {
  font-size: 26px;
  font-weight: 600;
}
</style>
