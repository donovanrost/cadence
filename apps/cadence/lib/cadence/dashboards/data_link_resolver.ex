defmodule Cadence.Dashboards.DataLinkResolver do
  @moduledoc """
  Resolves typed dashboard data links into inspector payloads.

  This is the boundary between a dashboard's runtime data-link contract and the
  persisted records behind it.
  """

  import Ecto.Query
  import Cadence.Dashboards.DataLinkResolver.Support

  alias Cadence.Dashboards.{
    DataLink,
    DataLinkInspector,
    LifecycleEvent
  }

  alias Cadence.Dashboards.DataLinkResolver.BackfillLifecycleRows
  alias Cadence.Dashboards.DataLinkResolver.CommandTargets
  alias Cadence.Dashboards.DataLinkResolver.EventTargets
  alias Cadence.Dashboards.DataLinkResolver.LimitTargets
  alias Cadence.Dashboards.DataLinkResolver.OperationalResourceTargets
  alias Cadence.Dashboards.DataLinkResolver.SourceStateTargets
  alias Cadence.Dashboards.DataLinkResolver.TransportRuntimeTargets
  alias Cadence.Limits
  alias Cadence.Ops.PointCatalog

  alias Cadence.Persistence.Schemas.{
    RawEvidenceRow,
    TelemetrySampleRow
  }

  alias Cadence.Repo
  alias Cadence.Telemetry.Storage, as: TelemetryStorage

  @supported_targets DataLink.resolvable_targets()

  @type inspector :: DataLinkInspector.t()

  @spec resolve(DataLink.t(), keyword()) :: {:ok, inspector()} | {:error, inspector()}
  def resolve(%DataLink{} = link, opts) when is_list(opts) do
    # authz pending: enforce mission-scoped evidence inspection permission before
    # returning rows that reference telemetry, limits, or raw evidence records.
    case required_scope(opts) do
      {:ok, organization_id, mission_id} ->
        scoped_link = scope_context(link, organization_id, mission_id)
        resolve_scoped_link(scoped_link, organization_id, mission_id)

      {:error, reason} ->
        {:error,
         inspector(link, :missing, "Cannot resolve data link without #{format_key(reason)}.", [])}
    end
  end

  @spec unsupported?(atom()) :: boolean()
  def unsupported?(target), do: target not in @supported_targets

  @spec missing(binary() | nil) :: inspector()
  def missing(link_id) do
    DataLinkInspector.new(%{
      status: :missing,
      status_text: "missing",
      title: "Data link",
      message: "Data link is no longer present in the current dashboard result.",
      target: :data_link,
      target_text: "data link",
      target_id: link_id,
      link_id: link_id,
      link_label: "Data link",
      source: :warning,
      source_text: "warning",
      rows: [row("Link", link_id)] |> Enum.reject(&is_nil/1),
      context_rows: [],
      source_context: %{},
      related_links: [],
      actions: []
    })
  end

  defp resolve_scoped_link(
         %DataLink{target: :telemetry_point} = link,
         organization_id,
         mission_id
       ),
       do: resolve_telemetry_point(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :telemetry_sample} = link,
         organization_id,
         mission_id
       ),
       do: resolve_telemetry_sample(link, organization_id, mission_id)

  defp resolve_scoped_link(%DataLink{target: :raw_evidence} = link, organization_id, mission_id),
    do: resolve_raw_evidence(link, organization_id, mission_id)

  defp resolve_scoped_link(%DataLink{target: :limit_event} = link, organization_id, mission_id),
    do: LimitTargets.resolve(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :limit_definition} = link,
         organization_id,
         mission_id
       ),
       do: LimitTargets.resolve(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :limit_definition_interval} = link,
         organization_id,
         mission_id
       ),
       do: LimitTargets.resolve(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :limit_definition_lifecycle_event} = link,
         organization_id,
         mission_id
       ),
       do: LimitTargets.resolve(link, organization_id, mission_id)

  defp resolve_scoped_link(%DataLink{target: :mission_event} = link, organization_id, mission_id),
    do: EventTargets.resolve(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :operational_event} = link,
         organization_id,
         mission_id
       ),
       do: EventTargets.resolve(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :command_release_attempt} = link,
         organization_id,
         mission_id
       ),
       do: CommandTargets.resolve(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :command_request} = link,
         organization_id,
         mission_id
       ),
       do: CommandTargets.resolve(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :command_queue_entry} = link,
         organization_id,
         mission_id
       ),
       do: CommandTargets.resolve(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :command_verifier_instance} = link,
         organization_id,
         mission_id
       ),
       do: CommandTargets.resolve(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :transport_capability_record} = link,
         organization_id,
         mission_id
       ),
       do: TransportRuntimeTargets.resolve(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :transport_action_request} = link,
         organization_id,
         mission_id
       ),
       do: TransportRuntimeTargets.resolve(link, organization_id, mission_id)

  defp resolve_scoped_link(%DataLink{target: target} = link, organization_id, mission_id)
       when target in [
              :binding_set_interval,
              :application_binding_interval,
              :catalog_revision_interval,
              :source_binding_interval,
              :source_health_interval,
              :transport_execution_interval,
              :transport_connection_state_interval,
              :ground_station_connection_state_interval,
              :ground_station_antenna_pointing_state_interval,
              :link_rf_lock_state_interval,
              :link_frame_sync_state_interval
            ],
       do: SourceStateTargets.resolve(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :source_health_event} = link,
         organization_id,
         mission_id
       ),
       do: SourceStateTargets.resolve(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :source_watermark_event} = link,
         organization_id,
         mission_id
       ),
       do: SourceStateTargets.resolve(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :source_binding_event} = link,
         organization_id,
         mission_id
       ),
       do: SourceStateTargets.resolve(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :comparison_finding} = link,
         organization_id,
         mission_id
       ),
       do: resolve_comparison_finding(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :telemetry_revision_decision_event} = link,
         organization_id,
         mission_id
       ),
       do: resolve_telemetry_revision_decision_event(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :telemetry_backfill_lifecycle_event} = link,
         organization_id,
         mission_id
       ),
       do: resolve_telemetry_backfill_lifecycle_event(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :dashboard_lifecycle_event} = link,
         organization_id,
         mission_id
       ),
       do: resolve_dashboard_lifecycle_event(link, organization_id, mission_id)

  defp resolve_scoped_link(%DataLink{target: :contact} = link, organization_id, mission_id),
    do: OperationalResourceTargets.resolve(link, organization_id, mission_id)

  defp resolve_scoped_link(%DataLink{target: :transport} = link, organization_id, mission_id),
    do: OperationalResourceTargets.resolve(link, organization_id, mission_id)

  defp resolve_scoped_link(%DataLink{target: :link} = link, organization_id, mission_id),
    do: OperationalResourceTargets.resolve(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :source_endpoint} = link,
         organization_id,
         mission_id
       ),
       do: OperationalResourceTargets.resolve(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :ground_station} = link,
         organization_id,
         mission_id
       ),
       do: OperationalResourceTargets.resolve(link, organization_id, mission_id)

  defp resolve_scoped_link(%DataLink{} = link, _organization_id, _mission_id),
    do: {:error, inspector(link, :unsupported, unsupported_message(link), [])}

  defp resolve_telemetry_point(%DataLink{} = link, organization_id, mission_id) do
    point =
      organization_id
      |> PointCatalog.list_points(mission_id)
      |> Enum.find(&(&1.point_id == link.target_id))

    case point do
      nil ->
        {:ok,
         inspector(
           link,
           :context_only,
           "Telemetry point is not present in the active operator point catalog.",
           [row("Point", link.target_id)]
         )}

      point ->
        {:ok, inspector(link, :resolved, nil, point_rows(point))}
    end
  end

  defp resolve_telemetry_sample(%DataLink{} = link, organization_id, mission_id) do
    sample_row =
      TelemetrySampleRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.sample_id == ^link.target_id
      )
      |> Repo.one()

    case sample_row do
      %TelemetrySampleRow{} = sample_row ->
        sample = TelemetrySampleRow.to_domain(sample_row)

        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           telemetry_sample_rows(sample),
           telemetry_sample_related_links(link, sample, organization_id, mission_id),
           telemetry_actions(link,
             point_id: sample.point_id,
             selected_time: sample.receipt_time,
             source: :data_link_panel
           )
         )}

      nil ->
        {:error, inspector(link, :missing, "Telemetry sample was not found in this mission.", [])}
    end
  end

  defp resolve_raw_evidence(%DataLink{} = link, organization_id, mission_id) do
    evidence_row =
      RawEvidenceRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.evidence_id == ^link.target_id
      )
      |> Repo.one()

    case evidence_row do
      %RawEvidenceRow{} = evidence_row ->
        evidence = RawEvidenceRow.to_domain(evidence_row)

        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           raw_evidence_rows(evidence),
           raw_evidence_related_links(link, evidence, organization_id, mission_id)
         )}

      nil ->
        {:error, inspector(link, :missing, "Raw evidence was not found in this mission.", [])}
    end
  end

  defp resolve_comparison_finding(%DataLink{} = link, organization_id, mission_id) do
    {:ok,
     inspector(
       link,
       :context_only,
       "Comparison finding is derived from the current dashboard runtime context.",
       comparison_finding_rows(link, organization_id, mission_id),
       comparison_finding_related_links(link)
     )}
  end

  defp resolve_telemetry_revision_decision_event(%DataLink{} = link, organization_id, mission_id) do
    link.target_id
    |> TelemetryStorage.fetch_observation_identity_decision_event(
      organization_id: organization_id,
      mission_id: mission_id
    )
    |> case do
      nil ->
        {:error,
         inspector(
           link,
           :missing,
           "Telemetry revision decision event was not found in this mission.",
           []
         )}

      event ->
        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           telemetry_revision_decision_event_rows(event),
           telemetry_revision_decision_event_related_links(link, event)
         )}
    end
  end

  defp resolve_telemetry_backfill_lifecycle_event(%DataLink{} = link, organization_id, mission_id) do
    link.target_id
    |> TelemetryStorage.fetch_backfill_lifecycle_event(
      organization_id: organization_id,
      mission_id: mission_id
    )
    |> case do
      nil ->
        {:error,
         inspector(
           link,
           :missing,
           "Telemetry backfill lifecycle event was not found in this mission.",
           []
         )}

      event ->
        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           BackfillLifecycleRows.rows(event, organization_id, mission_id),
           telemetry_backfill_lifecycle_event_related_links(
             link,
             event,
             organization_id,
             mission_id
           )
         )}
    end
  end

  defp resolve_dashboard_lifecycle_event(%DataLink{} = link, organization_id, mission_id) do
    case Cadence.Dashboards.fetch_lifecycle_event(organization_id, mission_id, link.target_id) do
      {:ok, %LifecycleEvent{} = event} ->
        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           dashboard_lifecycle_event_rows(event),
           dashboard_lifecycle_event_related_links(link, event)
         )}

      {:error, :not_found} ->
        {:error,
         inspector(
           link,
           :missing,
           "Dashboard lifecycle event was not found in this mission.",
           []
         )}
    end
  end

  defp point_rows(point) do
    [
      row("Point", point.point_id),
      row("Packet", Map.get(point, :packet_name)),
      row("Field", Map.get(point, :field_name)),
      row("Unit", Map.get(point, :unit)),
      row("Stale timeout", Map.get(point, :stale_timeout_ms)),
      row("Description", Map.get(point, :description))
    ]
  end

  defp telemetry_sample_rows(sample) do
    [
      row("Sample", sample.sample_id),
      row("Point", sample.point_id),
      row("Spacecraft", sample.spacecraft_id),
      row("Raw", sample.raw_value),
      row("Engineering", sample.engineering_value),
      row("Quality", sample.quality_state),
      row("Generation", sample.generation_time),
      row("Receipt", sample.receipt_time),
      row("Evidence", sample.evidence_id),
      row("Packet", sample.packet_id),
      row("Packet definition", sample.packet_definition_id),
      row("Packet definition version", sample.packet_definition_version)
    ]
  end

  defp raw_evidence_rows(evidence) do
    [
      row("Evidence", evidence.evidence_id),
      row("Spacecraft", evidence.spacecraft_id),
      row("Source endpoint", evidence.source_endpoint_ref),
      row("Protocol", evidence.protocol_family),
      row("Direction", evidence.direction),
      row("Source time", evidence.source_time),
      row("Receipt", evidence.receipt_time),
      row("Source ref", evidence.source_ref),
      row("Raw bytes", byte_size(evidence.raw)),
      row("Raw hex", Base.encode16(evidence.raw, case: :lower)),
      row("Metadata", evidence.metadata)
    ]
  end

  defp comparison_finding_rows(%DataLink{} = link, organization_id, mission_id) do
    comparison = context_value(link.context, :comparison)

    primary_sample =
      comparison_sample(comparison, :primary_sample_id, organization_id, mission_id)

    compare_sample =
      comparison_sample(comparison, :compare_sample_id, organization_id, mission_id)

    primary_storage = sample_storage_provenance(primary_sample)
    compare_storage = sample_storage_provenance(compare_sample)

    [
      row("Comparison finding", link.target_id),
      row("State", state_value(comparison, :state)),
      row("Delta", state_value(comparison, :delta)),
      row("Primary sample", state_value(comparison, :primary_sample_id)),
      row("Compare sample", state_value(comparison, :compare_sample_id)),
      row("Primary data view", state_value(comparison, :primary_data_view)),
      row("Compare data view", state_value(comparison, :compare_data_view)),
      row("Primary data management", state_value(comparison, :primary_data_management)),
      row("Compare data management", state_value(comparison, :compare_data_management)),
      row("Primary count", state_value(comparison, :primary_count)),
      row("Compare count", state_value(comparison, :compare_count)),
      row("Widget", state_value(comparison, :widget_id)),
      row("Widget title", state_value(comparison, :widget_title)),
      row("Observation identity", storage_value(primary_storage, :observation_identity_id)),
      row(
        "Realm",
        storage_value(primary_storage, :realm) ||
          nested_context_value(link.context, :data, :realm)
      ),
      row(
        "Data source",
        storage_value(primary_storage, :data_source_id) ||
          nested_context_value(link.context, :data, :data_source_id)
      ),
      row(
        "Source binding",
        storage_value(primary_storage, :binding_id) ||
          nested_context_value(link.context, :data, :source_binding_id)
      ),
      row(
        "Observable",
        storage_value(primary_storage, :observable_id) ||
          context_value(link.context, :observable_id)
      ),
      row("Point", primary_sample && primary_sample.point_id),
      row("Spacecraft", primary_sample && primary_sample.spacecraft_id),
      row("Decision reason", "dashboard_comparison_finding"),
      row("Correction authority", "comparison"),
      row("Previous canonical observation", storage_value(compare_storage, :observation_id)),
      row("Previous canonical sample", compare_sample && compare_sample.sample_id),
      row("Previous canonical revision", storage_value(compare_storage, :revision)),
      row("Previous validity state", storage_value(compare_storage, :validity_state)),
      row("New canonical observation", storage_value(primary_storage, :observation_id)),
      row("New canonical sample", primary_sample && primary_sample.sample_id),
      row("New canonical revision", storage_value(primary_storage, :revision)),
      row("New validity state", storage_value(primary_storage, :validity_state))
    ]
  end

  defp telemetry_revision_decision_event_rows(event) do
    [
      row("Revision decision event", event.decision_event_id),
      row("Observation identity", event.observation_identity_id),
      row("Decision", event.decision),
      row("Decision reason", event.decision_reason),
      row("Occurred", event.occurred_at),
      row("Realm", event.realm),
      row("Data source", event.data_source_id),
      row("Source binding", event.binding_id),
      row("Observable", event.observable_id),
      row("Point", event.point_id),
      row("Spacecraft", event.spacecraft_id),
      row("Actor", event.actor_id),
      row("Actor kind", event.actor_kind),
      row("Evidence ref", event.evidence_ref),
      row("Source panel", state_value(event.evidence_ref, :source_panel)),
      row("Source target", state_value(event.evidence_ref, :source_target)),
      row("Source target id", state_value(event.evidence_ref, :source_target_id)),
      row("Source link label", state_value(event.evidence_ref, :source_link_label)),
      row("Correction workflow", correction_workflow_value(event.evidence_ref, :id)),
      row("Correction authority", correction_workflow_value(event.evidence_ref, :authority)),
      row(
        "Correction requested by",
        correction_workflow_value(event.evidence_ref, :requested_by)
      ),
      row("Bulk workflow", bulk_workflow_item_value(event.evidence_ref, :workflow_id)),
      row("Bulk workflow item", bulk_workflow_item_value(event.evidence_ref, :item_index)),
      row("Bulk workflow item count", bulk_workflow_item_value(event.evidence_ref, :item_count)),
      row(
        "Bulk workflow observation identity",
        bulk_workflow_item_value(event.evidence_ref, :observation_identity_id)
      ),
      row(
        "Bulk workflow selection",
        bulk_workflow_item_value(event.evidence_ref, :selection_kind)
      ),
      row("Comparison finding", comparison_finding_value(event.evidence_ref, :placement_id)),
      row("Comparison state", comparison_finding_value(event.evidence_ref, :state)),
      row("Comparison delta", comparison_finding_value(event.evidence_ref, :delta)),
      row(
        "Comparison primary sample",
        comparison_finding_value(event.evidence_ref, :primary_sample_id)
      ),
      row(
        "Comparison compare sample",
        comparison_finding_value(event.evidence_ref, :compare_sample_id)
      ),
      row(
        "Comparison primary data view",
        comparison_finding_value(event.evidence_ref, :primary_data_view)
      ),
      row(
        "Comparison compare data view",
        comparison_finding_value(event.evidence_ref, :compare_data_view)
      ),
      row(
        "Comparison primary data management",
        comparison_finding_value(event.evidence_ref, :primary_data_management)
      ),
      row(
        "Comparison compare data management",
        comparison_finding_value(event.evidence_ref, :compare_data_management)
      ),
      row("Comparison widget", comparison_finding_value(event.evidence_ref, :widget_id)),
      row("Comparison widget title", comparison_finding_value(event.evidence_ref, :widget_title)),
      row("Previous validity state", state_value(event.previous_state, :validity_state)),
      row("New validity state", state_value(event.new_state, :validity_state)),
      row(
        "Previous canonical observation",
        state_value(event.previous_state, :canonical_observation_id)
      ),
      row("New canonical observation", state_value(event.new_state, :canonical_observation_id)),
      row("Previous canonical sample", state_value(event.previous_state, :canonical_sample_id)),
      row("New canonical sample", state_value(event.new_state, :canonical_sample_id)),
      row("Previous canonical revision", state_value(event.previous_state, :canonical_revision)),
      row("New canonical revision", state_value(event.new_state, :canonical_revision))
    ]
  end

  defp dashboard_lifecycle_event_rows(%LifecycleEvent{} = event) do
    [
      row("Dashboard lifecycle event", event.dashboard_lifecycle_event_id),
      row("Dashboard", event.dashboard_id),
      row("Event type", event.event_type),
      row("Dashboard version", event.dashboard_version),
      row("Previous lifecycle state", event.previous_lifecycle_state),
      row("Current lifecycle state", event.current_lifecycle_state),
      row("Previous published version", event.previous_published_version),
      row("Current published version", event.current_published_version),
      row("Actor", event.actor_id),
      row("Occurred", event.occurred_at),
      row("Payload schema", state_value(event.payload, :schema)),
      row("Comparison review kind", comparison_review_request_kind(event.payload)),
      row("Comparison review open count", state_value(event.payload, :open_count)),
      row("Comparison review placements", state_value(event.payload, :open_placement_ids)),
      row(
        "Comparison review source request",
        state_value(event.payload, :source_request_event_id)
      ),
      row(
        "Comparison review source actionable count",
        state_value(event.payload, :source_actionable_count)
      ),
      row(
        "Comparison review source skipped count",
        state_value(event.payload, :source_skipped_count)
      )
    ]
  end

  defp correction_workflow_value(evidence_ref, key) do
    evidence_ref
    |> state_value(:correction_workflow)
    |> state_value(key)
  end

  defp comparison_finding_value(evidence_ref, key) do
    evidence_ref
    |> state_value(:comparison_finding)
    |> state_value(key)
  end

  defp bulk_workflow_item_value(evidence_ref, key) do
    evidence_ref
    |> state_value(:bulk_workflow_item)
    |> state_value(key)
  end

  defp backfill_lifecycle_payload_value(payload, key), do: state_value(payload, key)

  defp comparison_review_origin_value(payload, key) do
    payload
    |> state_value(:comparison_review_origin)
    |> state_value(key)
  end

  defp comparison_review_request_kind(payload) do
    state_value(payload, :review_kind) || state_value(payload, :request_kind)
  end

  defp telemetry_sample_related_links(%DataLink{} = link, sample, organization_id, mission_id) do
    [
      related_link(link, :telemetry_point, sample.point_id, "Telemetry point"),
      related_link(link, :raw_evidence, sample.evidence_id, "Raw evidence")
      | sample_limit_event_links(link, sample, organization_id, mission_id)
    ]
  end

  defp sample_limit_event_links(%DataLink{} = link, sample, organization_id, mission_id) do
    organization_id
    |> Limits.list_limit_events_for_sample(
      mission_id,
      sample.sample_id,
      source_sample_type: :telemetry_sample,
      limit: 5
    )
    |> Enum.map(fn event ->
      related_link(link, :limit_event, event.limit_event_id, "Limit event")
    end)
  end

  defp raw_evidence_related_links(%DataLink{} = link, evidence, organization_id, mission_id) do
    TelemetrySampleRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.evidence_id == ^evidence.evidence_id
    )
    |> order_by([row], desc: row.receipt_time)
    |> limit(5)
    |> Repo.all()
    |> Enum.map(fn sample_row ->
      sample = TelemetrySampleRow.to_domain(sample_row)
      related_link(link, :telemetry_sample, sample.sample_id, "Telemetry sample")
    end)
  end

  defp comparison_finding_related_links(%DataLink{} = link) do
    comparison = context_value(link.context, :comparison)

    [
      comparison_sample_link(link, :primary_sample_id, "Primary telemetry sample"),
      comparison_sample_link(link, :compare_sample_id, "Compare telemetry sample")
    ]
    |> Enum.map(fn
      {%DataLink{} = related_link, key} ->
        sample_context =
          link.context
          |> context_value(:data)
          |> put_sample_view(state_value(comparison, sample_view_key(key)))

        %DataLink{
          related_link
          | context:
              link.context
              |> Map.put(:data, sample_context)
              |> Map.delete(:comparison)
        }

      other ->
        other
    end)
  end

  defp comparison_sample(comparison, key, organization_id, mission_id) do
    case state_value(comparison, key) do
      sample_id when is_binary(sample_id) and sample_id != "" ->
        TelemetrySampleRow
        |> where(
          [row],
          row.organization_id == ^organization_id and row.mission_id == ^mission_id and
            row.sample_id == ^sample_id
        )
        |> Repo.one()
        |> case do
          %TelemetrySampleRow{} = sample_row -> TelemetrySampleRow.to_domain(sample_row)
          nil -> nil
        end

      _missing ->
        nil
    end
  end

  defp sample_storage_provenance(%{provenance: provenance}) when is_map(provenance) do
    context_value(provenance, :storage) || %{}
  end

  defp sample_storage_provenance(_sample), do: %{}

  defp storage_value(storage, key), do: context_value(storage, key)

  defp comparison_sample_link(%DataLink{} = link, key, label) do
    comparison = context_value(link.context, :comparison)

    case state_value(comparison, key) do
      sample_id when is_binary(sample_id) and sample_id != "" ->
        {%DataLink{
           link
           | link_id: "comparison:#{link.target_id}:#{key}:#{sample_id}",
             label: label,
             target: :telemetry_sample,
             target_id: sample_id,
             source: :annotation
         }, key}

      _missing ->
        nil
    end
  end

  defp sample_view_key(:primary_sample_id), do: :primary_data_view
  defp sample_view_key(:compare_sample_id), do: :compare_data_view

  defp put_sample_view(data_context, view) when is_map(data_context) and is_binary(view),
    do: Map.put(data_context, :view, view)

  defp put_sample_view(data_context, _view) when is_map(data_context), do: data_context
  defp put_sample_view(_data_context, view) when is_binary(view), do: %{view: view}
  defp put_sample_view(_data_context, _view), do: %{}

  defp telemetry_revision_decision_event_related_links(%DataLink{} = link, event) do
    [
      related_link(
        link,
        :telemetry_point,
        event.point_id || event.observable_id,
        "Telemetry point",
        :evidence
      ),
      related_link(
        link,
        :telemetry_sample,
        state_value(event.previous_state, :canonical_sample_id),
        "Previous canonical sample"
      ),
      related_link(
        link,
        :telemetry_sample,
        state_value(event.new_state, :canonical_sample_id),
        "New canonical sample"
      ),
      telemetry_revision_decision_event_correction_workflow_link(link, event)
    ]
  end

  defp telemetry_revision_decision_event_correction_workflow_link(%DataLink{} = link, event) do
    requested_by = correction_workflow_value(event.evidence_ref, :requested_by)

    if requested_by == "dashboard_comparison_review" do
      related_link(
        link,
        :dashboard_lifecycle_event,
        correction_workflow_value(event.evidence_ref, :id) ||
          bulk_workflow_item_value(event.evidence_ref, :workflow_id),
        "Comparison review request",
        :comparison_review_origin
      )
    end
  end

  defp telemetry_backfill_lifecycle_event_related_links(
         %DataLink{} = link,
         event,
         organization_id,
         mission_id
       ) do
    [
      related_link(
        link,
        :telemetry_point,
        event.point_id || event.observable_id,
        "Telemetry point"
      ),
      telemetry_backfill_lifecycle_late_data_source_link(link, event),
      telemetry_backfill_lifecycle_retry_source_link(link, event),
      telemetry_backfill_lifecycle_correction_source_link(link, event),
      telemetry_backfill_lifecycle_comparison_review_origin_link(link, event)
    ] ++
      telemetry_backfill_lifecycle_group_failure_links(link, event, organization_id, mission_id) ++
      telemetry_backfill_lifecycle_referencing_event_links(
        link,
        event,
        organization_id,
        mission_id
      )
  end

  defp telemetry_backfill_lifecycle_retry_source_link(%DataLink{} = link, event) do
    related_link(
      link,
      :telemetry_backfill_lifecycle_event,
      backfill_lifecycle_payload_value(event.payload, :retry_source_event_id),
      "Retry source event",
      :source_event
    )
  end

  defp telemetry_backfill_lifecycle_late_data_source_link(%DataLink{} = link, event) do
    related_link(
      link,
      :telemetry_backfill_lifecycle_event,
      backfill_lifecycle_payload_value(event.payload, :source_event_id),
      "Late data source event",
      :source_event
    )
  end

  defp telemetry_backfill_lifecycle_correction_source_link(%DataLink{} = link, event) do
    related_link(
      link,
      :telemetry_backfill_lifecycle_event,
      backfill_lifecycle_payload_value(event.payload, :corrects_event_id),
      "Correction source event",
      :source_event
    )
  end

  defp telemetry_backfill_lifecycle_comparison_review_origin_link(%DataLink{} = link, event) do
    related_link(
      link,
      :dashboard_lifecycle_event,
      comparison_review_origin_value(event.payload, :request_event_id),
      "Comparison review request",
      :comparison_review_origin
    )
  end

  defp dashboard_lifecycle_event_related_links(%DataLink{} = link, %LifecycleEvent{} = event) do
    [
      related_link(
        link,
        :dashboard_lifecycle_event,
        state_value(event.payload, :source_request_event_id),
        "Source comparison review request",
        :source_event
      )
    ]
  end

  defp telemetry_backfill_lifecycle_referencing_event_links(
         %DataLink{} = link,
         event,
         organization_id,
         mission_id
       ) do
    mission_id
    |> TelemetryStorage.list_backfill_lifecycle_events(
      organization_id: organization_id,
      limit: 1_000
    )
    |> Enum.reject(&(&1.backfill_lifecycle_event_id == event.backfill_lifecycle_event_id))
    |> Enum.flat_map(fn related_event ->
      related_event
      |> telemetry_backfill_lifecycle_reference_links(event.backfill_lifecycle_event_id)
      |> Enum.map(fn {label, relationship_kind} ->
        related_link(
          link,
          :telemetry_backfill_lifecycle_event,
          related_event.backfill_lifecycle_event_id,
          label,
          relationship_kind
        )
      end)
    end)
  end

  defp telemetry_backfill_lifecycle_reference_links(related_event, source_event_id) do
    [
      telemetry_backfill_lifecycle_reference_link(
        related_event,
        source_event_id,
        :retry_source_event_id,
        "Retry event",
        :retry_event
      ),
      telemetry_backfill_lifecycle_reference_link(
        related_event,
        source_event_id,
        :corrects_event_id,
        telemetry_backfill_lifecycle_correction_reference_label(related_event),
        telemetry_backfill_lifecycle_correction_reference_kind(related_event)
      ),
      telemetry_backfill_lifecycle_reference_link(
        related_event,
        source_event_id,
        :correction_transition_source_event_id,
        "Correction transition event",
        :correction_transition
      ),
      telemetry_backfill_lifecycle_reference_link(
        related_event,
        source_event_id,
        :source_event_id,
        telemetry_backfill_lifecycle_source_reference_label(related_event),
        telemetry_backfill_lifecycle_source_reference_kind(related_event)
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp telemetry_backfill_lifecycle_reference_link(
         related_event,
         source_event_id,
         payload_key,
         label,
         relationship_kind
       ) do
    case backfill_lifecycle_payload_value(related_event.payload, payload_key) do
      ^source_event_id ->
        {"#{label} #{telemetry_backfill_lifecycle_reference_text(related_event)}",
         relationship_kind}

      _other ->
        nil
    end
  end

  defp telemetry_backfill_lifecycle_source_reference_label(related_event) do
    cond do
      backfill_lifecycle_payload_value(related_event.payload, :kind) ==
          "late_data_policy_decision" ->
        "Late data policy event"

      backfill_lifecycle_payload_value(related_event.payload, :stage_transition_source) ->
        "Stage transition event"

      true ->
        "Follow-up event"
    end
  end

  defp telemetry_backfill_lifecycle_source_reference_kind(related_event) do
    cond do
      backfill_lifecycle_payload_value(related_event.payload, :kind) ==
          "late_data_policy_decision" ->
        :late_data_policy_event

      backfill_lifecycle_payload_value(related_event.payload, :stage_transition_source) ->
        :stage_transition_event

      true ->
        :follow_up_event
    end
  end

  defp telemetry_backfill_lifecycle_correction_reference_label(related_event) do
    case backfill_lifecycle_payload_value(
           related_event.payload,
           :correction_transition_source_event_id
         ) do
      source_event_id when is_binary(source_event_id) and source_event_id != "" ->
        "Correction transition event"

      _other ->
        "Correction request"
    end
  end

  defp telemetry_backfill_lifecycle_correction_reference_kind(related_event) do
    case backfill_lifecycle_payload_value(
           related_event.payload,
           :correction_transition_source_event_id
         ) do
      source_event_id when is_binary(source_event_id) and source_event_id != "" ->
        :correction_transition

      _other ->
        :correction_request
    end
  end

  defp telemetry_backfill_lifecycle_reference_text(related_event) do
    related_event.point_id || related_event.observable_id ||
      backfill_lifecycle_payload_value(related_event.payload, :stage) ||
      related_event.backfill_run_id ||
      related_event.backfill_lifecycle_event_id
  end

  defp telemetry_backfill_lifecycle_group_failure_links(
         %DataLink{} = link,
         event,
         organization_id,
         mission_id
       ) do
    case backfill_lifecycle_payload_value(event.payload, :request_group_id) do
      group_id when is_binary(group_id) and group_id != "" ->
        mission_id
        |> TelemetryStorage.list_backfill_lifecycle_events(
          organization_id: organization_id,
          event_type: :backfill_failed,
          limit: 1_000
        )
        |> Enum.filter(
          &(backfill_lifecycle_payload_value(&1.payload, :request_group_id) == group_id)
        )
        |> Enum.sort_by(&backfill_lifecycle_failed_group_link_sort_key/1)
        |> Enum.map(fn failed_event ->
          failed_item_label =
            failed_event.point_id || failed_event.observable_id || failed_event.backfill_run_id

          related_link(
            link,
            :telemetry_backfill_lifecycle_event,
            failed_event.backfill_lifecycle_event_id,
            "Failed item #{failed_item_label}"
          )
        end)

      _other ->
        []
    end
  end

  defp backfill_lifecycle_failed_group_link_sort_key(event) do
    {backfill_lifecycle_payload_value(event.payload, :request_item_index) || 0,
     event.backfill_run_id}
  end

  defp scope_context(%DataLink{} = link, organization_id, mission_id) do
    context =
      link.context
      |> context_map()
      |> Map.put(:organization_id, organization_id)
      |> Map.put(:mission_id, mission_id)

    %DataLink{link | context: context}
  end

  defp context_map(context) when is_map(context), do: context
  defp context_map(_context), do: %{}

  defp required_scope(opts) do
    organization_id = Keyword.get(opts, :organization_id)
    mission_id = Keyword.get(opts, :mission_id)

    cond do
      not valid_id?(organization_id) -> {:error, :organization_id}
      not valid_id?(mission_id) -> {:error, :mission_id}
      true -> {:ok, organization_id, mission_id}
    end
  end

  defp valid_id?(value), do: is_binary(value) and value != ""

  defp unsupported_message(%DataLink{} = link) do
    "Dashboard data-link target #{target_text(link.target)} is not supported by the inspector yet."
  end

  defp format_key(key) do
    key
    |> Atom.to_string()
    |> String.replace("_", " ")
  end
end
