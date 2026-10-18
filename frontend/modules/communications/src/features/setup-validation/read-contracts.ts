export type Finding = {
  id: string | null;
  title: string;
  body: string;
  action_label: string | null;
  action_href: string | null;
  status: { tone: "blocked" | "attention"; label: string };
};
export type FindingGroup = { id: string; title: string; description: string; findings: Finding[] };
