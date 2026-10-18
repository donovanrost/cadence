defmodule Cadence.GroundNetworks.MissionProviderRegistration do
  @moduledoc "Authorized mission-provider registration independent of frontend transport."
  alias Cadence.Auth.{Policy, Scope}

  alias Cadence.GroundNetworks.{
    DeliveryPolicy,
    MissionProvider,
    MissionProviders,
    ProviderAccountGrants,
    ProviderAccounts
  }

  @number_fields ~w(maximum_earlier_start_shift_seconds maximum_later_start_shift_seconds maximum_earlier_end_shift_seconds maximum_later_end_shift_seconds minimum_retained_duration_seconds)
  @fields ~w(display_name provider_account_grant_id provider_account_grant_version provider_account_id provider_account_version policy_mode deadline_behavior permitted_resource_refs approved_station_substitutions) ++
            @number_fields

  def create(scope, mission_id, params) do
    with {:ok, provider} <- prepare(scope, mission_id, params),
         do: MissionProviders.persist_provider(scope, provider)
  end

  defp authorize(%Scope{mission_id: scoped} = scope, mission_id)
       when is_nil(scoped) or scoped == mission_id do
    context = %{organization_id: scope.organization_id, mission_id: mission_id}

    with :ok <- Policy.authorize(scope, :operate_mission, context),
         do: Policy.authorize(scope, :manage_mission, context)
  end

  defp authorize(_scope, _mission), do: {:error, :forbidden}

  defp bounded_params(params) when is_map(params) do
    if map_size(params) <= length(@fields) and
         Enum.all?(params, fn {key, value} ->
           key in @fields and is_binary(value) and byte_size(value) <= 8192 and
             String.valid?(value)
         end), do: :ok, else: {:error, :invalid_application_request}
  end

  defp bounded_params(_params), do: {:error, :invalid_application_request}

  defp immutable_grant_versions(params, grant) do
    Enum.reduce_while(
      [
        {"provider_account_grant_version", grant.version},
        {"provider_account_version", grant.provider_account_version}
      ],
      :ok,
      fn {key, expected}, :ok ->
        if not Map.has_key?(params, key) or params[key] == Integer.to_string(expected),
          do: {:cont, :ok},
          else: {:halt, {:error, :provider_account_grant_mismatch}}
      end
    )
  end

  def prepare(scope, mission_id, params) do
    with :ok <- authorize(scope, mission_id),
         :ok <- bounded_params(params),
         {:ok, grant_id} <- required_id(params, "provider_account_grant_id"),
         {:ok, grant} <-
           ProviderAccountGrants.fetch_active_for_system(scope.organization_id, grant_id),
         true <- grant.mission_id == mission_id,
         :ok <- immutable_grant_versions(params, grant),
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

      {:ok, provider}
    else
      false -> {:error, :provider_account_grant_mismatch}
      {:error, _reason} = error -> error
    end
  end

  defp immutable_account_id(params, account_id) do
    case Map.get(params, "provider_account_id") do
      nil -> :ok
      ^account_id -> :ok
      _other -> {:error, :provider_account_binding_mismatch}
    end
  end

  defp delivery_policy(params) do
    with mode when mode in ["approval_required", "bounded_automatic"] <- params["policy_mode"],
         {:ok, numbers} <- policy_numbers(params, mode),
         {:ok, policy} <-
           DeliveryPolicy.normalize(
             Map.merge(numbers, %{
               "mode" => mode,
               "deadline_behavior" =>
                 Map.get(params, "deadline_behavior", "retain_last_accepted"),
               "changes_always_requiring_approval" =>
                 if(mode == "approval_required",
                   do: ["schedule", "resource", "capacity", "cost"],
                   else: []
                 ),
               "approved_station_substitutions" =>
                 if(mode == "bounded_automatic",
                   do: comma_list(params["approved_station_substitutions"]),
                   else: []
                 )
             })
           ) do
      {:ok, DeliveryPolicy.to_document(policy)}
    else
      _ -> {:error, :invalid_delivery_policy}
    end
  end

  defp policy_numbers(_params, "approval_required"), do: {:ok, %{}}

  defp policy_numbers(params, "bounded_automatic") do
    Enum.reduce_while(@number_fields, {:ok, %{}}, fn key, {:ok, acc} ->
      value =
        Map.get(params, key, if(key == "minimum_retained_duration_seconds", do: "", else: "0"))

      minimum = if key == "minimum_retained_duration_seconds", do: 1, else: 0

      case Integer.parse(value) do
        {number, ""} when number >= minimum and number <= 9_007_199_254_740_991 ->
          {:cont, {:ok, Map.put(acc, key, number)}}

        _ ->
          {:halt, {:error, :invalid_delivery_policy}}
      end
    end)
  end

  defp required_id(params, key) when is_map(params) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _invalid -> {:error, {:missing_action_parameter, key}}
    end
  end

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
