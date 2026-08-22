defmodule Cadence.Comms.RoutingRuleStore do
  @moduledoc """
  Persistence boundary for Routing Rules and their append-only events.
  """

  import Ecto.Query

  alias Ecto.Changeset

  alias Cadence.Comms.{
    RoutingRule,
    RoutingRuleEvent,
    RoutingRuleEventRow,
    RoutingRuleRow,
    Transport
  }

  alias Cadence.Comms.TransportStore

  alias Cadence.Contacts.{
    LinkAssignment,
    LinkAssignmentStore,
    PathTemplate,
    PathTemplateStore,
    ProfileStore
  }

  alias Cadence.Missions
  alias Cadence.Repo
  alias Cadence.SourceEndpoints
  alias Cadence.Spacecraft
  alias Cadence.SpacecraftStore

  @spec create_routing_rule(binary(), RoutingRule.t(), keyword()) ::
          {:ok, RoutingRule.t()} | {:error, term()}
  def create_routing_rule(organization_id, %RoutingRule{} = routing_rule, opts \\ [])
      when is_binary(organization_id) and is_list(opts) do
    transaction_result =
      Repo.transaction(fn ->
        with {:ok, scoped_rule} <- put_organization_scope(routing_rule, organization_id),
             {:ok, _mission} <-
               Missions.fetch_mission(scoped_rule.organization_id, scoped_rule.mission_id),
             {:ok, prepared_rule} <- prepare_rule(scoped_rule),
             {:ok, materialized_rule} <- materialize_runtime_compatibility(prepared_rule),
             {:ok, _row} <- Repo.insert(RoutingRuleRow.changeset(materialized_rule)),
             {:ok, _created_event} <- append_event(materialized_rule, :created, opts),
             {:ok, _materialized_event} <- append_event(materialized_rule, :materialized, opts) do
          materialized_rule
        else
          {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case transaction_result do
      {:ok, %RoutingRule{} = rule} ->
        fetch_routing_rule(rule.organization_id, rule.mission_id, rule.routing_rule_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec update_routing_rule(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, RoutingRule.t()} | {:error, term()}
  def update_routing_rule(organization_id, mission_id, routing_rule_id, attrs, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(routing_rule_id) and
             is_map(attrs) and is_list(opts) do
    transaction_result =
      Repo.transaction(fn ->
        with {:ok, %RoutingRule{} = current_rule} <-
               fetch_routing_rule(organization_id, mission_id, routing_rule_id),
             {:ok, next_rule} <- build_next_rule(current_rule, attrs),
             {:ok, prepared_rule} <- prepare_rule(next_rule),
             {:ok, materialized_rule} <- materialize_runtime_compatibility(prepared_rule),
             {:ok, _count} <- update_rule_row(materialized_rule),
             {:ok, _event} <- append_event(materialized_rule, :updated, opts) do
          materialized_rule
        else
          {:error, %Changeset{} = changeset} -> Repo.rollback(changeset)
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case transaction_result do
      {:ok, %RoutingRule{lifecycle_state: :archived} = rule} ->
        fetch_routing_rule_state(rule.organization_id, rule.mission_id, rule.routing_rule_id)

      {:ok, %RoutingRule{} = rule} ->
        fetch_routing_rule(rule.organization_id, rule.mission_id, rule.routing_rule_id)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec set_routing_rule_enabled(binary(), binary(), binary(), boolean(), keyword()) ::
          {:ok, RoutingRule.t()} | {:error, term()}
  def set_routing_rule_enabled(organization_id, mission_id, routing_rule_id, enabled?, opts \\ [])
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(routing_rule_id) and
             is_boolean(enabled?) and is_list(opts) do
    event_type = if enabled?, do: :enabled, else: :disabled

    with {:ok, %RoutingRule{} = rule} <-
           update_routing_rule(
             organization_id,
             mission_id,
             routing_rule_id,
             %{enabled?: enabled?},
             Keyword.put(opts, :event_type, event_type)
           ) do
      {:ok, rule}
    end
  end

  @spec archive_routing_rule(binary(), binary(), binary(), map(), keyword()) ::
          {:ok, RoutingRule.t()} | {:error, term()}
  def archive_routing_rule(
        organization_id,
        mission_id,
        routing_rule_id,
        metadata_patch \\ %{},
        opts \\ []
      )
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(routing_rule_id) and
             is_map(metadata_patch) and is_list(opts) do
    update_routing_rule(
      organization_id,
      mission_id,
      routing_rule_id,
      %{
        lifecycle_state: :archived,
        enabled?: false,
        metadata_patch: Map.put(metadata_patch, "archived_at", DateTime.utc_now())
      },
      Keyword.put(opts, :event_type, :archived)
    )
  end

  @spec fetch_routing_rule(binary(), binary(), binary()) ::
          {:ok, RoutingRule.t()} | {:error, term()}
  def fetch_routing_rule(organization_id, mission_id, routing_rule_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(routing_rule_id) do
    case Repo.get_by(RoutingRuleRow,
           organization_id: organization_id,
           mission_id: mission_id,
           routing_rule_id: routing_rule_id
         ) do
      nil ->
        {:error, :routing_rule_not_found}

      %RoutingRuleRow{lifecycle_state: "archived"} ->
        {:error, :routing_rule_not_found}

      %RoutingRuleRow{} = row ->
        {:ok, RoutingRuleRow.to_domain(row)}
    end
  end

  @spec fetch_routing_rule_state(binary(), binary(), binary()) ::
          {:ok, RoutingRule.t()} | {:error, term()}
  def fetch_routing_rule_state(organization_id, mission_id, routing_rule_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(routing_rule_id) do
    case Repo.get_by(RoutingRuleRow,
           organization_id: organization_id,
           mission_id: mission_id,
           routing_rule_id: routing_rule_id
         ) do
      nil -> {:error, :routing_rule_not_found}
      %RoutingRuleRow{} = row -> {:ok, RoutingRuleRow.to_domain(row)}
    end
  end

  @spec list_routing_rules(binary(), binary()) :: [RoutingRule.t()]
  def list_routing_rules(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id) do
    RoutingRuleRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.lifecycle_state != "archived"
    )
    |> order_by([row], asc: row.spacecraft_id, asc: row.purpose_label, asc: row.direction)
    |> Repo.all()
    |> Enum.map(&RoutingRuleRow.to_domain/1)
  end

  @spec list_routing_rules_for_spacecraft(binary(), binary(), binary()) :: [RoutingRule.t()]
  def list_routing_rules_for_spacecraft(organization_id, mission_id, spacecraft_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(spacecraft_id) do
    RoutingRuleRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.spacecraft_id == ^spacecraft_id and row.lifecycle_state != "archived"
    )
    |> order_by([row], asc: row.purpose_label, asc: row.direction)
    |> Repo.all()
    |> Enum.map(&RoutingRuleRow.to_domain/1)
  end

  @spec list_routing_rule_events(binary(), binary(), binary()) :: [RoutingRuleEvent.t()]
  def list_routing_rule_events(organization_id, mission_id, routing_rule_id)
      when is_binary(organization_id) and is_binary(mission_id) and is_binary(routing_rule_id) do
    RoutingRuleEventRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.routing_rule_id == ^routing_rule_id
    )
    |> order_by([row], asc: row.occurred_at, asc: row.routing_rule_event_id)
    |> Repo.all()
    |> Enum.map(&RoutingRuleEventRow.to_domain/1)
  end

  defp prepare_rule(%RoutingRule{} = rule) do
    with {:ok, %Spacecraft{} = _spacecraft} <-
           SpacecraftStore.fetch_spacecraft(
             rule.organization_id,
             rule.mission_id,
             rule.spacecraft_id
           ),
         {:ok, %Transport{} = transport} <-
           TransportStore.fetch_transport_version(
             rule.organization_id,
             rule.mission_id,
             rule.transport_id,
             rule.transport_version
           ),
         :ok <- validate_transport_active(transport) do
      {:ok, rule}
    end
  end

  defp validate_transport_active(%Transport{lifecycle_state: :active}), do: :ok
  defp validate_transport_active(%Transport{}), do: {:error, :routing_rule_transport_archived}

  defp materialize_runtime_compatibility(%RoutingRule{enabled?: false} = rule), do: {:ok, rule}

  defp materialize_runtime_compatibility(%RoutingRule{} = rule) do
    with {:ok, %Spacecraft{} = spacecraft} <-
           SpacecraftStore.fetch_spacecraft(
             rule.organization_id,
             rule.mission_id,
             rule.spacecraft_id
           ),
         {:ok, source_endpoint} <-
           SourceEndpoints.ensure_managed_source_endpoint(rule.organization_id, spacecraft),
         {:ok, %Transport{} = transport} <-
           TransportStore.fetch_transport_version(
             rule.organization_id,
             rule.mission_id,
             rule.transport_id,
             rule.transport_version
           ),
         {:ok, provider_profile} <- fetch_materialized_provider(rule, transport),
         {:ok, materialized} <-
           materialize_for_directions(rule, source_endpoint.source_endpoint_id, provider_profile) do
      {:ok, merge_materialized_refs(rule, materialized)}
    end
  end

  defp fetch_materialized_provider(_rule, %Transport{materialized_provider_profile_id: nil}) do
    {:error, :routing_rule_transport_provider_not_materialized}
  end

  defp fetch_materialized_provider(rule, %Transport{materialized_provider_profile_id: provider_id}) do
    ProfileStore.fetch_provider_profile(rule.organization_id, rule.mission_id, provider_id)
  end

  defp materialize_for_directions(
         %RoutingRule{direction: :bidirectional} = rule,
         source_endpoint_ref,
         provider
       ) do
    with {:ok, inbound} <- materialize_direction(rule, :inbound, source_endpoint_ref, provider),
         {:ok, outbound} <- materialize_direction(rule, :outbound, source_endpoint_ref, provider) do
      {:ok, [inbound, outbound]}
    end
  end

  defp materialize_for_directions(
         %RoutingRule{direction: direction} = rule,
         source_endpoint_ref,
         provider
       ) do
    with {:ok, materialized} <-
           materialize_direction(rule, direction, source_endpoint_ref, provider) do
      {:ok, [materialized]}
    end
  end

  defp materialize_direction(rule, direction, source_endpoint_ref, provider) do
    path_direction = path_direction(direction)
    selection_role = selection_role(rule.role)

    provider_ref = %{
      "provider_profile_id" => provider.provider_profile_id,
      "version" => provider.version
    }

    path_template =
      PathTemplate.new(%{
        mission_id: rule.mission_id,
        path_id: "#{rule.routing_rule_id}:#{path_direction}",
        direction: path_direction,
        selection_role: selection_role,
        provider_path_ref: rule.provider_path_ref,
        provider_profile_refs: [provider_ref],
        metadata: %{
          "display_name" => "#{rule.display_name} #{path_direction}",
          "materialized_from_routing_rule_id" => rule.routing_rule_id
        }
      })

    with {:ok, path_template} <-
           PathTemplateStore.persist(rule.organization_id, path_template) do
      assignment =
        LinkAssignment.new(%{
          mission_id: rule.mission_id,
          spacecraft_id: rule.spacecraft_id,
          source_endpoint_ref: source_endpoint_ref,
          path_template_id: path_template.path_template_id,
          path_template_version: path_template.version,
          direction: path_template.direction,
          selection_role: path_template.selection_role,
          provider_path_ref: rule.provider_path_ref,
          provider_profile_refs: path_template.provider_profile_refs,
          metadata: %{
            "display_name" => "#{rule.display_name} #{path_direction}",
            "materialized_from_routing_rule_id" => rule.routing_rule_id
          }
        })

      with {:ok, assignment} <-
             LinkAssignmentStore.persist(rule.organization_id, assignment) do
        {:ok, %{path_template: path_template, link_assignment: assignment}}
      end
    end
  end

  defp path_direction(:inbound), do: :downlink
  defp path_direction(:outbound), do: :uplink

  defp selection_role(:primary), do: :selected
  defp selection_role(:candidate), do: :candidate
  defp selection_role(:contributing), do: :contributing

  defp merge_materialized_refs(%RoutingRule{} = rule, materialized) do
    assignment_ids = Enum.map(materialized, & &1.link_assignment.link_assignment_id)
    path_template_ids = Enum.map(materialized, & &1.path_template.path_template_id)

    %RoutingRule{
      rule
      | materialized_link_assignment_id: List.first(assignment_ids),
        metadata:
          rule.metadata
          |> Map.put("materialized_link_assignment_ids", assignment_ids)
          |> Map.put("materialized_path_template_ids", path_template_ids)
    }
  end

  defp append_event(%RoutingRule{} = rule, default_event_type, opts) do
    event_type = Keyword.get(opts, :event_type, default_event_type)

    event =
      RoutingRuleEvent.new(%{
        organization_id: rule.organization_id,
        mission_id: rule.mission_id,
        routing_rule_id: rule.routing_rule_id,
        event_type: event_type,
        actor_id: Keyword.get(opts, :actor_id),
        payload: event_payload(rule, event_type)
      })

    case Repo.insert(RoutingRuleEventRow.changeset(event)) do
      {:ok, %RoutingRuleEventRow{} = row} -> {:ok, RoutingRuleEventRow.to_domain(row)}
      {:error, %Changeset{} = changeset} -> {:error, changeset}
    end
  end

  defp event_payload(rule, event_type) do
    %{
      "event_type" => Atom.to_string(event_type),
      "spacecraft_id" => rule.spacecraft_id,
      "transport_id" => rule.transport_id,
      "transport_version" => rule.transport_version,
      "direction" => Atom.to_string(rule.direction),
      "role" => Atom.to_string(rule.role),
      "enabled" => rule.enabled?
    }
  end

  defp update_rule_row(%RoutingRule{} = rule) do
    case Repo.get_by(RoutingRuleRow,
           organization_id: rule.organization_id,
           mission_id: rule.mission_id,
           routing_rule_id: rule.routing_rule_id
         ) do
      nil ->
        {:error, :routing_rule_not_found}

      %RoutingRuleRow{} ->
        {count, _rows} =
          RoutingRuleRow
          |> where(
            [row],
            row.organization_id == ^rule.organization_id and
              row.mission_id == ^rule.mission_id and
              row.routing_rule_id == ^rule.routing_rule_id
          )
          |> Repo.update_all(
            set: [
              spacecraft_id: rule.spacecraft_id,
              lifecycle_state: Atom.to_string(rule.lifecycle_state),
              display_name: rule.display_name,
              purpose_label: rule.purpose_label,
              direction: Atom.to_string(rule.direction),
              transport_id: rule.transport_id,
              transport_version: rule.transport_version,
              provider_path_ref: rule.provider_path_ref,
              role: Atom.to_string(rule.role),
              enabled: rule.enabled?,
              materialized_link_assignment_id: rule.materialized_link_assignment_id,
              metadata: %{"value" => rule.metadata},
              updated_at: DateTime.utc_now()
            ]
          )

        case count do
          1 -> {:ok, 1}
          _other -> {:error, :routing_rule_not_found}
        end
    end
  end

  defp build_next_rule(%RoutingRule{} = rule, attrs) do
    metadata =
      rule.metadata
      |> Map.merge(Map.get(attrs, :metadata, %{}))
      |> Map.merge(Map.get(attrs, :metadata_patch, %{}))

    {:ok,
     RoutingRule.new(%{
       routing_rule_id: rule.routing_rule_id,
       organization_id: rule.organization_id,
       mission_id: rule.mission_id,
       spacecraft_id: Map.get(attrs, :spacecraft_id, rule.spacecraft_id),
       lifecycle_state: Map.get(attrs, :lifecycle_state, rule.lifecycle_state),
       display_name: Map.get(attrs, :display_name, rule.display_name),
       purpose_label: Map.get(attrs, :purpose_label, rule.purpose_label),
       direction: Map.get(attrs, :direction, rule.direction),
       transport_id: Map.get(attrs, :transport_id, rule.transport_id),
       transport_version: Map.get(attrs, :transport_version, rule.transport_version),
       provider_path_ref: Map.get(attrs, :provider_path_ref, rule.provider_path_ref),
       role: Map.get(attrs, :role, rule.role),
       enabled?: Map.get(attrs, :enabled?, rule.enabled?),
       materialized_link_assignment_id: nil,
       metadata: metadata
     })}
  end

  defp put_organization_scope(%RoutingRule{} = rule, organization_id)
       when is_binary(organization_id) and organization_id != "" do
    case rule.organization_id do
      nil ->
        {:ok, %RoutingRule{rule | organization_id: organization_id}}

      ^organization_id ->
        {:ok, rule}

      existing_organization_id ->
        {:error,
         {:organization_mission_mismatch, existing_organization_id, organization_id,
          rule.mission_id}}
    end
  end
end
