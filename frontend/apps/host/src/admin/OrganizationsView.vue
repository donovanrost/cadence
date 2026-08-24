<script setup lang="ts">
import { dateLabel, organizations } from "./admin-data";
</script>

<template>
  <section id="organizations-view" class="table-page">
    <header class="table-page__head">
      <h1>Organizations</h1>
      <p>
        Tenant boundaries are explicit. Membership, missions, and scoped resources inherit from the
        organization record.
      </p>
    </header>

    <div class="table-summary" aria-label="Organization summary">
      <span
        ><strong>{{ organizations.length }}</strong> ACTIVE ORGANIZATIONS</span
      >
      <span><strong>27</strong> TOTAL MEMBERS</span>
      <span><strong>06</strong> OWNED MISSIONS</span>
    </div>

    <div class="organization-table" role="table" aria-label="Organizations">
      <div class="organization-table__row organization-table__head" role="row">
        <span role="columnheader">ORGANIZATION</span>
        <span role="columnheader">REFERENCE</span>
        <span role="columnheader">MEMBERS</span>
        <span role="columnheader">MISSIONS</span>
        <span role="columnheader">UPDATED</span>
      </div>
      <article
        v-for="organization in organizations"
        :id="organization.id"
        :key="organization.id"
        class="organization-table__row"
        role="row"
      >
        <strong role="cell">{{ organization.name }}</strong>
        <span role="cell">{{ organization.reference }}</span>
        <span role="cell">{{ organization.members.toString().padStart(2, "0") }}</span>
        <span role="cell">{{ organization.missions.toString().padStart(2, "0") }}</span>
        <time role="cell" :datetime="organization.updatedAt">
          {{ dateLabel(organization.updatedAt) }}
        </time>
      </article>
    </div>

    <footer>
      <span>WRITE OPERATIONS / NOT YET CONNECTED</span>
      <span>DATA / POC FIXTURE</span>
    </footer>
  </section>
</template>

<style scoped>
.table-page {
  min-height: 100%;
  padding: var(--cadence-space-10);
}

.table-page__head {
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(280px, 480px);
  gap: var(--cadence-space-10);
  align-items: end;
  padding-bottom: var(--cadence-space-10);
}

.table-page footer,
.table-summary,
.organization-table__head,
.organization-table span,
.organization-table time {
  font-family: var(--cadence-font-mono);
}

.table-page h1 {
  margin: 0;
  color: var(--cadence-color-text-strong);
  font-size: var(--cadence-type-display-lg);
  font-weight: 580;
  letter-spacing: var(--cadence-tracking-display);
  line-height: var(--cadence-leading-tight);
}

.table-page__head > p {
  margin: 0;
  color: var(--cadence-color-text-secondary);
  line-height: var(--cadence-leading-copy);
}

.table-summary {
  display: flex;
  gap: var(--cadence-space-6);
  padding: var(--cadence-space-4) 0;
  border-top: 1px solid var(--cadence-color-border);
  border-bottom: 1px solid var(--cadence-color-border);
  color: var(--cadence-color-text-muted);
  font-size: var(--cadence-type-label);
  letter-spacing: var(--cadence-tracking-label);
}

.table-summary strong {
  color: var(--cadence-color-text-strong);
}

.organization-table {
  margin-top: var(--cadence-space-8);
  border: 1px solid var(--cadence-color-border);
}

.organization-table__row {
  display: grid;
  grid-template-columns: minmax(220px, 1.2fr) minmax(180px, 1fr) 100px 100px minmax(140px, 0.7fr);
  min-height: 72px;
  border-bottom: 1px solid var(--cadence-color-border-subtle);
}

.organization-table__row:last-child {
  border-bottom: 0;
}

.organization-table__row > * {
  display: flex;
  align-items: center;
  padding: var(--cadence-space-4);
  border-right: 1px solid var(--cadence-color-border-subtle);
}

.organization-table__row > *:last-child {
  border-right: 0;
}

.organization-table__head {
  min-height: 40px;
  color: var(--cadence-color-text-muted);
  font-size: var(--cadence-type-label);
  letter-spacing: var(--cadence-tracking-label);
}

.organization-table article:hover {
  background: var(--cadence-color-surface-inset);
}

.organization-table article strong {
  color: var(--cadence-color-text-strong);
  font-size: var(--cadence-type-body-md);
}

.organization-table article span,
.organization-table article time {
  color: var(--cadence-color-text-secondary);
  font-size: var(--cadence-type-body-sm);
}

.table-page footer {
  display: flex;
  justify-content: space-between;
  gap: var(--cadence-space-6);
  margin-top: var(--cadence-space-6);
  color: var(--cadence-color-text-muted);
  font-size: var(--cadence-type-label);
  letter-spacing: var(--cadence-tracking-label);
}

@media (max-width: 1050px) {
  .organization-table {
    overflow-x: auto;
  }

  .organization-table__row {
    min-width: 860px;
  }
}

@media (max-width: 720px) {
  .table-page {
    padding: var(--cadence-space-6) var(--cadence-space-4);
  }

  .table-page__head {
    grid-template-columns: 1fr;
    gap: var(--cadence-space-5);
  }

  .table-summary,
  .table-page footer {
    flex-direction: column;
    gap: var(--cadence-space-2);
  }
}
</style>
