export type Page = {
  id: string;
  heading: string;
  subtitle: string;
  list: {
    card_id: string;
    id: string;
    empty: {
      id: string;
      copy: string;
    };
  };
};

export type SelectedRequest = {
  activation_request_id: string;
  binding_set_id: string;
  binding_set_version: number;
};

export type FormField = {
  id: string;
  name: string;
  type: "hidden" | "textarea";
  value: string;
};

export type DecisionAction = {
  id: string;
  name: string;
  value: "approved" | "rejected";
  label: string;
};

export type DecisionForm = {
  panel_id: string;
  id: string;
  request_id: FormField;
  reason: FormField & {
    label: string;
    required: boolean;
  };
  actions: {
    reject: DecisionAction;
    approve: DecisionAction;
  };
};

export type ActivationRequest = {
  __dom_id: string;
  activation_request_id: string;
  binding_set_id: string;
  binding_set_version: number;
  status: {
    label: string;
  };
  requester_display: string;
  review: {
    id: string;
    label: string;
  };
};

export type Decision = "approved" | "rejected";

export type InboxData = {
  page: Page;
  selected: SelectedRequest | null;
  form: DecisionForm;
  activation_requests: ActivationRequest[];
};
export type DecisionInput = {
  activation_decision: { request_id: string; reason: string };
  decision: Decision;
};
export type ReviewContext = { organization_id: string; mission_id: string };
export type InboxSnapshot = {
  version: 1;
  status: "ready";
  context: ReviewContext;
  token: string;
  data: InboxData;
};
export type DecisionResult =
  | {
      status: "ok";
      data: {
        activationRequestId: string;
        decision: Decision;
        outcome: "applied" | "rejected" | "application_needs_review";
      };
    }
  | { status: "invalid"; message: string }
  | { status: "unavailable" };
