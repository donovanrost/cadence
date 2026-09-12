import { identifier, integer, invalid, record, text } from "../../shared/read-validation";
import { array, id, object, oneOf, string, unique } from "../../shared/form-validation";
import type { ProviderAccountDirectory } from "./list.contracts";

const card = object({
  id,
  __dom_id: id,
  provider_account_id: identifier,
  display_name: string,
  status: oneOf(["info", "ready", "attention", "blocked"]),
  status_label: string,
  provider: string,
  config: string,
  credential: string,
  events: string,
  endpoint: string,
  href: string,
});
export function readAccountDirectory(
  value: unknown,
  organizationId: string,
  version = 1,
): ProviderAccountDirectory {
  if (version !== 1) invalid();
  const input = record(value);
  const organization_id = identifier(input.organization_id);
  if (organization_id !== identifier(organizationId)) invalid();
  const provider_accounts = array(card, 1000)(input.provider_accounts);
  const count = integer(input.count, 0, 1000);
  if (count !== provider_accounts.length) invalid();
  unique(provider_accounts.map((item) => item.provider_account_id));
  unique(provider_accounts.map((item) => item.__dom_id));
  for (const item of provider_accounts) {
    const expectedId = "provider-account-" + item.provider_account_id;
    if (
      item.id !== expectedId ||
      item.__dom_id !== expectedId ||
      item.href !== "/provider-accounts/" + encodeURIComponent(item.provider_account_id) ||
      !/^v[1-9]\d*$/.test(item.config)
    )
      invalid();
    text(item.display_name);
  }
  return { organization_id, count, provider_accounts };
}
