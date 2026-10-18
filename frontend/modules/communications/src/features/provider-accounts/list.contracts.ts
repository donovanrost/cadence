import type { ProviderAccountCard } from "./cards.contracts";

export type ProviderAccountDirectory = {
  organization_id: string;
  count: number;
  provider_accounts: Array<ProviderAccountCard & { __dom_id: string }>;
};
