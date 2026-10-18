export type ProviderAccountCard = {
  id: string;
  display_name: string;
  provider_account_id: string;
  status: "info" | "ready" | "attention" | "blocked";
  status_label: string;
  provider: string;
  config: string;
  credential: string;
  events: string;
  endpoint: string;
  href: string;
};
