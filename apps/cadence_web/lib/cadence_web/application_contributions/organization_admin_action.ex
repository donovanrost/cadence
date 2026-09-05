defmodule CadenceWeb.ApplicationContributions.OrganizationAdminAction do
  @moduledoc "Stable Phoenix-owned action contracts for the organization admin remote."

  alias Cadence.Applications.{ActionFailure, ActionRequest, HostContext}
  alias Cadence.Auth.Scope
  alias CadenceWeb.ApplicationContributions.OrganizationAdminProviders, as: Providers

  @action_contracts [
    %{
      id: "validate_provider_account_form",
      version: 1,
      surface_id: "provider_account_new",
      effect: :none,
      host_owned?: false
    },
    %{
      id: "register_provider_account",
      version: 1,
      surface_id: "provider_account_new",
      effect: :durable,
      host_owned?: false
    },
    %{
      id: "validate_provider_account",
      version: 1,
      surface_id: "provider_account_show",
      effect: :external,
      host_owned?: false
    },
    %{
      id: "rotate_provider_credential",
      version: 1,
      surface_id: "provider_account_show",
      effect: :durable,
      host_owned?: false
    },
    %{
      id: "revoke_provider_credential",
      version: 1,
      surface_id: "provider_account_show",
      effect: :durable,
      host_owned?: false
    },
    %{
      id: "grant_provider_account_mission",
      version: 1,
      surface_id: "provider_account_show",
      effect: :durable,
      host_owned?: false
    },
    %{
      id: "revoke_provider_account_mission",
      version: 1,
      surface_id: "provider_account_show",
      effect: :durable,
      host_owned?: false
    },
    %{
      id: "accept_invitation",
      version: 1,
      surface_id: "notifications",
      effect: :durable,
      host_owned?: true
    },
    %{
      id: "mark_notification_read",
      version: 1,
      surface_id: "notifications",
      effect: :durable,
      host_owned?: false
    },
    %{
      id: "mark_notification_read",
      version: 1,
      surface_id: "notifications_bell",
      effect: :durable,
      host_owned?: false
    },
    %{
      id: "refresh_runtime",
      version: 1,
      surface_id: "admin_runtime",
      effect: :none,
      host_owned?: false
    },
    %{
      id: "filter_runtime_decisions",
      version: 1,
      surface_id: "admin_runtime",
      effect: :none,
      host_owned?: false
    },
    %{
      id: "validate_organization",
      version: 1,
      surface_id: "admin_organization_new",
      effect: :none,
      host_owned?: false
    },
    %{
      id: "create_organization",
      version: 1,
      surface_id: "admin_organization_new",
      effect: :durable,
      host_owned?: false
    },
    %{
      id: "issue_service_identity",
      version: 1,
      surface_id: "admin_organization_show",
      effect: :durable,
      host_owned?: false
    },
    %{
      id: "dismiss_service_token",
      version: 1,
      surface_id: "admin_organization_show",
      effect: :none,
      host_owned?: false
    },
    %{
      id: "open_organization",
      version: 1,
      surface_id: "admin_organization_show",
      effect: :external,
      host_owned?: true
    },
    %{
      id: "validate_invitation",
      version: 1,
      surface_id: "admin_organization_invite",
      effect: :none,
      host_owned?: false
    },
    %{
      id: "invite_organization_member",
      version: 1,
      surface_id: "admin_organization_invite",
      effect: :durable,
      host_owned?: false
    }
  ]

  @doc "Returns all action contracts, including surface-local overloads."
  @spec all() :: [map()]
  def all, do: @action_contracts

  @doc "Validates a complete provider-owned surface/action binding ledger."
  @spec validate_bindings([map()]) :: :ok | {:error, atom()}
  def validate_bindings(action_contracts) when is_list(action_contracts) do
    if Enum.all?(action_contracts, &valid_action_contract?/1) do
      identities = Enum.map(action_contracts, &{&1.surface_id, &1.version, &1.id})

      if length(identities) == length(Enum.uniq(identities)),
        do: :ok,
        else: {:error, :duplicate_action_bindings}
    else
      {:error, :invalid_action_contracts}
    end
  end

  def validate_bindings(_action_contracts), do: {:error, :invalid_action_contracts}

  @doc false
  @spec application_key() :: binary()
  def application_key, do: "organization_admin"

  @doc "Executes an authenticated organization, user, or platform-admin action."
  @spec execute(Scope.t(), HostContext.t(), ActionRequest.t()) ::
          {:ok, term()} | {:error, ActionFailure.t() | term()}
  def execute(
        %Scope{} = scope,
        %HostContext{} = host_context,
        %ActionRequest{application_key: "organization_admin", application_version: 1} = request
      ) do
    with :ok <- ensure_surface_binding(request),
         :ok <- ensure_action_context(scope, host_context, request.action_id),
         {:ok, result} <- execute_action(scope, host_context, request) do
      {:ok, result}
    end
  end

  def execute(_scope, _host_context, _request),
    do: {:error, failure("invalid_action", "The organization action request is invalid.")}

  defp execute_action(_scope, _host_context, %ActionRequest{action_id: "open_organization"}),
    do: {:error, failure("host_owned_action", "Organization switching remains Phoenix-owned.")}

  defp execute_action(_scope, _host_context, %ActionRequest{action_id: "dismiss_service_token"}),
    do: {:ok, %{patch: %{issued_service_token: nil}}}

  defp execute_action(_scope, _host_context, %ActionRequest{
         action_id: "validate_provider_account_form",
         params: params
       }) do
    values = input_map(params, "provider_account")
    {:ok, %{patch: %{form: Providers.ProviderAccountNew.form(values)}}}
  end

  defp execute_action(scope, _host_context, %ActionRequest{
         action_id: "register_provider_account",
         params: params
       }) do
    with {:ok, values} <- required_input_map(params, "provider_account"),
         {:ok, result} <- Providers.ProviderAccountNew.create(scope, values) do
      {:ok, result}
    end
  end

  defp execute_action(scope, _host_context, %ActionRequest{
         action_id: "validate_provider_account",
         params: params
       }) do
    with {:ok, provider_account_id} <- required_param(params, "provider_account_id"),
         {:ok, _account} <-
           Cadence.GroundNetworks.ProviderAccounts.validate(scope, provider_account_id),
         {:ok, props} <- Providers.ProviderAccountShow.props(scope, provider_account_id) do
      {:ok, %{patch: props}}
    end
  end

  defp execute_action(scope, _host_context, %ActionRequest{action_id: action_id, params: params})
       when action_id in [
              "rotate_provider_credential",
              "revoke_provider_credential",
              "grant_provider_account_mission",
              "revoke_provider_account_mission"
            ] do
    with {:ok, provider_account_id} <- required_param(params, "provider_account_id"),
         {:ok, _result} <- provider_account_action(scope, action_id, provider_account_id, params),
         {:ok, props} <- Providers.ProviderAccountShow.props(scope, provider_account_id) do
      {:ok, %{patch: props}}
    end
  end

  defp execute_action(scope, _host_context, %ActionRequest{
         action_id: "accept_invitation",
         params: params
       }) do
    with {:ok, notification_id} <- required_param(params, "notification_id"),
         {:ok, notification} <- Cadence.Notifications.fetch_notification(notification_id),
         true <- notification.user_id == scope.user.user_id,
         :organization_invitation <- notification.kind,
         {:ok, invitation_id} <-
           required_map_param(notification.metadata, "organization_invitation_id"),
         {:ok, _result} <-
           Cadence.Accounts.accept_invitation_as_user(scope.user.user_id, invitation_id) do
      {:ok, %{navigate: "/"}}
    else
      false ->
        {:error, failure("forbidden", "That notification is not available to this user.")}

      {:error, reason} ->
        {:error, reason}

      _other ->
        {:error, failure("invalid_invitation", "That invitation is no longer available.")}
    end
  end

  defp execute_action(scope, _host_context, %ActionRequest{
         action_id: "mark_notification_read",
         params: params
       }) do
    with {:ok, notification_id} <- required_param(params, "notification_id"),
         {:ok, notification} <- Cadence.Notifications.fetch_notification(notification_id),
         true <- notification.user_id == scope.user.user_id,
         {:ok, _updated} <-
           Cadence.Notifications.mark_notification_read(notification_id, scope.user.user_id) do
      {:ok, %{patch: %{presentation: Providers.Notifications.presentation(scope)}}}
    else
      false -> {:error, failure("forbidden", "That notification is not available to this user.")}
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute_action(_scope, _host_context, %ActionRequest{
         action_id: "refresh_runtime",
         params: params
       }),
       do: {:ok, %{patch: Providers.AdminRuntime.props(params)}}

  defp execute_action(_scope, _host_context, %ActionRequest{
         action_id: "filter_runtime_decisions",
         params: params
       }),
       do:
         {:ok,
          %{
            patch: Providers.AdminRuntime.props(input_map(params, "runtime_decision_filters"))
          }}

  defp execute_action(_scope, _host_context, %ActionRequest{
         action_id: "validate_organization",
         params: params
       }),
       do:
         {:ok,
          %{
            patch: %{
              form: Providers.AdminOrganizationNew.form(input_map(params, "organization"))
            }
          }}

  defp execute_action(_scope, _host_context, %ActionRequest{
         action_id: "create_organization",
         params: params
       }) do
    values = input_map(params, "organization")
    display_name = normalize_text(value(values, "display_name"))
    slug = normalize_text(value(values, "slug"))

    if is_binary(display_name) and is_binary(slug) do
      case Providers.AdminOrganizationNew.create(%{
             "display_name" => display_name,
             "slug" => slug
           }) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, failure("invalid_organization", "Display name and slug are required.")}
    end
  end

  defp execute_action(_scope, _host_context, %ActionRequest{
         action_id: "issue_service_identity",
         params: params
       }) do
    with {:ok, organization_id} <- required_param(params, "organization_id"),
         {:ok, result} <-
           Providers.AdminOrganizationShow.issue_service_identity(
             organization_id,
             input_map(params, "service_identity")
           ) do
      {:ok, %{patch: result}}
    end
  end

  defp execute_action(_scope, _host_context, %ActionRequest{
         action_id: "validate_invitation",
         params: params
       }),
       do:
         {:ok,
          %{
            patch: %{
              form: Providers.AdminOrganizationInvite.form(input_map(params, "invite"))
            }
          }}

  defp execute_action(scope, _host_context, %ActionRequest{
         action_id: "invite_organization_member",
         params: params
       }) do
    with {:ok, organization_id} <- required_param(params, "organization_id"),
         {:ok, values} <- required_input_map(params, "invite"),
         {:ok, result} <- Providers.AdminOrganizationInvite.create(scope, organization_id, values) do
      {:ok, result}
    end
  end

  defp execute_action(_scope, _host_context, _request),
    do: {:error, failure("unsupported_action", "The organization action is not implemented.")}

  defp ensure_surface_binding(%ActionRequest{} = request),
    do: Cadence.Applications.ActionContractLedger.admit(request, __MODULE__)

  defp provider_account_action(scope, "rotate_provider_credential", account_id, _params) do
    with {:ok, _account, version} <-
           Cadence.GroundNetworks.ProviderAccounts.fetch(scope, account_id),
         {:ok, _result} <-
           Cadence.GroundNetworks.ProviderCredentials.rotate(
             scope,
             account_id,
             version.credential_ref,
             provider_account_opts()
           ) do
      {:ok, %{completed: true}}
    end
  end

  defp provider_account_action(scope, "revoke_provider_credential", account_id, _params) do
    with {:ok, _account, version} <-
           Cadence.GroundNetworks.ProviderAccounts.fetch(scope, account_id),
         {:ok, _result} <-
           Cadence.GroundNetworks.ProviderCredentials.revoke(
             scope,
             account_id,
             version.credential_ref,
             provider_account_opts()
           ) do
      {:ok, %{completed: true}}
    end
  end

  defp provider_account_action(scope, "grant_provider_account_mission", account_id, params) do
    grant = input_map(params, "grant")

    with {:ok, mission_id} <- required_param(grant, "mission_id") do
      Cadence.GroundNetworks.ProviderAccountGrants.grant(
        scope,
        mission_id,
        account_id,
        %{
          restrictions: grant_restrictions(grant),
          grant_reason: optional_text(value(grant, "grant_reason"))
        }
      )
    end
  end

  defp provider_account_action(scope, "revoke_provider_account_mission", _account_id, params) do
    with {:ok, grant_id} <- required_param(params, "grant-id") do
      Cadence.Control.Providers.revoke_account_grant(
        scope,
        grant_id,
        "Revoked by organization administrator"
      )
    end
  end

  defp ensure_action_context(
         %Scope{organization_id: organization_id},
         %HostContext{placement: :organization, organization_id: organization_id},
         action_id
       )
       when is_binary(organization_id) do
    if action_id in organization_actions(),
      do: :ok,
      else: {:error, :unsupported_application_action_scope}
  end

  defp ensure_action_context(
         %Scope{actor_kind: :user, user: %{user_id: user_id}},
         %HostContext{placement: :user, user_id: user_id},
         action_id
       ) do
    if action_id in user_actions(), do: :ok, else: {:error, :unsupported_application_action_scope}
  end

  defp ensure_action_context(%Scope{} = scope, %HostContext{placement: :admin}, action_id) do
    if Scope.admin_mode?(scope) and action_id in admin_actions(),
      do: :ok,
      else: {:error, :forbidden}
  end

  defp ensure_action_context(_scope, _host_context, _action_id), do: {:error, :scope_mismatch}

  defp organization_actions do
    [
      "validate_provider_account_form",
      "register_provider_account",
      "validate_provider_account",
      "rotate_provider_credential",
      "revoke_provider_credential",
      "grant_provider_account_mission",
      "revoke_provider_account_mission"
    ]
  end

  defp user_actions, do: ["accept_invitation", "mark_notification_read"]

  defp admin_actions do
    [
      "refresh_runtime",
      "filter_runtime_decisions",
      "validate_organization",
      "create_organization",
      "issue_service_identity",
      "dismiss_service_token",
      "open_organization",
      "validate_invitation",
      "invite_organization_member"
    ]
  end

  defp provider_account_opts,
    do: Application.get_env(:cadence_web, :provider_account_live_opts, [])

  defp grant_restrictions(params) do
    %{
      "allowed_services" => comma_list(value(params, "allowed_services")),
      "allowed_stations" => comma_list(value(params, "allowed_stations")),
      "max_quota" => nonnegative_integer(value(params, "max_quota"))
    }
    |> Map.reject(fn {_key, value} -> value in [nil, []] end)
  end

  defp comma_list(value) do
    case optional_text(value) do
      nil -> []
      text -> text |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    end
  end

  defp nonnegative_integer(value) do
    case optional_text(value) do
      nil ->
        nil

      text ->
        case Integer.parse(text) do
          {number, ""} when number >= 0 -> number
          _other -> -1
        end
    end
  end

  defp optional_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end

  defp optional_text(_value), do: nil

  defp required_input_map(params, key) do
    value = input_map(params, key)

    if value == %{},
      do: {:error, failure("invalid_input", "The action input is invalid.")},
      else: {:ok, value}
  end

  defp input_map(params, key) when is_map(params) do
    case value(params, key) do
      map when is_map(map) -> map
      _other -> %{}
    end
  end

  defp input_map(_params, _key), do: %{}

  defp required_param(params, key) do
    case value(params, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, failure("invalid_input", "The action input is invalid.")}
    end
  end

  defp required_map_param(params, key), do: required_param(params, key)

  defp value(params, key) when is_map(params) and is_binary(key) do
    Map.get(params, key) || Map.get(params, atom_key(key))
  end

  defp atom_key("provider_account"), do: :provider_account
  defp atom_key("provider_account_id"), do: :provider_account_id
  defp atom_key("grant"), do: :grant
  defp atom_key("grant-id"), do: :grant_id
  defp atom_key("notification_id"), do: :notification_id
  defp atom_key("organization"), do: :organization
  defp atom_key("organization_id"), do: :organization_id
  defp atom_key("service_identity"), do: :service_identity
  defp atom_key("runtime_decision_filters"), do: :runtime_decision_filters
  defp atom_key("invite"), do: :invite
  defp atom_key("display_name"), do: :display_name
  defp atom_key("slug"), do: :slug
  defp atom_key("mission_id"), do: :mission_id
  defp atom_key("allowed_services"), do: :allowed_services
  defp atom_key("allowed_stations"), do: :allowed_stations
  defp atom_key("max_quota"), do: :max_quota
  defp atom_key("grant_reason"), do: :grant_reason
  defp atom_key("email"), do: :email
  defp atom_key("membership_role"), do: :membership_role
  defp atom_key("grant_platform_admin"), do: :grant_platform_admin
  defp atom_key(_key), do: nil

  defp normalize_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end

  defp normalize_text(_value), do: nil

  defp failure(code, message), do: %ActionFailure{code: code, message: message}

  @doc "Finds an action by its surface and durable action identity."
  @spec fetch(binary(), binary(), pos_integer()) :: {:ok, map()} | {:error, :unknown_action}
  def fetch(surface_id, action_id, version \\ 1)

  def fetch(surface_id, action_id, version)
      when is_binary(surface_id) and is_binary(action_id) and is_integer(version) do
    case Enum.find(
           @action_contracts,
           &(&1.surface_id == surface_id and &1.id == action_id and &1.version == version)
         ) do
      nil -> {:error, :unknown_action}
      contract -> {:ok, contract}
    end
  end

  def fetch(_surface_id, _action_id, _version), do: {:error, :unknown_action}

  @doc "Whether the action crosses a Phoenix/host-owned flow boundary."
  @spec host_owned?(binary(), binary()) :: boolean()
  def host_owned?(surface_id, action_id) do
    case fetch(surface_id, action_id) do
      {:ok, contract} -> contract.host_owned?
      {:error, :unknown_action} -> false
    end
  end

  @doc false
  @spec validate() :: :ok | {:error, atom()}
  def validate do
    validate_bindings(@action_contracts)
  end

  defp valid_action_contract?(contract) when is_map(contract) do
    id = Map.get(contract, :id)
    surface_id = Map.get(contract, :surface_id)
    version = Map.get(contract, :version)
    effect = Map.get(contract, :effect)
    host_owned? = Map.get(contract, :host_owned?)

    is_binary(id) and id != "" and is_binary(surface_id) and surface_id != "" and
      is_integer(version) and version > 0 and effect in [:none, :durable, :external] and
      is_boolean(host_owned?)
  end

  defp valid_action_contract?(_contract), do: false
end
