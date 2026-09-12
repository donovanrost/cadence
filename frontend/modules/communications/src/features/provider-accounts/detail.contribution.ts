import type { OrganizationPageContribution } from "@cadence/plugin-sdk/organization-pages";
import { boolean } from "../../shared/form-validation";
import { identifier, integer, record } from "../../shared/read-validation";
import { readAccountDetail } from "./detail.validation";
import { providerAccountActions } from "./actions";
import ProviderAccountDetailPage from "./ProviderAccountDetailPage.vue";

export const providerAccountDetailContribution: OrganizationPageContribution<
  typeof ProviderAccountDetailPage
> = {
  id: "comms.provider-account-detail",
  slot: "organization.page",
  version: 1,
  title: "Provider account",
  // oxlint-disable-next-line typescript/no-unsafe-assignment -- vue-tsc checks the SFC constructor at this registration or render boundary.
  component: ProviderAccountDetailPage,
  actions: [...Object.keys(providerAccountActions.provider_account_show), "refresh"],
  read(value, context) {
    const data = record(value);
    return {
      model: readAccountDetail(
        data.model,
        context.organizationId,
        1,
        identifier(context.resourceId),
      ),
      sequence: integer(data.sequence, 0, 1_000_000),
      locked: boolean(data.locked),
    };
  },
};
