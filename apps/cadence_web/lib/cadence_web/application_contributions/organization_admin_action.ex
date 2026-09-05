defmodule CadenceWeb.ApplicationContributions.OrganizationAdminAction do
  @moduledoc "Stable Phoenix-owned action contracts for the organization admin remote."

  @action_contracts [
    %{
      id: "validate_provider_account",
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
      effect: :none,
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
      effect: :durable,
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
  @spec validate() :: :ok | {:error, :invalid_action_contracts}
  def validate do
    valid? =
      Enum.all?(@action_contracts, fn contract ->
        is_binary(contract.id) and is_binary(contract.surface_id) and
          contract.version > 0 and contract.effect in [:none, :durable] and
          is_boolean(contract.host_owned?)
      end)

    if valid?, do: :ok, else: {:error, :invalid_action_contracts}
  end
end
