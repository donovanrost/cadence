export type RoutingRow = {
  id: string;
  display_name: string;
  href: string;
  spacecraft_id: string;
  spacecraft_name: string;
  purpose_label: string;
  direction: string;
  transport_id: string;
  transport_name: string;
  role: string;
  enabled: boolean;
};
export type RoutingDetails = {
  id: string;
  display_name: string;
  href: string;
  list_href: string;
  enabled: boolean;
  lifecycle_state: string;
  spacecraft_id: string;
  spacecraft_name: string;
  purpose_label: string;
  direction: string;
  transport_id: string;
  transport_name: string;
  transport_version: number;
  role: string;
};
