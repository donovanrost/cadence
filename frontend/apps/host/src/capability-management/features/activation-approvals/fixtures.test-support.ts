import type { InboxSnapshot } from "./contracts";
export function inboxFixture(): InboxSnapshot {
  return {
    version: 1,
    status: "ready",
    token: "review-token",
    context: { organization_id: "org-1", mission_id: "mission-1" },
    data: {
      page: {
        id: "activation-approval-inbox",
        heading: "Activation approvals",
        subtitle: "Review governed changes.",
        list: {
          card_id: "activation-approval-list",
          id: "activation-requests",
          empty: { id: "activation-requests-empty", copy: "No requests waiting." },
        },
      },
      selected: null,
      form: {
        panel_id: "activation-decision-panel",
        id: "activation-decision-form",
        request_id: {
          id: "activation_decision_request_id",
          name: "activation_decision[request_id]",
          type: "hidden",
          value: "",
        },
        reason: {
          id: "activation_decision_reason",
          name: "activation_decision[reason]",
          type: "textarea",
          value: "",
          label: "Decision rationale",
          required: true,
        },
        actions: {
          approve: {
            id: "approve-activation-request",
            name: "decision",
            value: "approved",
            label: "Approve and apply",
          },
          reject: {
            id: "reject-activation-request",
            name: "decision",
            value: "rejected",
            label: "Reject",
          },
        },
      },
      activation_requests: [
        {
          __dom_id: "activation-request-request-1",
          activation_request_id: "request-1",
          binding_set_id: "flight-basis",
          binding_set_version: 2,
          status: { label: "Approval pending" },
          requester_display: "Requester",
          review: { id: "review-request-1", label: "Review" },
        },
      ],
    },
  };
}
