defmodule Cadence.Comms.RoutingRuleStore.Batch do
  @moduledoc false

  alias Cadence.Comms.{RoutingRuleEventRow, RoutingRuleRow, RoutingRuleStore, TransportStore}
  alias Cadence.Comms.UplinkGateway
  alias Cadence.Contacts.{LinkAssignmentStore, PathTemplateStore, ProfileStore}
  alias Cadence.Persistence.BulkInsert
  alias Cadence.SourceEndpoints

  @updated_fields [
    :lifecycle_state,
    :enabled,
    :display_name,
    :purpose_label,
    :direction,
    :transport_id,
    :transport_version,
    :provider_path_ref,
    :role,
    :materialized_link_assignment_id,
    :spacecraft_type_id,
    :spacecraft_type_version,
    :metadata,
    :updated_at
  ]

  def persist(_org, _mission, [], _context), do: :ok

  def persist(org, mission, changes, context) do
    active = Enum.reject(changes, &match?({_, _, :archived}, &1))
    ids = active |> Enum.map(fn {_, rule, _} -> rule.spacecraft_id end) |> Enum.uniq()
    spacecraft = Enum.map(ids, &Map.fetch!(context.spacecraft, &1))

    provider_profiles = load_providers(org, mission, active, context.transports)

    with :ok <- validate_archive_pins(org, mission, changes, context.transports),
         {:ok, active} <- materialize(active, context, provider_profiles),
         :ok <- SourceEndpoints.ensure_managed_source_endpoints(org, mission, spacecraft),
         :ok <- retire(org, mission, changes),
         :ok <- persist_artifacts(active) do
      persist_rows(changes, active)
    end
  end

  defp load_providers(org, mission, active, transports) do
    ids =
      active
      |> Enum.map(fn {_, rule, _} ->
        Map.fetch!(transports, rule.transport_id).materialized_provider_profile_id
      end)
      |> Enum.reject(&is_nil/1)

    ProfileStore.fetch_provider_profiles(org, mission, ids)
  end

  defp validate_archive_pins(org, mission, changes, transports) do
    pins =
      for {_, rule, :archived} <- changes,
          not match?(
            %{version: version} when version == rule.transport_version,
            Map.get(transports, rule.transport_id)
          ),
          do: {{rule.transport_id, rule.transport_version}, rule.profile_rule_id}

    stored = TransportStore.fetch_transport_versions(org, mission, Enum.map(pins, &elem(&1, 0)))

    Enum.find_value(pins, :ok, fn {pin, id} ->
      case Map.get(stored, pin) do
        %{lifecycle_state: :active} -> nil
        nil -> {:error, id, :transport_not_found}
        _archived -> {:error, id, :routing_rule_transport_archived}
      end
    end)
  end

  defp materialize(changes, context, providers) do
    Enum.reduce_while(changes, {:ok, []}, fn {_, rule, event}, {:ok, plans} ->
      transport = Map.fetch!(context.transports, rule.transport_id)
      spacecraft = Map.fetch!(context.spacecraft, rule.spacecraft_id)

      case provider(providers, transport.materialized_provider_profile_id) do
        {:ok, provider} ->
          {route, gateway, artifacts} = artifacts(rule, spacecraft, transport, provider)
          {:cont, {:ok, [{route, event, gateway, artifacts} | plans]}}

        {:error, reason} ->
          {:halt, {:error, rule.profile_rule_id, reason}}
      end
    end)
  end

  defp provider(_providers, nil), do: {:error, :routing_rule_transport_provider_not_materialized}

  defp provider(providers, id) do
    case Map.fetch(providers, id) do
      {:ok, provider} -> {:ok, provider}
      :error -> {:error, :contact_provider_profile_not_found}
    end
  end

  defp artifacts(rule, spacecraft, transport, provider) do
    gateway =
      if rule.direction == :outbound,
        do: UplinkGateway.profile(rule, spacecraft, transport, provider)

    endpoint = SourceEndpoints.managed_source_endpoint_id(spacecraft.spacecraft_id)
    artifacts = RoutingRuleStore.route_artifacts(rule, endpoint, provider, gateway)
    {RoutingRuleStore.merge_materialized_refs(rule, [artifacts]), gateway, artifacts}
  end

  defp retire(org, mission, changes) do
    assignments = retired_by(changes, "materialized_link_assignment_ids")
    templates = retired_by(changes, "materialized_path_template_ids")

    with :ok <- LinkAssignmentStore.retire_route_assignments(org, mission, assignments),
         {:ok, _} <- PathTemplateStore.retire_route_templates(org, mission, templates) do
      :ok
    end
  end

  defp retired_by(changes, key) do
    for {current, _, _} <- changes,
        current != nil,
        id <- Map.get(current.metadata, key, []),
        into: %{},
        do: {id, current.routing_rule_id}
  end

  defp persist_artifacts(plans) do
    gateways = for {_, _, gateway, _} <- plans, gateway != nil, do: gateway
    templates = Enum.map(plans, fn {_, _, _, artifacts} -> artifacts.path_template end)
    assignments = Enum.map(plans, fn {_, _, _, artifacts} -> artifacts.link_assignment end)

    with {:ok, _} <- ProfileStore.persist_route_gateways(gateways),
         {:ok, _} <- PathTemplateStore.persist_route_templates(templates),
         {:ok, _} <- LinkAssignmentStore.persist_route_assignments(assignments) do
      :ok
    end
  end

  defp persist_rows(changes, active) do
    archived = for {_, rule, :archived} <- changes, do: {rule, :archived}
    routes = Enum.map(active, fn {rule, event, _, _} -> {rule, event} end) ++ archived

    with {:ok, _} <-
           BulkInsert.changesets(
             RoutingRuleRow,
             Stream.map(routes, fn {rule, _} -> RoutingRuleRow.changeset(rule) end),
             on_conflict: {:replace, @updated_fields},
             conflict_target: [:mission_id, :routing_rule_id]
           ),
         {:ok, _} <-
           BulkInsert.changesets(RoutingRuleEventRow, Enum.flat_map(routes, &event_changesets/1)) do
      :ok
    end
  end

  defp event_changesets({rule, :created}),
    do: Enum.map([:created, :materialized], &event_changeset(rule, &1))

  defp event_changesets({rule, event}), do: [event_changeset(rule, event)]

  defp event_changeset(rule, event) do
    rule
    |> RoutingRuleStore.route_event(event)
    |> RoutingRuleEventRow.changeset()
  end
end
