// Feature-owned event bindings. Authorization and effects remain in Phoenix.
export const providerAccountActions = Object.freeze({
  provider_accounts: Object.freeze({}),
  provider_account_new: Object.freeze({
    validate: "validate_provider_account_form",
    save: "register_provider_account",
  }),
  provider_account_show: Object.freeze({
    "validate-account": "validate_provider_account",
    "rotate-credential": "rotate_provider_credential",
    "revoke-credential": "revoke_provider_credential",
    "grant-mission": "grant_provider_account_mission",
    "revoke-grant": "revoke_provider_account_mission",
  }),
});
