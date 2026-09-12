export type TransportRow = {
  id: string;
  display_name: string;
  href: string;
  origin: string;
  transport_kind: string;
  direction_capability: string;
  version: number;
};
export type TransportDetails = {
  id: string;
  display_name: string;
  href: string;
  list_href: string;
  version: number;
  lifecycle_state: string;
  origin: string;
  transport_kind: string;
  direction_capability: string;
  provider_managed: boolean;
};
