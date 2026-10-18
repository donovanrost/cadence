<script setup lang="ts">
import CadenceButton from "@cadence/ui/CadenceButton.vue";
import CadenceLink from "@cadence/ui/CadenceLink.vue";
import CadenceTableFrame from "@cadence/ui/CadenceTableFrame.vue";
import type { ConfigurationDocument, ConfigurationSnapshot } from "./contracts";
import { configurationChanges, type SetupIssue } from "./presentation";
import { computed, ref, watch } from "vue";
const props = defineProps<{
  snapshot: ConfigurationSnapshot;
  draft: ConfigurationDocument;
  unsaved: boolean;
  issues: readonly SetupIssue[];
  busy: boolean;
  conflict: boolean;
  feedback: string | null;
}>();
defineEmits<{ review: []; decide: [reason: string, decision: "approved" | "rejected"] }>();
const reason = ref("");
const actionArea = ref<HTMLElement | null>(null);
watch(
  () => props.feedback,
  (feedback) => {
    if (feedback) actionArea.value?.scrollIntoView({ block: "nearest" });
  },
  { flush: "post" },
);
watch(
  [
    () => props.snapshot.token,
    () => props.snapshot.review?.id,
    () => props.snapshot.approval.token,
  ],
  () => {
    reason.value = "";
  },
);
const currentReview = computed(() =>
  !props.unsaved && props.snapshot.review?.version === props.snapshot.saved_version
    ? props.snapshot.review
    : null,
);
const pendingReview = computed(() => currentReview.value?.state === "approval_pending");
const selfReview = computed(
  () => props.snapshot.review?.requester_id === props.snapshot.approval.actor_id,
);
const changes = computed(() => configurationChanges(props.snapshot, props.draft));
const activeRevision = computed(
  () => currentReview.value?.state === "active" && !changes.value.length,
);
const catalog = computed(() =>
  props.snapshot.catalogs.find((item) => item.id === props.draft.catalog_revision_id),
);
const reviewText = computed(() => {
  const review = currentReview.value;
  return review
    ? {
        approval_pending: "Awaiting review",
        approved: "Approval recorded · check runtime status",
        rejected: "Review rejected",
        stale: "Review needs updating",
        active: "Configuration activated",
      }[review.state]
    : props.snapshot.approval.requirement === "direct"
      ? "Review & activate"
      : "Prepare for review";
});
</script>
<template>
  <div class="scw-stack">
    <div class="scw-section-heading">
      <div>
        <p class="scw-eyebrow">REVIEW & ACTIVATION</p>
        <h2>Configuration changes</h2>
        <p class="scw-muted">
          Compare the draft with the settings currently serving {{ snapshot.name }}.
        </p>
      </div>
      <span class="scw-tag">{{
        snapshot.saved_version ? `Saved r${snapshot.saved_version}` : "No saved draft"
      }}</span>
    </div>
    <div v-if="unsaved || conflict" class="scw-notice">
      <strong>{{ conflict ? "Resolve competing changes" : "Save before review" }}</strong>
      <p>
        {{
          conflict
            ? "The saved configuration changed. Compare it with your edits before submitting."
            : "The comparison includes your unsaved edits. Save the draft to create an exact revision for review."
        }}
      </p>
    </div>
    <section v-if="issues.length" class="scw-surface">
      <header class="scw-block-heading">
        <h3>Before submitting</h3>
        <span class="scw-count">{{ issues.length }}</span>
      </header>
      <div class="scw-task-list">
        <a
          v-for="issue in issues"
          :key="issue.id"
          class="scw-task"
          :href="`${snapshot.base_href}?section=${issue.section}`"
          ><span class="hero-exclamation-circle scw-icon" aria-hidden="true" /><span
            ><strong>{{ issue.label }}</strong
            ><span>{{ issue.detail }}</span></span
          ><span class="hero-arrow-up-right scw-icon" aria-hidden="true"
        /></a>
      </div>
    </section>
    <CadenceTableFrame v-if="changes.length" id="spacecraft-change-comparison" class="table-sm"
      ><caption class="sr-only">
        Active and proposed spacecraft configuration
      </caption>
      <thead>
        <tr>
          <th scope="col">Setting</th>
          <th scope="col">Active</th>
          <th scope="col">Draft</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="change in changes" :key="change.label">
          <th scope="row">
            {{ change.label }}<span class="scw-table-detail">{{ change.impact }}</span>
          </th>
          <td>{{ change.before }}</td>
          <td>{{ change.after }}</td>
        </tr>
      </tbody></CadenceTableFrame
    >
    <p v-else class="scw-empty">The draft matches the active configuration.</p>
    <section id="spacecraft-configuration-review" class="scw-surface">
      <header class="scw-block-heading">
        <h3>{{ reviewText }}</h3>
        <span v-if="currentReview" class="scw-muted">r{{ currentReview.version }}</span>
      </header>
      <div class="scw-block-body scw-stack">
        <p v-if="activeRevision">This saved revision is active on {{ snapshot.name }}.</p>
        <p v-else-if="currentReview?.state === 'approved'">
          Approval has been recorded. Check runtime status before trying to activate this revision
          again.
        </p>
        <p v-else>
          {{
            snapshot.approval.requirement === "direct"
              ? "One authorized operator can review and activate this exact saved configuration."
              : "A different authorized person must approve this exact saved configuration before activation."
          }}
        </p>
        <p class="scw-muted">
          {{
            {
              organization: "Organization default",
              inherited: "Inherited from organization",
              overridden: "Mission override",
              enforced: "Required by organization",
            }[snapshot.approval.source]
          }}
          · <CadenceLink :href="snapshot.links.settings">Approval settings</CadenceLink>
        </p>
        <p v-if="pendingReview && selfReview" role="status">
          Waiting for another person to review. Share this spacecraft’s Changes page with a
          teammate.
        </p>
        <form
          v-if="pendingReview && !selfReview && snapshot.approval.can_review"
          id="spacecraft-review-decision"
          class="scw-stack"
          @submit.prevent="$emit('decide', reason, 'approved')"
        >
          <label for="spacecraft-review-reason">Review rationale</label>
          <textarea
            id="spacecraft-review-reason"
            v-model="reason"
            class="textarea textarea-bordered"
            required
            maxlength="4096"
            :disabled="busy || unsaved || conflict"
            placeholder="Record why this configuration is ready, or what needs to change."
          />
          <div class="scw-actions">
            <CadenceButton
              type="submit"
              size="sm"
              variant="primary"
              :disabled="busy || unsaved || conflict || !reason.trim()"
              >Approve & activate</CadenceButton
            >
            <CadenceButton
              size="sm"
              variant="danger"
              :disabled="busy || unsaved || conflict || !reason.trim()"
              @click="$emit('decide', reason, 'rejected')"
              >Reject</CadenceButton
            >
          </div>
        </form>
        <div ref="actionArea" class="scw-stack">
          <p v-if="feedback" id="spacecraft-activation-feedback" class="scw-feedback" role="status">
            {{ feedback }}
          </p>
          <div class="scw-actions">
            <CadenceButton
              v-if="!pendingReview && !activeRevision"
              :id="
                snapshot.approval.requirement === 'direct'
                  ? 'spacecraft-activate'
                  : 'spacecraft-submit-review'
              "
              size="sm"
              variant="primary"
              :loading="busy"
              :disabled="
                busy ||
                !snapshot.approval.can_request ||
                conflict ||
                unsaved ||
                issues.length > 0 ||
                !snapshot.saved_version ||
                !changes.length ||
                snapshot.review?.state === 'approval_pending'
              "
              @click="$emit('review')"
              >{{
                busy
                  ? snapshot.approval.requirement === "direct"
                    ? "Activating configuration…"
                    : "Submitting for review…"
                  : snapshot.approval.requirement === "direct"
                    ? "Activate configuration"
                    : "Submit for review"
              }}</CadenceButton
            ><CadenceLink v-if="pendingReview" :href="snapshot.links.approvals"
              >Open review inbox</CadenceLink
            ><CadenceLink v-if="catalog" :href="catalog.href">View catalog</CadenceLink>
          </div>
        </div>
      </div>
    </section>
  </div>
</template>
