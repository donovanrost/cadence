defmodule Cadence.Applications.Comms.ActionProvider do
  @moduledoc "Typed action adapter for mission Comms provider operations."

  @behaviour Cadence.Applications.ActionProvider

  alias Cadence.Applications.{ActionRequest, HostContext}
  alias Cadence.Auth.Scope
  alias Cadence.Control.Providers, as: ControlProviders
  alias Cadence.GroundNetworks.{MissionProvider, ProviderAccountGrants, ProviderAccounts}
  alias Cadence.Management.Providers

  @application_key "comms"

  @impl true
  def application_key, do: @application_key

  @impl true
  def execute(
        %Scope{} = scope,
        %HostContext{placement: :mission, mission_id: mission_id},
        %ActionRequest{
          application_key: @application_key,
          application_version: 1,
          action_id: action_id,
          params: params
        }
      )
      when action_id in ["validate_provider", "sync_provider", "archive_provider"] do
    with {:ok, provider_id} <- required_id(params, "provider_id") do
      case action_id do
        "validate_provider" -> ControlProviders.validate_current(scope, mission_id, provider_id)
        "sync_provider" -> ControlProviders.sync_current(scope, mission_id, provider_id)
        "archive_provider" -> Providers.archive_provider(scope, mission_id, provider_id)
      end
    end
  end

  def execute(
        %Scope{} = scope,
        %HostContext{placement: :mission, mission_id: mission_id},
        %ActionRequest{
          application_key: @application_key,
          application_version: 1,
          action_id: "create_provider",
          params: params
        }
      ) do
    create_provider(scope, mission_id, provider_params(params))
  end

  def execute(%Scope{}, %HostContext{}, %ActionRequest{}),
    do: {:error, :unsupported_application_action}

  @impl true
  def result(%MissionProvider{} = provider) do
    %{
      "provider_id" => provider.provider_id,
      "version" => provider.version,
      "display_name" => provider.display_name
    }
  end

  def result(value) when is_map(value), do: value
  def result(value), do: value

  defp create_provider(scope, mission_id, params) do
    with {:ok, grant_id} <- required_id(params, "provider_account_grant_id"),
         {:ok, grant} <-
           ProviderAccountGrants.fetch_active_for_system(scope.organization_id, grant_id),
         true <- grant.mission_id == mission_id,
         {:ok, account_version} <-
           ProviderAccounts.fetch_version(
             scope.organization_id,
             grant.provider_account_id,
             grant.provider_account_version
           ),
         :ok <- immutable_account_id(params, grant.provider_account_id),
         {:ok, display_name} <- required_text(params, "display_name"),
         {:ok, delivery_policy} <- delivery_policy(params) do
      provider =
        MissionProvider.new(%{
          mission_id: mission_id,
          display_name: display_name,
          provider_account_id: account_version.provider_account_id,
          provider_account_version: account_version.version,
          provider_account_grant_id: grant.provider_account_grant_id,
          provider_account_grant_version: grant.version,
          provider_type: account_version.provider_type,
          client_key: account_version.client_key,
          base_url: account_version.base_url,
          credential_ref: account_version.credential_ref,
          environment_ref: account_version.environment_ref,
          permitted_resource_refs: comma_list(Map.get(params, "permitted_resource_refs")),
          delivery_policy_document: delivery_policy
        })

      Providers.persist_provider(scope, provider)
    else
      false -> {:error, :provider_account_grant_mismatch}
      {:error, _reason} = error -> error
    end
  end

  defp provider_params(params) when is_map(params), do: Map.get(params, "provider", params)
  defp provider_params(_params), do: %{}

  defp immutable_account_id(params, account_id) do
    case Map.get(params, "provider_account_id") do
      nil -> :ok
      ^account_id -> :ok
      _other -> {:error, :provider_account_binding_mismatch}
    end
  end

  defp delivery_policy(%{"policy_mode" => "approval_required"} = params) do
    {:ok,
     %{
       "mode" => "approval_required",
       "changes_always_requiring_approval" => ["schedule", "resource", "capacity", "cost"],
       "deadline_behavior" => Map.get(params, "deadline_behavior", "retain_last_accepted")
     }}
  end

  defp delivery_policy(%{"policy_mode" => "bounded_automatic"} = params) do
    {:ok,
     %{
       "mode" => "bounded_automatic",
       "deadline_behavior" => Map.get(params, "deadline_behavior", "retain_last_accepted"),
       "approved_station_substitutions" =>
         comma_list(Map.get(params, "approved_station_substitutions"))
     }}
  end

  defp delivery_policy(_params), do: {:error, :invalid_delivery_policy}

  defp required_id(params, key) when is_map(params) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _invalid -> {:error, {:missing_action_parameter, key}}
    end
  end

  defp required_id(_params, key), do: {:error, {:missing_action_parameter, key}}

  defp required_text(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> {:error, {:missing_action_parameter, key}}
          value -> {:ok, value}
        end

      _invalid ->
        {:error, {:missing_action_parameter, key}}
    end
  end

  defp comma_list(value) when is_binary(value),
    do: value |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  defp comma_list(_value), do: []
end
