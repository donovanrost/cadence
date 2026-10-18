export type JourneyStep = {
  number: string;
  label: string;
  detail: string;
  active: boolean;
};

export type Page = {
  id: string;
  header: {
    eyebrow: string;
    title: string;
    description: string;
    create_action: {
      id: string;
      label: string;
      href: string;
    };
  };
  journey_steps: JourneyStep[];
  empty_state: {
    id: string;
    title: string;
    description: string;
  };
  list_id: string;
};

export type PriorityTone = "error" | "warning" | "neutral";

export type ContactRequirementRow = {
  id: string;
  __dom_id: string;
  priority: {
    label: string;
    tone: PriorityTone;
    class: string;
  };
  version_direction: string;
  intent_label: string;
  outcome_detail: string;
  window: {
    label: string;
    detail: string;
  };
  lifecycle: {
    label: string;
    detail: string;
  };
  detail_href: string;
};

export type OpsContactRequirementListProps = {
  contract_version: 1;
  context: { organization_id: string; mission_id: string };
  query: { page: number; state: "all" | "active" | "closed" | "canceled" };
  filters: { id: string; label: string; href: string; active: boolean }[];
  pagination: { label: string; previous_href: string | null; next_href: string | null };
  page: Page;
  requirements: ContactRequirementRow[];
};
