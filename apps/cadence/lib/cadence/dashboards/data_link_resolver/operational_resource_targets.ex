defmodule Cadence.Dashboards.DataLinkResolver.OperationalResourceTargets do
  @moduledoc """
  Resolves contact, transport, link, source-endpoint, and ground-station targets.

  The resolver owns context-scoped resource reads, inspector rows, cross-resource
  links, and navigation actions for operational setup evidence.
  """

  import Cadence.Dashboards.DataLinkResolver.Support

  alias Cadence.Comms.{GroundStation, RoutingRule, Transport}

  alias Cadence.Contacts.{LinkAssignment, RealizedContact, ScheduledContact}

  alias Cadence.Dashboards.{
    DashboardAction,
    DataLink,
    DataLinkInspector
  }

  alias Cadence.Reads.OperationalState
  alias Cadence.SourceEndpoints.SourceEndpoint

  @spec resolve(DataLink.t(), binary(), binary()) ::
          {:ok, DataLinkInspector.t()} | {:error, DataLinkInspector.t()}
  def resolve(%DataLink{target: :contact} = link, organization_id, mission_id) do
    case fetch_contact(link.target_id, organization_id, mission_id) do
      {:scheduled, %ScheduledContact{} = contact} ->
        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           scheduled_contact_rows(contact),
           scheduled_contact_related_links(link, contact)
         )}

      {:realized, %RealizedContact{} = contact} ->
        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           realized_contact_rows(contact),
           realized_contact_related_links(link, contact)
         )}

      nil ->
        {:error, inspector(link, :missing, "Contact was not found in this mission.", [])}
    end
  end

  def resolve(%DataLink{target: :transport} = link, organization_id, mission_id) do
    case OperationalState.fetch_transport(organization_id, mission_id, link.target_id) do
      {:ok, %Transport{} = transport} ->
        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           transport_rows(transport),
           resource_related_links(link, transport),
           resource_actions(link)
         )}

      {:error, _reason} ->
        {:error,
         inspector(
           link,
           :missing,
           "Transport was not found in this mission.",
           [],
           resource_related_links(link),
           resource_actions(link)
         )}
    end
  end

  def resolve(%DataLink{target: :link} = link, organization_id, mission_id) do
    case OperationalState.fetch_link_assignment(organization_id, mission_id, link.target_id) do
      {:ok, %LinkAssignment{} = assignment} ->
        routing_rule = routing_rule_for_link_assignment(organization_id, mission_id, assignment)
        resource = link_assignment_resource(assignment, routing_rule)

        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           link_assignment_rows(assignment, routing_rule),
           resource_related_links(link, resource),
           resource_actions(link, resource) ++ routing_rule_actions(routing_rule)
         )}

      {:error, _reason} ->
        {:error,
         inspector(
           link,
           :missing,
           "Link assignment was not found in this mission.",
           [],
           resource_related_links(link),
           resource_actions(link)
         )}
    end
  end

  def resolve(%DataLink{target: :source_endpoint} = link, organization_id, mission_id) do
    case OperationalState.fetch_source_endpoint(organization_id, mission_id, link.target_id) do
      {:ok, %SourceEndpoint{} = source_endpoint} ->
        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           source_endpoint_rows(source_endpoint),
           resource_related_links(link, source_endpoint),
           resource_actions(link)
         )}

      {:error, _reason} ->
        {:error,
         inspector(
           link,
           :missing,
           "Source endpoint was not found in this mission.",
           [],
           resource_related_links(link),
           resource_actions(link)
         )}
    end
  end

  def resolve(%DataLink{target: :ground_station} = link, organization_id, mission_id) do
    case OperationalState.fetch_ground_station(organization_id, mission_id, link.target_id) do
      {:ok, %GroundStation{} = ground_station} ->
        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           ground_station_rows(ground_station),
           resource_related_links(link, ground_station),
           resource_actions(link)
         )}

      {:error, _reason} ->
        {:ok,
         inspector(
           link,
           :context_only,
           "Ground station was not found as setup state; using transport/source-endpoint metadata context.",
           ground_station_rows(link),
           resource_related_links(link),
           resource_actions(link)
         )}
    end
  end

  defp fetch_contact(contact_id, organization_id, mission_id) do
    case OperationalState.fetch_scheduled_contact(organization_id, mission_id, contact_id) do
      {:ok, %ScheduledContact{} = contact} ->
        {:scheduled, contact}

      {:error, _reason} ->
        case OperationalState.fetch_realized_contact(organization_id, mission_id, contact_id) do
          {:ok, %RealizedContact{} = contact} -> {:realized, contact}
          {:error, _reason} -> nil
        end
    end
  end

  defp scheduled_contact_rows(%ScheduledContact{} = contact) do
    [
      row("Contact", contact.scheduled_contact_id),
      row("Contact type", :scheduled_contact),
      row("Lifecycle state", contact.lifecycle_state),
      row("Starts", contact.starts_at),
      row("Ends", contact.ends_at),
      row("Source endpoints", contact.source_endpoint_refs),
      row("Contact intents", contact.contact_intents),
      row("Provider contact ref", contact.provider_contact_ref),
      row("Realized contact", contact.realized_contact_id),
      row("Path templates", contact.path_template_ids),
      row("Paths", path_ids(contact.paths)),
      row("Metadata", contact.metadata)
    ]
  end

  defp realized_contact_rows(%RealizedContact{} = contact) do
    [
      row("Realized contact", contact.realized_contact_id),
      row("Contact type", :realized_contact),
      row("Lifecycle state", contact.lifecycle_state),
      row("Scheduled contact", contact.scheduled_contact_id),
      row("Initial time", contact.initial_time),
      row("Realized", contact.realized_at),
      row("Ended", contact_end_time(contact.metadata)),
      row("Clock mode", contact.clock_mode),
      row("Source endpoints", contact.source_endpoint_refs),
      row("Contact intents", contact.contact_intents),
      row("Paths", path_ids(contact.paths)),
      row("Metadata", contact.metadata)
    ]
  end

  defp scheduled_contact_related_links(%DataLink{} = link, %ScheduledContact{} = contact) do
    [
      related_link(link, :contact, contact.realized_contact_id, "Realized contact")
    ]
  end

  defp realized_contact_related_links(%DataLink{} = link, %RealizedContact{} = contact) do
    [
      related_link(link, :contact, contact.scheduled_contact_id, "Scheduled contact")
    ]
  end

  defp transport_rows(%Transport{} = transport) do
    [
      row("Transport", transport.transport_id),
      row("Display name", transport.display_name),
      row("Version", transport.version),
      row("Lifecycle state", transport.lifecycle_state),
      row("Transport kind", transport.transport_kind),
      row("Direction", transport.direction_capability),
      row("Adapter", transport.adapter_key),
      row("Provider profile", transport.materialized_provider_profile_id),
      row(
        "Source endpoint",
        metadata_value(transport.metadata, [:source_endpoint_id, :source_endpoint_ref])
      ),
      row(
        "Ground station",
        metadata_value(transport.metadata, [:ground_station_id, :antenna_id])
      ),
      row(
        "Link",
        metadata_value(transport.metadata, [:link_id, :link_assignment_id, :link_assignment_ref])
      ),
      row("Metadata", transport.metadata)
    ]
  end

  defp link_assignment_rows(%LinkAssignment{} = assignment, routing_rule) do
    [
      row("Link", assignment.link_assignment_id),
      row("Lifecycle state", assignment.lifecycle_state),
      row("Spacecraft", assignment.spacecraft_id),
      row("Source endpoint", assignment.source_endpoint_ref),
      row("Path template", assignment.path_template_id),
      row("Path template version", assignment.path_template_version),
      row("Direction", assignment.direction),
      row("Selection role", assignment.selection_role),
      row("Provider path", assignment.provider_path_ref),
      row("Routing rule", routing_rule_value(routing_rule, :routing_rule_id)),
      row("Routing display name", routing_rule_value(routing_rule, :display_name)),
      row("Routing purpose", routing_rule_value(routing_rule, :purpose_label)),
      row("Routing direction", routing_rule_value(routing_rule, :direction)),
      row("Routing role", routing_rule_value(routing_rule, :role)),
      row("Transport", routing_rule_value(routing_rule, :transport_id)),
      row("Transport version", routing_rule_value(routing_rule, :transport_version)),
      row("Enabled", routing_rule_value(routing_rule, :enabled?)),
      row("Metadata", assignment.metadata)
    ]
  end

  defp source_endpoint_rows(%SourceEndpoint{} = source_endpoint) do
    [
      row("Source endpoint", source_endpoint.source_endpoint_id),
      row("Display name", source_endpoint.display_name),
      row("Spacecraft", source_endpoint.spacecraft_id),
      row("Source ref", source_endpoint.source_ref),
      row("SCID", source_endpoint.scid),
      row(
        "Ground station",
        metadata_value(source_endpoint.metadata, [:ground_station_id, :antenna_id])
      ),
      row(
        "Link",
        metadata_value(source_endpoint.metadata, [
          :link_id,
          :link_assignment_id,
          :link_assignment_ref
        ])
      ),
      row("Metadata", source_endpoint.metadata)
    ]
  end

  defp ground_station_rows(%DataLink{} = link) do
    resource = context_value(link.context, :operational_resource)

    [
      row("Ground station", link.target_id),
      row("Resource", state_value(resource, :resource_id)),
      row("Scope kind", state_value(resource, :scope_kind)),
      row("Transport", state_value(resource, :transport_id)),
      row("Source endpoint", state_value(resource, :source_endpoint_id)),
      row("Link", state_value(resource, :link_id)),
      row("Adapter", state_value(resource, :adapter_key))
    ]
  end

  defp ground_station_rows(%GroundStation{} = ground_station) do
    [
      row("Ground station", ground_station.ground_station_id),
      row("Display name", ground_station.display_name),
      row("Provider", ground_station.provider),
      row("Region", ground_station.region),
      row("Transport", metadata_value(ground_station.metadata, [:transport_id])),
      row(
        "Source endpoint",
        metadata_value(ground_station.metadata, [:source_endpoint_id, :source_endpoint_ref])
      ),
      row("Link", metadata_value(ground_station.metadata, [:link_id, :link_assignment_id])),
      row("Metadata", ground_station.metadata)
    ]
  end

  defp resource_related_links(%DataLink{} = link, persisted_resource \\ nil) do
    resource = resource_context(link, persisted_resource)

    [
      related_resource_link(
        link,
        :transport,
        state_value(resource, :transport_id),
        "Transport"
      ),
      related_resource_link(
        link,
        :source_endpoint,
        state_value(resource, :source_endpoint_id),
        "Source endpoint"
      ),
      related_resource_link(
        link,
        :ground_station,
        state_value(resource, :ground_station_id),
        "Ground station"
      ),
      related_resource_link(
        link,
        :link,
        state_value(resource, :link_id),
        "Link"
      )
    ]
  end

  defp related_resource_link(
         %DataLink{target: target, target_id: target_id},
         target,
         target_id,
         _label
       ),
       do: nil

  defp related_resource_link(%DataLink{} = link, target, target_id, label) do
    related_link(link, target, target_id, label)
  end

  defp resource_actions(%DataLink{} = link, persisted_resource \\ nil) do
    data_context = context_value(link.context, :data) || %{}
    resource = resource_context(link, persisted_resource)

    inventory_query =
      %{
        "selected_target" => data_ref_text(link.target),
        "selected_id" => link.target_id,
        "transport_id" => state_value(resource, :transport_id),
        "source_endpoint_id" => state_value(resource, :source_endpoint_id),
        "ground_station_id" => state_value(resource, :ground_station_id),
        "link_id" => state_value(resource, :link_id),
        "realm" => context_value(data_context, :realm),
        "data_source_id" => context_value(data_context, :data_source_id),
        "source_binding_id" => context_value(data_context, :source_binding_id),
        "logical_source" => context_value(link.context, :logical_source)
      }
      |> compact_action_query()

    source_query =
      %{
        "realm" => context_value(data_context, :realm),
        "data_source_id" => context_value(data_context, :data_source_id),
        "source_binding_id" => context_value(data_context, :source_binding_id),
        "logical_source" => context_value(link.context, :logical_source)
      }
      |> compact_action_query()

    [
      resource_action(
        "dashboard-operational-resource-inventory",
        "View source inventory",
        :source_inventory,
        inventory_query,
        link.context
      ),
      resource_action(
        "dashboard-operational-resource-health",
        "View source health",
        :source_health,
        source_query,
        link.context
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp resource_action(_action_id, _label, _target, query, _context)
       when map_size(query) == 0,
       do: nil

  defp resource_action(action_id, label, target, query, context) do
    %DashboardAction{
      action_id: action_id,
      label: label,
      target: target,
      kind: :invoke,
      query: query,
      context: context,
      source: :data_link_panel
    }
  end

  defp compact_action_query(query) do
    query
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new(fn {key, value} -> {key, value_text(value)} end)
  end

  defp resource_context(%DataLink{} = link, persisted_resource) do
    link.context
    |> context_value(:operational_resource)
    |> merge_resource_context(link, persisted_resource)
  end

  defp merge_resource_context(context, %DataLink{} = link, persisted_resource) do
    context
    |> context_map_or_empty()
    |> Map.put_new(:transport_id, resource_transport_id(link, persisted_resource))
    |> Map.put_new(:source_endpoint_id, resource_source_endpoint_id(persisted_resource))
    |> Map.put_new(:ground_station_id, resource_ground_station_id(persisted_resource))
    |> Map.put_new(:link_id, resource_link_id(persisted_resource))
  end

  defp resource_transport_id(
         %DataLink{target: :transport, target_id: target_id},
         _resource
       ),
       do: target_id

  defp resource_transport_id(_link, %GroundStation{} = ground_station),
    do: metadata_value(ground_station.metadata, [:transport_id])

  defp resource_transport_id(_link, resource)
       when is_map(resource) and not is_struct(resource),
       do: state_value(resource, :transport_id)

  defp resource_transport_id(_link, _resource), do: nil

  defp resource_source_endpoint_id(%Transport{} = transport),
    do: metadata_value(transport.metadata, [:source_endpoint_id, :source_endpoint_ref])

  defp resource_source_endpoint_id(%SourceEndpoint{} = source_endpoint),
    do: source_endpoint.source_endpoint_id

  defp resource_source_endpoint_id(%GroundStation{} = ground_station),
    do: metadata_value(ground_station.metadata, [:source_endpoint_id, :source_endpoint_ref])

  defp resource_source_endpoint_id(resource)
       when is_map(resource) and not is_struct(resource),
       do: state_value(resource, :source_endpoint_id)

  defp resource_source_endpoint_id(_resource), do: nil

  defp resource_ground_station_id(%Transport{} = transport),
    do: metadata_value(transport.metadata, [:ground_station_id, :antenna_id])

  defp resource_ground_station_id(%SourceEndpoint{} = source_endpoint),
    do: metadata_value(source_endpoint.metadata, [:ground_station_id, :antenna_id])

  defp resource_ground_station_id(%GroundStation{} = ground_station),
    do: ground_station.ground_station_id

  defp resource_ground_station_id(resource)
       when is_map(resource) and not is_struct(resource),
       do: state_value(resource, :ground_station_id)

  defp resource_ground_station_id(_resource), do: nil

  defp resource_link_id(%Transport{} = transport),
    do: metadata_value(transport.metadata, [:link_id, :link_assignment_id, :link_assignment_ref])

  defp resource_link_id(%SourceEndpoint{} = source_endpoint),
    do:
      metadata_value(source_endpoint.metadata, [
        :link_id,
        :link_assignment_id,
        :link_assignment_ref
      ])

  defp resource_link_id(%GroundStation{} = ground_station),
    do:
      metadata_value(ground_station.metadata, [
        :link_id,
        :link_assignment_id,
        :link_assignment_ref
      ])

  defp resource_link_id(resource) when is_map(resource) and not is_struct(resource),
    do: state_value(resource, :link_id)

  defp resource_link_id(_resource), do: nil

  defp routing_rule_for_link_assignment(
         organization_id,
         mission_id,
         %LinkAssignment{} = assignment
       ) do
    OperationalState.list_routing_rules(organization_id, mission_id)
    |> Enum.find(&routing_rule_materialized_link?(&1, assignment.link_assignment_id))
  end

  defp routing_rule_materialized_link?(%RoutingRule{} = rule, link_assignment_id) do
    rule.materialized_link_assignment_id == link_assignment_id or
      link_assignment_id in materialized_link_assignment_ids(rule.metadata)
  end

  defp materialized_link_assignment_ids(metadata) when is_map(metadata) do
    metadata
    |> metadata_value([:materialized_link_assignment_ids])
    |> List.wrap()
    |> Enum.reject(&is_nil/1)
  end

  defp materialized_link_assignment_ids(_metadata), do: []

  defp link_assignment_resource(%LinkAssignment{} = assignment, routing_rule) do
    %{
      link_id: assignment.link_assignment_id,
      source_endpoint_id: assignment.source_endpoint_ref,
      transport_id: routing_rule_value(routing_rule, :transport_id)
    }
  end

  defp routing_rule_actions(nil), do: []

  defp routing_rule_actions(%RoutingRule{} = routing_rule) do
    [
      %DashboardAction{
        action_id: "dashboard-link-routing-rule",
        label: "View routing rule",
        target: :routing_rule,
        kind: :invoke,
        query: %{"routing_rule_id" => routing_rule.routing_rule_id},
        context: %{
          organization_id: routing_rule.organization_id,
          mission_id: routing_rule.mission_id,
          routing_rule_id: routing_rule.routing_rule_id
        },
        source: :data_link_panel
      }
    ]
  end

  defp routing_rule_value(%RoutingRule{} = routing_rule, :enabled?), do: routing_rule.enabled?
  defp routing_rule_value(%RoutingRule{} = routing_rule, key), do: Map.get(routing_rule, key)
  defp routing_rule_value(_routing_rule, _key), do: nil

  defp path_ids(paths) when is_list(paths) do
    paths
    |> Enum.map(&Map.get(&1, :path_id))
    |> Enum.reject(&is_nil/1)
  end

  defp path_ids(_paths), do: []

  defp contact_end_time(metadata) when is_map(metadata) do
    Map.get(metadata, :completed_at) ||
      Map.get(metadata, "completed_at") ||
      Map.get(metadata, :stopped_at) ||
      Map.get(metadata, "stopped_at") ||
      Map.get(metadata, :ended_at) ||
      Map.get(metadata, "ended_at")
  end

  defp contact_end_time(_metadata), do: nil
end
