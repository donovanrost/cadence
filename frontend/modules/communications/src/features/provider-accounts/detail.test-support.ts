import { required } from "../../../../../test-support/required";
import { detailFixture } from "./provider-accounts.test-support";
import { readAccountDetail } from "./detail.validation";
export function accountDetailFixture() {
  const original = detailFixture();
  const raw = {
    ...original,
    account: {
      organization_id: "org-1",
      provider_account_id: "account-1",
      version: 3,
      credential_ref: "credential-1",
      credential_version: 2,
      credential_status: "active",
    },
    page: {
      ...required(original.page),
      header: {
        ...required(original.page).header,
        subtitle: "account-1",
        config_label: "config v3",
      },
    },
    grant_form: {
      ...required(original.grant_form),
      values: { ...required(original.grant_form).values, mission_id: "mission-2" },
      fields: {
        ...required(original.grant_form).fields,
        mission_id: {
          ...required(original.grant_form).fields.mission_id,
          value: "mission-2",
          options: [{ value: "mission-2", label: "Mission Two", disabled: false }],
        },
      },
    },
    account_grants: required(original.account_grants).map((grant) => ({
      ...grant,
      mission_id: "mission-1",
      version: 2,
      account_version: 3,
      version_label: "grant v2 · account v3",
    })),
  };
  return readAccountDetail(raw, "org-1", 1);
}
