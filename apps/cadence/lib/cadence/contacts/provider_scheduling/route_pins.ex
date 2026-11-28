defmodule Cadence.Contacts.ProviderScheduling.RoutePins do
  @moduledoc """
  The immutable pins `ProviderScheduling` resolves a fleet's downlink routes against, loaded in
  bounded batches: link assignments, path templates, transport versions, the mission provider
  versions those transports pin, their profiles, and each pinned provider version's readiness.

  A pinned provider version is ready only while it is active, validated, synced, its account
  grant still binds it, and the provider has no newer ARCHIVED version (#985). Archiving adds a
  newer archived version while transports keep pinning the older active one, so the pinned
  version alone would still look schedulable; `mission_provider_archived` refuses it, the same
  rule as `Cadence.GroundNetworks.EphemerisStates`' bound pairs.
  """

  alias Cadence.Comms.TransportStore
  alias Cadence.Contacts.{LinkAssignmentStore, PathTemplateStore, ProfileStore}
  alias Cadence.GroundNetworks.{MissionProvider, MissionProviders, ProviderAccountGrants}
  alias Cadence.GroundNetworks.MissionProviders.Archived

  @doc "Loads the pins for `rules` (one batch per store, one archived-provider query)."
  @spec load(binary(), binary(), [struct()]) :: map()
  def load(organization_id, mission_id, rules) do
    assignments =
      LinkAssignmentStore.fetch_many(
        organization_id,
        mission_id,
        Enum.flat_map(rules, &materialized_assignment_ids/1)
      )

    templates =
      PathTemplateStore.fetch_versions(
        organization_id,
        mission_id,
        Enum.map(assignments, fn {_id, row} ->
          {row.path_template_id, row.path_template_version}
        end)
      )

    transports =
      TransportStore.fetch_transport_versions(
        organization_id,
        mission_id,
        Enum.map(rules, &{&1.transport_id, &1.transport_version})
      )

    managed = transports |> Map.values() |> Enum.filter(&(&1.origin == :provider_managed))
    keys = Enum.map(managed, &{&1.mission_provider_id, &1.mission_provider_version})
    providers = MissionProviders.fetch_provider_versions(organization_id, mission_id, keys)
    archived = Archived.archived_since(organization_id, mission_id, keys)

    profiles =
      ProfileStore.fetch_provider_profiles(
        organization_id,
        mission_id,
        managed |> Enum.map(& &1.materialized_provider_profile_id) |> Enum.reject(&is_nil/1)
      )

    %{
      assignments: assignments,
      templates: templates,
      transports: transports,
      current_transports:
        TransportStore.current_route_pins(
          organization_id,
          mission_id,
          Enum.map(rules, & &1.transport_id)
        ),
      providers: providers,
      provider_readiness:
        Map.new(providers, fn {key, provider} ->
          {key, readiness(provider, MapSet.member?(archived, key))}
        end),
      profiles: profiles
    }
  end

  @doc "The link assignment ids a routing rule materialized."
  @spec materialized_assignment_ids(struct()) :: [binary()]
  def materialized_assignment_ids(rule) do
    ids = Map.get(rule.metadata, "materialized_link_assignment_ids", [])

    if ids == [] and is_binary(rule.materialized_link_assignment_id),
      do: [rule.materialized_link_assignment_id],
      else: ids
  end

  defp readiness(_provider, true = _archived),
    do: {:error, :mission_provider_archived, "Mission Provider is archived."}

  defp readiness(provider, false) do
    with :ok <- provider_ready(provider), do: provider_grant_ready(provider)
  end

  defp provider_ready(%MissionProvider{} = provider) do
    cond do
      provider.lifecycle_state != :active ->
        {:error, :mission_provider_not_active, "Mission Provider version is not active."}

      not match?(%DateTime{}, provider.last_validated_at) or
          get_in(provider.metadata, ["control_plane", "status"]) != "healthy" ->
        {:error, :mission_provider_not_validated, "Mission Provider must validate successfully."}

      not match?(%DateTime{}, provider.last_synced_at) ->
        {:error, :mission_provider_profiles_not_synced,
         "Mission Provider profiles are not synchronized."}

      true ->
        :ok
    end
  end

  defp provider_grant_ready(%MissionProvider{provider_account_grant_id: nil}), do: :ok

  defp provider_grant_ready(%MissionProvider{} = provider) do
    case ProviderAccountGrants.validate_binding(
           provider.organization_id,
           provider.mission_id,
           provider.provider_account_id,
           provider.provider_account_version,
           provider.provider_account_grant_id,
           provider.provider_account_grant_version
         ) do
      {:ok, _grant} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
