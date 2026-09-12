<script setup lang="ts">
import { inject } from "vue";
import { PLAN_DETAIL_PORT, type OpsContactPlanShowProps } from "./OpsContactPlanShow.contracts";
import { usePlanDetail } from "./plan-detail-state";
import { reviewHref } from "./plan-detail";
import PlanReviewPagination from "./PlanReviewPagination.vue";
import CadencePageHeading from "@cadence/ui/CadencePageHeading.vue";
import CadenceOpsViewport from "@cadence/ui/CadenceOpsViewport.vue";
import CadencePanel from "@cadence/ui/CadencePanel.vue";
const props = defineProps<OpsContactPlanShowProps>();
const port = props.port ?? inject(PLAN_DETAIL_PORT, undefined);
const {
  detail: d,
  reasons,
  pending,
  notice,
  enabled,
  execute,
  refresh,
  connected,
  confirmed,
} = usePlanDetail(() => props.detail, port);
const forms = [
  {
    id: "submission",
    action: "submit-plan" as const,
    reason: "submission" as const,
    title: "Submit for review",
    label: "Submission reason",
  },
  {
    id: "approval",
    action: "approve-plan" as const,
    reason: "approval" as const,
    title: "Approve reviewed plan",
    label: "Approval reason",
  },
  {
    id: "rejection",
    action: "reject-plan" as const,
    reason: "rejection" as const,
    title: "Reject reviewed plan",
    label: "Rejection reason",
  },
];
const label = (v: string) => v.replaceAll("_", " ");
const requirementHref = (mission: string, id: string, version: number) =>
  `/missions/${encodeURIComponent(mission)}/ops/requirements/${encodeURIComponent(id)}?version=${version}`;
</script>
<template>
  <CadenceOpsViewport v-if="d" id="ops-contact-plan-show-page">
    <CadencePageHeading
      :breadcrumbs="[
        {
          label: 'Contact requirements',
          href: `/missions/${encodeURIComponent(d.context.mission_id)}/ops/requirements`,
        },
        { label: 'Plan review' },
      ]"
    >
      <template #eyebrow>Mission operations / contact planning</template>
      <template #title
        >Contact plan <span class="font-mono text-primary">v{{ d.plan.version }}</span></template
      >
      <template #description
        >Review the immutable proposal before submission, approval or execution.</template
      >
      <template #metadata
        ><span class="font-mono text-xs uppercase"
          >Current plan: {{ label(d.plan.lifecycle_state) }} · v{{ d.plan.current_version }}</span
        ></template
      >
      <template #actions
        ><button
          id="refresh-plan-review"
          type="button"
          class="btn btn-sm"
          :disabled="!connected || pending"
          @click="refresh"
        >
          Refresh evidence
        </button></template
      >
    </CadencePageHeading>
    <aside
      v-if="d.plan.version !== d.plan.current_version"
      id="plan-review-historical"
      class="mb-5 border border-warning/40 bg-warning/5 p-4 text-sm"
    >
      Historical review. The current plan is v{{ d.plan.current_version }}; decisions are disabled
      for this version.
      <a
        id="review-current-plan"
        :href="reviewHref(d, d.plan.current_version)"
        class="ml-2 text-primary underline"
        >Review current version</a
      >
    </aside>
    <p
      v-if="notice"
      id="plan-operation-notice"
      role="status"
      class="mb-5 border border-info/30 bg-info/5 p-4 text-sm"
    >
      {{ notice }}
    </p>
    <p
      v-if="confirmed"
      id="plan-operation-receipt"
      class="mb-5 min-w-0 break-all border border-success/40 p-4 text-sm"
    >
      {{ confirmed.action }} · completed · {{ confirmed.receipt?.result.contactPlanId }} · v{{
        confirmed.receipt?.result.version
      }}
    </p>
    <CadencePanel header-class="" id="plan-review-summary" class="mb-5">
      <h2 class="mb-3 text-lg font-semibold">Reviewed proposal</h2>
      <div class="grid gap-4 sm:grid-cols-3">
        <p>
          <strong>{{ d.plan.selected_count }}</strong> selected for booking
        </p>
        <p>
          <strong>{{ d.plan.locked_count }}</strong> existing commitments
        </p>
        <p>
          <strong>{{ d.plan.rejected_count }}</strong> rejected options
        </p>
      </div>
      <p class="mt-4">
        Coverage {{ d.plan.coverage_satisfied ? "satisfied" : "unsatisfied" }} ·
        {{ d.plan.conflicts_clear ? "No overlap conflicts" : "Overlap conflicts present" }}
      </p>
      <p class="mt-3 whitespace-pre-wrap">{{ d.plan.rationale }}</p>
      <dl class="mt-4 text-xs">
        <dt class="hud-label">Plan identity</dt>
        <dd class="break-all font-mono">{{ d.plan.id }}</dd>
        <dt class="hud-label mt-3">Exact reviewed content hash</dt>
        <dd id="plan-reviewed-hash" class="break-all font-mono">{{ d.plan.content_sha256 }}</dd>
      </dl>
    </CadencePanel>
    <CadencePanel header-class="" id="plan-decisions" class="mb-5">
      <h2 class="mb-3 text-lg font-semibold">Decision</h2>
      <p v-if="d.plan.reviewed_decision" id="plan-reviewed-decision" class="mb-4">
        This version was {{ d.plan.reviewed_decision.decision }} by
        {{ d.plan.reviewed_decision.actor_id }}. {{ d.plan.reviewed_decision.reason }}
      </p>
      <p
        v-if="!d.permissions.decide"
        id="plan-admin-required"
        class="mb-4 text-sm text-base-content/65"
      >
        Approval and rejection require plan approval permission.
      </p>
      <p v-if="!d.plan.manual_review" class="mb-4 text-sm">
        This proposal is governed by an automation approval policy; manual approval is unavailable.
      </p>
      <div class="grid gap-5 lg:grid-cols-3">
        <form
          v-for="form in forms"
          :id="form.id"
          :key="form.id"
          @submit.prevent="execute(form.action, reasons[form.reason])"
        >
          <label :for="form.id + '-reason'" class="mb-2 block text-sm font-medium">{{
            form.label
          }}</label>
          <textarea
            :id="form.id + '-reason'"
            v-model="reasons[form.reason]"
            :name="form.reason + '[reason]'"
            class="textarea textarea-bordered w-full"
            rows="3"
            required
            :disabled="!enabled(form.action)"
          ></textarea>
          <button
            :id="form.action"
            type="submit"
            class="btn btn-sm mt-3"
            :class="form.action === 'approve-plan' ? 'btn-primary' : ''"
            :disabled="!enabled(form.action) || !reasons[form.reason].trim()"
          >
            {{ form.title }}
          </button>
        </form>
      </div>
      <div class="mt-6 border-t border-base-300 pt-4">
        <p class="mb-3 text-sm">
          Execution reserves selected opportunities only. Locked entries remain existing
          commitments. Provider readiness and expiry are rechecked by the server.
        </p>
        <button
          id="execute-plan"
          type="button"
          class="btn btn-primary btn-sm"
          :disabled="!enabled('execute-plan')"
          @click="execute('execute-plan')"
        >
          Execute approved version
        </button>
      </div>
    </CadencePanel>
    <CadencePanel header-class="" id="plan-opportunities" class="mb-5">
      <h2 class="mb-3 text-lg font-semibold">Opportunity evidence</h2>
      <p v-if="!d.opportunities.entries.length" id="plan-opportunities-empty">
        No opportunities on this page.
      </p>
      <article
        v-for="o in d.opportunities.entries"
        :id="'plan-opportunity-' + encodeURIComponent(o.id)"
        :key="o.id"
        class="border-b border-base-300 py-4 last:border-0"
      >
        <div class="flex flex-wrap items-center justify-between gap-2">
          <h3 class="font-semibold">{{ o.provider }} · {{ o.station }}</h3>
          <span
            class="font-mono text-xs uppercase"
            :class="o.disposition === 'selected' ? 'text-primary' : 'text-base-content/65'"
            >{{ o.disposition === "locked" ? "Existing commitment" : o.disposition }}</span
          >
        </div>
        <p class="mt-2 text-sm">{{ o.starts_at }} → {{ o.ends_at }} · expires {{ o.expires_at }}</p>
        <p class="mt-2 text-sm">
          {{ o.eligible ? "Eligible when captured" : "Ineligible when captured" }} ·
          {{ o.availability }} <span v-if="o.synthetic">· Synthetic evidence</span>
        </p>
        <p class="mt-2 break-all text-xs">
          {{ o.route_key }} · Provider {{ o.provider_id }} v{{ o.provider_version }} · Transport
          {{ o.transport_id }} v{{ o.transport_version }}
        </p>
        <a
          :href="requirementHref(d.context.mission_id, o.requirement_id, o.requirement_version)"
          class="mt-2 inline-block text-sm text-primary underline"
          >Review requirement v{{ o.requirement_version }}</a
        >
        <details class="mt-2 text-xs">
          <summary>Immutable evidence identity</summary>
          <p class="break-all font-mono">{{ o.id }}<br />{{ o.content_sha256 }}</p>
        </details>
      </article>
      <PlanReviewPagination
        :detail="d"
        page-key="opportunities_page"
        :page="d.opportunities.page"
        :more="d.opportunities.more"
        :disabled="pending"
      />
    </CadencePanel>
    <div class="grid gap-5 xl:grid-cols-2">
      <CadencePanel header-class="" id="plan-requirements"
        ><h2 class="mb-3 text-lg font-semibold">Requirement coverage</h2>
        <p v-if="!d.requirements.entries.length">No requirements on this page.</p>
        <article
          v-for="r in d.requirements.entries"
          :key="r.id + '@' + r.version"
          class="border-b border-base-300 py-3"
        >
          <a
            :href="requirementHref(d.context.mission_id, r.id, r.version)"
            class="break-all text-primary underline"
            >{{ r.id }} · v{{ r.version }}</a
          >
          <p class="mt-2 text-sm">
            {{ r.satisfied ? "Satisfied" : "Unsatisfied" }} · {{ r.eligible_count }} eligible of
            {{ r.selected_count }} commitments · {{ r.approval_mode }} approval
          </p>
          <p class="text-sm">
            {{ r.hard_failure_count }} unmet conditions · {{ r.search_failure_count }} unavailable
            searches
          </p>
        </article>
        <PlanReviewPagination
          :detail="d"
          page-key="requirements_page"
          :page="d.requirements.page"
          :more="d.requirements.more"
          :disabled="pending"
      /></CadencePanel>
      <CadencePanel header-class="" id="plan-issues"
        ><h2 class="mb-3 text-lg font-semibold">Review findings</h2>
        <p v-if="!d.issues.entries.length" id="plan-issues-empty">No findings on this page.</p>
        <article
          v-for="issue in d.issues.entries"
          :key="issue.id"
          class="border-b border-base-300 py-3"
        >
          <p>{{ issue.message }}</p>
          <p class="text-xs font-mono">{{ issue.code }}</p>
          <a
            v-if="issue.requirement_id && issue.requirement_version"
            :href="
              requirementHref(d.context.mission_id, issue.requirement_id, issue.requirement_version)
            "
            class="text-sm text-primary underline"
            >Review requirement</a
          >
          <p v-for="id in issue.snapshot_ids" :key="id" class="break-all text-xs font-mono">
            {{ id }}
          </p>
        </article>
        <PlanReviewPagination
          :detail="d"
          page-key="issues_page"
          :page="d.issues.page"
          :more="d.issues.more"
          :disabled="pending"
      /></CadencePanel>
      <CadencePanel header-class="" id="plan-execution"
        ><h2 class="mb-3 text-lg font-semibold">Execution of v{{ d.plan.version }}</h2>
        <p v-if="!d.execution.entries.length" id="plan-execution-empty">
          No execution items for this version on this page.
        </p>
        <article v-for="e in d.execution.entries" :key="e.id" class="border-b border-base-300 py-3">
          <p>{{ label(e.state) }} · {{ e.attempts }} attempts</p>
          <p class="break-all text-xs font-mono">{{ e.snapshot_id }}</p>
          <a
            v-if="e.reservation_id"
            :href="`/missions/${encodeURIComponent(d.context.mission_id)}/ops/contacts/${encodeURIComponent(e.reservation_id)}`"
            class="text-sm text-primary underline"
            >Review reservation</a
          >
        </article>
        <PlanReviewPagination
          :detail="d"
          page-key="execution_page"
          :page="d.execution.page"
          :more="d.execution.more"
          :disabled="pending"
      /></CadencePanel>
      <CadencePanel header-class="" id="plan-approvals"
        ><h2 class="mb-3 text-lg font-semibold">Decision history</h2>
        <p v-if="!d.approvals.entries.length" id="plan-approvals-empty">
          No decisions through this version on this page.
        </p>
        <article v-for="a in d.approvals.entries" :key="a.id" class="border-b border-base-300 py-3">
          <a :href="reviewHref(d, a.version)" class="text-primary underline"
            >v{{ a.version }} · {{ a.decision }}</a
          >
          <p class="whitespace-pre-wrap text-sm">{{ a.reason }}</p>
          <p class="text-xs">{{ a.actor_kind }} {{ a.actor_id }} · {{ a.decided_at }}</p>
          <p class="break-all text-xs font-mono">{{ a.content_sha256 }}</p>
        </article>
        <PlanReviewPagination
          :detail="d"
          page-key="approvals_page"
          :page="d.approvals.page"
          :more="d.approvals.more"
          :disabled="pending"
      /></CadencePanel>
      <CadencePanel header-class="" id="plan-versions"
        ><h2 class="mb-3 text-lg font-semibold">Version history</h2>
        <article v-for="v in d.versions.entries" :key="v.id" class="border-b border-base-300 py-3">
          <a :href="reviewHref(d, v.version)" class="text-primary underline"
            >Review v{{ v.version }}</a
          >
          <p class="text-xs">{{ v.created_at }}</p>
          <p class="break-all text-xs font-mono">{{ v.content_sha256 }}</p>
        </article>
        <PlanReviewPagination
          :detail="d"
          page-key="versions_page"
          :page="d.versions.page"
          :more="d.versions.more"
          :disabled="pending"
      /></CadencePanel>
    </div>
  </CadenceOpsViewport>
  <section
    v-else
    id="plan-detail-unavailable"
    role="status"
    class="border border-warning/40 bg-warning/5 p-5"
  >
    <h2 class="font-semibold">Plan review unavailable</h2>
    <p>The plan evidence could not be verified.</p>
    <button
      v-if="connected"
      id="retry-plan-review"
      type="button"
      class="btn btn-sm mt-3"
      :disabled="pending"
      @click="refresh"
    >
      Retry read
    </button>
  </section>
</template>
