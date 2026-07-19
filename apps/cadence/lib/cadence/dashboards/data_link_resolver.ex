defmodule Cadence.Dashboards.DataLinkResolver do
  @moduledoc """
  Resolves typed dashboard data links into inspector payloads.

  This is the boundary between a dashboard's runtime data-link contract and the
  persisted records behind it.
  """

  import Ecto.Query

  alias Cadence.Comms.{
    GroundStation,
    GroundStationStore,
    RoutingRule,
    RoutingRuleStore,
    Transport,
    TransportStore
  }

  alias Cadence.Contacts
  alias Cadence.Contacts.{LinkAssignment, RealizedContact, ScheduledContact}

  alias Cadence.Dashboards.{
    DashboardAction,
    DataBindingInterval,
    DataLink,
    DataLinkInspector,
    DataSources,
    LifecycleEvent,
    TelemetryActions
  }

  alias Cadence.Dashboards.DataSources.DataBindingEventRow
  alias Cadence.Jobs
  alias Cadence.Limits
  alias Cadence.Limits.{DefinitionInterval, DefinitionLifecycle}
  alias Cadence.OperationalEvents
  alias Cadence.OperationalEvents.EffectiveInterval
  alias Cadence.Ops.PointCatalog
  alias Cadence.Projections.MissionEvents, as: MissionEventProjection
  alias Cadence.SourceEndpoints
  alias Cadence.SourceEndpoints.SourceEndpoint

  alias Cadence.Persistence.Schemas.{
    CommandQueueEntryRow,
    CommandReleaseAttemptRow,
    CommandRequestRow,
    CommandVerifierInstanceRow,
    DashboardSourceHealthEventRow,
    DashboardSourceWatermarkEventRow,
    MissionEventRow,
    OperationalEventRow,
    RawEvidenceRow,
    RealizedContactRow,
    ScheduledContactRow,
    TelemetryLimitEventRow,
    TelemetrySampleRow
  }

  alias Cadence.Repo
  alias Cadence.Telemetry.Storage, as: TelemetryStorage
  alias Cadence.Telemetry.Storage.BackfillLifecycleGroup

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
    do: resolve_limit_event(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :limit_definition} = link,
         organization_id,
         mission_id
       ),
       do: resolve_limit_definition(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :limit_definition_interval} = link,
         organization_id,
         mission_id
       ),
       do: resolve_limit_definition_interval(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :limit_definition_lifecycle_event} = link,
         organization_id,
         mission_id
       ),
       do: resolve_limit_definition_lifecycle_event(link, organization_id, mission_id)

  defp resolve_scoped_link(%DataLink{target: :mission_event} = link, organization_id, mission_id),
    do: resolve_mission_event(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :operational_event} = link,
         organization_id,
         mission_id
       ),
       do: resolve_operational_event(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :command_release_attempt} = link,
         organization_id,
         mission_id
       ),
       do: resolve_command_release_attempt(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :command_request} = link,
         organization_id,
         mission_id
       ),
       do: resolve_command_request(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :command_queue_entry} = link,
         organization_id,
         mission_id
       ),
       do: resolve_command_queue_entry(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :command_verifier_instance} = link,
         organization_id,
         mission_id
       ),
       do: resolve_command_verifier_instance(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :transport_capability_record} = link,
         organization_id,
         mission_id
       ),
       do: resolve_transport_capability_record(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :transport_action_request} = link,
         organization_id,
         mission_id
       ),
       do: resolve_transport_action_request(link, organization_id, mission_id)

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
       do: resolve_effective_interval(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :source_health_event} = link,
         organization_id,
         mission_id
       ),
       do: resolve_source_health_event(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :source_watermark_event} = link,
         organization_id,
         mission_id
       ),
       do: resolve_source_watermark_event(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :source_binding_event} = link,
         organization_id,
         mission_id
       ),
       do: resolve_source_binding_event(link, organization_id, mission_id)

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
    do: resolve_contact(link, organization_id, mission_id)

  defp resolve_scoped_link(%DataLink{target: :transport} = link, organization_id, mission_id),
    do: resolve_transport(link, organization_id, mission_id)

  defp resolve_scoped_link(%DataLink{target: :link} = link, organization_id, mission_id),
    do: resolve_link(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :source_endpoint} = link,
         organization_id,
         mission_id
       ),
       do: resolve_source_endpoint(link, organization_id, mission_id)

  defp resolve_scoped_link(
         %DataLink{target: :ground_station} = link,
         organization_id,
         mission_id
       ),
       do: resolve_ground_station(link, organization_id, mission_id)

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

  defp resolve_limit_event(%DataLink{} = link, organization_id, mission_id) do
    event_row =
      TelemetryLimitEventRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.limit_event_id == ^link.target_id
      )
      |> Repo.one()

    case event_row do
      %TelemetryLimitEventRow{} = event_row ->
        event = TelemetryLimitEventRow.to_domain(event_row)

        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           limit_event_rows(event),
           limit_event_related_links(link, event)
         )}

      nil ->
        {:error, inspector(link, :missing, "Limit event was not found in this mission.", [])}
    end
  end

  defp resolve_limit_definition(%DataLink{} = link, organization_id, mission_id) do
    case Limits.fetch_latest_limit_definition(organization_id, mission_id, link.target_id) do
      {:ok, definition} ->
        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           limit_definition_rows(definition),
           limit_definition_related_links(link, definition)
         )}

      {:error, :limit_definition_not_found} ->
        {:error, inspector(link, :missing, "Limit definition was not found in this mission.", [])}
    end
  end

  defp resolve_limit_definition_interval(%DataLink{} = link, organization_id, mission_id) do
    with activation_key when is_binary(activation_key) <-
           limit_definition_interval_activation_key(link.target_id),
         {:ok, event} <-
           DefinitionLifecycle.fetch_latest_definition_lifecycle_event(
             organization_id,
             mission_id,
             activation_key,
             include_unscoped?: true
           ) do
      definition = fetch_limit_definition_for_interval(event, organization_id, mission_id)
      interval = DefinitionInterval.from_event(event, event.active_to, definition)

      {:ok,
       inspector(
         link,
         :resolved,
         nil,
         limit_definition_interval_rows(link.target_id, interval),
         limit_definition_interval_related_links(link, interval)
       )}
    else
      _missing ->
        {:error,
         inspector(link, :missing, "Limit definition interval was not found in this mission.", [])}
    end
  end

  defp resolve_limit_definition_lifecycle_event(
         %DataLink{} = link,
         organization_id,
         mission_id
       ) do
    case DefinitionLifecycle.fetch_definition_lifecycle_event(
           organization_id,
           mission_id,
           link.target_id,
           include_unscoped?: true
         ) do
      {:ok, event} ->
        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           limit_definition_lifecycle_event_rows(event),
           limit_definition_lifecycle_event_related_links(link, event)
         )}

      {:error, :limit_definition_lifecycle_event_not_found} ->
        {:error,
         inspector(
           link,
           :missing,
           "Limit definition lifecycle event was not found in this mission.",
           []
         )}
    end
  end

  defp resolve_mission_event(%DataLink{} = link, organization_id, mission_id) do
    event_row =
      MissionEventRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.mission_event_id == ^link.target_id
      )
      |> Repo.one()

    case event_row do
      %MissionEventRow{} = event_row ->
        event = MissionEventRow.to_domain(event_row)

        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           mission_event_rows(event),
           mission_event_related_links(link, event)
         )}

      nil ->
        resolve_projected_mission_event(link, organization_id, mission_id)
    end
  end

  defp resolve_projected_mission_event(
         %DataLink{target_id: "mission_event:" <> operational_event_id} = link,
         organization_id,
         mission_id
       ) do
    event_row =
      OperationalEventRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.event_id == ^operational_event_id
      )
      |> Repo.one()

    case event_row do
      %OperationalEventRow{} = event_row ->
        event = OperationalEventRow.to_domain(event_row)

        event
        |> MissionEventProjection.project()
        |> Enum.find(&(&1.mission_event_id == link.target_id))
        |> case do
          nil ->
            {:error,
             inspector(link, :missing, "Mission event was not found in this mission.", [])}

          projected_event ->
            {:ok,
             inspector(
               link,
               :resolved,
               nil,
               mission_event_rows(projected_event),
               mission_event_related_links(link, projected_event)
             )}
        end

      nil ->
        {:error, inspector(link, :missing, "Mission event was not found in this mission.", [])}
    end
  end

  defp resolve_projected_mission_event(%DataLink{} = link, _organization_id, _mission_id),
    do: {:error, inspector(link, :missing, "Mission event was not found in this mission.", [])}

  defp resolve_operational_event(%DataLink{} = link, organization_id, mission_id) do
    event_row =
      OperationalEventRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.event_id == ^link.target_id
      )
      |> Repo.one()

    case event_row do
      %OperationalEventRow{} = event_row ->
        event = OperationalEventRow.to_domain(event_row)

        {:ok, inspector(link, :resolved, nil, operational_event_rows(event))}

      nil ->
        {:error,
         inspector(link, :missing, "Operational event was not found in this mission.", [])}
    end
  end

  defp resolve_command_verifier_instance(%DataLink{} = link, organization_id, mission_id) do
    verifier_row =
      CommandVerifierInstanceRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.command_verifier_instance_id == ^link.target_id
      )
      |> Repo.one()

    case verifier_row do
      %CommandVerifierInstanceRow{} = verifier_row ->
        verifier_instance = CommandVerifierInstanceRow.to_domain(verifier_row)

        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           command_verifier_instance_rows(verifier_instance),
           command_verifier_instance_related_links(link, verifier_instance)
         )}

      nil ->
        {:error,
         inspector(
           link,
           :missing,
           "Command verifier instance was not found in this mission.",
           []
         )}
    end
  end

  defp resolve_transport_capability_record(%DataLink{} = link, organization_id, mission_id) do
    event_row =
      OperationalEventRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.source_record_kind == "transport_capability_record" and
          row.source_record_id == ^link.target_id
      )
      |> order_by([row], asc: row.occurred_at, asc: row.event_id)
      |> limit(1)
      |> Repo.one()

    case event_row do
      %OperationalEventRow{} = event_row ->
        event = OperationalEventRow.to_domain(event_row)

        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           transport_capability_record_rows(event),
           [related_link(link, :operational_event, event.event_id, "Operational event")]
         )}

      nil ->
        {:error,
         inspector(
           link,
           :missing,
           "Transport capability record was not found in this mission.",
           []
         )}
    end
  end

  defp resolve_transport_action_request(%DataLink{} = link, organization_id, mission_id) do
    event_row =
      OperationalEventRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.source_record_kind == "transport_action_request" and
          row.source_record_id == ^link.target_id
      )
      |> order_by([row], asc: row.occurred_at, asc: row.event_id)
      |> limit(1)
      |> Repo.one()

    case event_row do
      %OperationalEventRow{} = event_row ->
        event = OperationalEventRow.to_domain(event_row)

        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           transport_action_request_rows(event),
           [related_link(link, :operational_event, event.event_id, "Operational event")]
         )}

      nil ->
        {:error,
         inspector(
           link,
           :missing,
           "Transport action request was not found in this mission.",
           []
         )}
    end
  end

  defp resolve_effective_interval(
         %DataLink{target: :source_binding_interval} = link,
         organization_id,
         mission_id
       ) do
    case find_effective_interval(link, organization_id, mission_id) do
      %EffectiveInterval{} = interval ->
        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           effective_interval_rows(interval),
           effective_interval_related_links(link, interval)
         )}

      nil ->
        resolve_source_binding_data_interval(link, organization_id, mission_id)
    end
  end

  defp resolve_effective_interval(%DataLink{} = link, organization_id, mission_id) do
    case find_effective_interval(link, organization_id, mission_id) do
      %EffectiveInterval{} = interval ->
        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           effective_interval_rows(interval),
           effective_interval_related_links(link, interval)
         )}

      nil ->
        {:error,
         inspector(link, :missing, "Operational interval was not found in this mission.", [])}
    end
  end

  defp resolve_source_binding_data_interval(%DataLink{} = link, organization_id, mission_id) do
    case find_source_binding_data_interval(link.target_id, organization_id, mission_id) do
      %DataBindingInterval{} = interval ->
        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           source_binding_data_interval_rows(link.target_id, interval),
           source_binding_data_interval_related_links(link, interval)
         )}

      nil ->
        {:error,
         inspector(link, :missing, "Source binding interval was not found in this mission.", [])}
    end
  end

  defp resolve_source_health_event(%DataLink{} = link, organization_id, mission_id) do
    event_row =
      DashboardSourceHealthEventRow
      |> where(
        [row],
        (is_nil(row.organization_id) or row.organization_id == ^organization_id) and
          row.mission_id == ^mission_id and
          row.source_health_event_id == ^link.target_id
      )
      |> Repo.one()

    case event_row do
      %DashboardSourceHealthEventRow{} = row ->
        event = DashboardSourceHealthEventRow.to_domain(row)
        {:ok, inspector(link, :resolved, nil, source_health_event_rows(event))}

      nil ->
        {:error,
         inspector(link, :missing, "Source health event was not found in this mission.", [])}
    end
  end

  defp resolve_source_watermark_event(%DataLink{} = link, organization_id, mission_id) do
    event_row =
      DashboardSourceWatermarkEventRow
      |> where(
        [row],
        (is_nil(row.organization_id) or row.organization_id == ^organization_id) and
          row.mission_id == ^mission_id and
          row.source_watermark_event_id == ^link.target_id
      )
      |> Repo.one()

    case event_row do
      %DashboardSourceWatermarkEventRow{} = row ->
        event = DashboardSourceWatermarkEventRow.to_domain(row)
        {:ok, inspector(link, :resolved, nil, source_watermark_event_rows(event))}

      nil ->
        {:error,
         inspector(link, :missing, "Source watermark event was not found in this mission.", [])}
    end
  end

  defp resolve_source_binding_event(%DataLink{} = link, organization_id, mission_id) do
    event_row =
      DataBindingEventRow
      |> where(
        [row],
        (is_nil(row.organization_id) or row.organization_id == ^organization_id) and
          row.mission_id == ^mission_id and row.data_binding_event_id == ^link.target_id
      )
      |> Repo.one()

    case event_row do
      %DataBindingEventRow{} = event_row ->
        event = DataBindingEventRow.to_domain(event_row)

        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           source_binding_event_rows(event),
           source_binding_event_related_links(link, event)
         )}

      nil ->
        {:error,
         inspector(link, :missing, "Source binding event was not found in this mission.", [])}
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
           telemetry_backfill_lifecycle_event_rows(event, organization_id, mission_id),
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

  defp resolve_contact(%DataLink{} = link, organization_id, mission_id) do
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

  defp resolve_transport(%DataLink{} = link, organization_id, mission_id) do
    case TransportStore.fetch_transport(organization_id, mission_id, link.target_id) do
      {:ok, %Transport{} = transport} ->
        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           transport_rows(transport),
           operational_resource_related_links(link, transport),
           operational_resource_actions(link)
         )}

      {:error, _reason} ->
        {:error,
         inspector(
           link,
           :missing,
           "Transport was not found in this mission.",
           [],
           operational_resource_related_links(link),
           operational_resource_actions(link)
         )}
    end
  end

  defp resolve_link(%DataLink{} = link, organization_id, mission_id) do
    case Contacts.fetch_link_assignment(organization_id, mission_id, link.target_id) do
      {:ok, %LinkAssignment{} = assignment} ->
        routing_rule = routing_rule_for_link_assignment(organization_id, mission_id, assignment)
        resource = link_assignment_resource(assignment, routing_rule)

        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           link_assignment_rows(assignment, routing_rule),
           operational_resource_related_links(link, resource),
           operational_resource_actions(link, resource) ++ routing_rule_actions(routing_rule)
         )}

      {:error, _reason} ->
        {:error,
         inspector(
           link,
           :missing,
           "Link assignment was not found in this mission.",
           [],
           operational_resource_related_links(link),
           operational_resource_actions(link)
         )}
    end
  end

  defp resolve_source_endpoint(%DataLink{} = link, organization_id, mission_id) do
    case SourceEndpoints.fetch_source_endpoint(organization_id, mission_id, link.target_id) do
      {:ok, %SourceEndpoint{} = source_endpoint} ->
        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           source_endpoint_rows(source_endpoint),
           operational_resource_related_links(link, source_endpoint),
           operational_resource_actions(link)
         )}

      {:error, _reason} ->
        {:error,
         inspector(
           link,
           :missing,
           "Source endpoint was not found in this mission.",
           [],
           operational_resource_related_links(link),
           operational_resource_actions(link)
         )}
    end
  end

  defp resolve_ground_station(%DataLink{} = link, organization_id, mission_id) do
    case GroundStationStore.fetch_ground_station(organization_id, mission_id, link.target_id) do
      {:ok, %GroundStation{} = ground_station} ->
        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           ground_station_rows(ground_station),
           operational_resource_related_links(link, ground_station),
           operational_resource_actions(link)
         )}

      {:error, _reason} ->
        {:ok,
         inspector(
           link,
           :context_only,
           "Ground station was not found as setup state; using transport/source-endpoint metadata context.",
           ground_station_rows(link),
           operational_resource_related_links(link),
           operational_resource_actions(link)
         )}
    end
  end

  defp inspector(%DataLink{} = link, status, message, rows, related_links \\ [], actions \\ nil) do
    DataLinkInspector.new(%{
      status: status,
      status_text: Atom.to_string(status),
      title: title(link),
      message: message,
      target: link.target,
      target_text: target_text(link.target),
      target_id: link.target_id,
      link_id: link.link_id,
      link_label: link.label,
      source: link.source,
      source_text: target_text(link.source),
      source_context: source_context(link.context),
      rows: rows |> Enum.reject(&is_nil/1),
      context_rows: context_rows(link.context),
      navigation: navigation_context(link.context),
      related_links: related_links |> Enum.reject(&is_nil/1) |> dedupe_related_links(),
      actions: actions || telemetry_actions(link, source: :data_link_panel)
    })
  end

  defp telemetry_actions(%DataLink{} = link, opts) do
    link
    |> TelemetryActions.explore_action_from_data_link(opts)
    |> List.wrap()
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

  defp limit_event_rows(event) do
    [
      row("Limit event", event.limit_event_id),
      row("Point", event.point_id),
      row("Spacecraft", event.spacecraft_id),
      row("Sample", event.sample_id),
      row("Definition", event.limit_definition_id),
      row("Definition version", event.limit_definition_version),
      row("Limit set", event.limit_set_name),
      row("Evaluated", event.evaluated_value),
      row("Limit state", event.limit_state),
      row("Normalized state", event.normalized_state),
      row("Violation", event.violation),
      row("Generation", event.generation_time),
      row("Receipt", event.receipt_time)
    ]
  end

  defp limit_definition_rows(definition) do
    [
      row("Definition", definition.limit_definition_id),
      row("Point", definition.point_id),
      row("Version", definition.version),
      row("Limit set", definition.limit_set_name),
      row("Thresholds", definition.thresholds),
      row("Metadata", definition.metadata)
    ]
  end

  defp limit_definition_lifecycle_event_rows(event) do
    [
      row("Limit definition lifecycle event", event.limit_definition_lifecycle_event_id),
      row("Definition activation", event.definition_activation_key),
      row("Point", event.point_id),
      row("Limit set", event.limit_set_name),
      row("Scope type", event.scope_type),
      row("Scope ref", event.scope_ref),
      row("Realm", event.realm),
      row("Event type", event.event_type),
      row("Limit definition", event.limit_definition_id),
      row("Limit definition version", event.limit_definition_version),
      row("Previous limit definition", event.previous_limit_definition_id),
      row("Previous limit definition version", event.previous_limit_definition_version),
      row("Active from", event.active_from),
      row("Active to", event.active_to),
      row("Reason", event.reason),
      row("Observed", event.observed_at),
      row("Payload", event.payload)
    ]
  end

  defp limit_definition_interval_rows(interval_id, %DefinitionInterval{} = interval) do
    [
      row("Limit definition interval", interval_id),
      row("Definition activation", interval.definition_activation_key),
      row("Lifecycle event", interval.limit_definition_lifecycle_event_id),
      row("Point", interval.point_id),
      row("Limit set", interval.limit_set_name),
      row("Scope type", interval.scope_type),
      row("Scope ref", interval.scope_ref),
      row("Realm", interval.realm),
      row("Event type", interval.event_type),
      row("Limit definition", interval.limit_definition_id),
      row("Limit definition version", interval.limit_definition_version),
      row("Previous limit definition", interval.previous_limit_definition_id),
      row("Previous limit definition version", interval.previous_limit_definition_version),
      row("Active from", interval.active_from),
      row("Active to", interval.active_to),
      row("Observed", interval.observed_at),
      row("Complete", interval.complete?),
      row("Thresholds", interval.thresholds),
      row("Metadata", interval.metadata)
    ]
  end

  defp mission_event_rows(event) do
    [
      row("Mission event", event.mission_event_id),
      row("Occurred", event.occurred_at),
      row("Category", event.category),
      row("Kind", event.kind),
      row("Severity", event.severity),
      row("Status", event.status),
      row("Title", event.title),
      row("Summary", event.summary),
      row("Source record kind", event.source_record_kind),
      row("Source record", event.source_record_id),
      row("Subject kind", event.subject_kind),
      row("Subject", event.subject_id),
      row("Spacecraft", event.spacecraft_id),
      row("Source endpoint", event.source_endpoint_ref),
      row("Scheduled contact", event.scheduled_contact_id),
      row("Realized contact", event.realized_contact_id),
      row("Path", event.path_id),
      row("Capability instance", event.capability_instance_id),
      row("Activation", event.activation_id),
      row("Correlation", event.correlation_key),
      row("Actor", event.actor),
      row("Metadata", event.metadata)
    ]
  end

  defp operational_event_rows(event) do
    base_rows = [
      row("Operational event", event.event_id),
      row("Occurred", event.occurred_at),
      row("Recorded", event.recorded_at),
      row("Effective", event.effective_at),
      row("Category", event.category),
      row("Kind", event.kind),
      row("Severity", event.severity),
      row("Organization", event.organization_id),
      row("Mission", event.mission_id),
      row("Actor", event.actor),
      row("Subject", event.subject),
      row("Scope", event.scope),
      row("Causality", event.causality),
      row("Payload", event.payload),
      row("Current", event.current),
      row("Metadata", event.metadata)
    ]

    base_rows ++ operational_event_semantic_rows(event)
  end

  defp operational_event_semantic_rows(%{causality: causality} = event) do
    causality
    |> state_value(:source_record_kind)
    |> operational_event_semantic_rows_for(event)
  end

  defp operational_event_semantic_rows_for(kind, event)
       when kind in [:transport_action_request, "transport_action_request"],
       do: transport_action_request_rows(event)

  defp operational_event_semantic_rows_for(kind, event)
       when kind in [:transport_capability_record, "transport_capability_record"],
       do: transport_capability_record_rows(event)

  defp operational_event_semantic_rows_for(kind, event)
       when kind in [:transport_timer_event, "transport_timer_event"],
       do: transport_timer_event_rows(event)

  defp operational_event_semantic_rows_for(kind, event)
       when kind in [:managed_timer_event, "managed_timer_event"],
       do: managed_timer_event_rows(event)

  defp operational_event_semantic_rows_for(kind, event)
       when kind in [:managed_action_request, "managed_action_request"],
       do: managed_action_request_rows(event)

  defp operational_event_semantic_rows_for(kind, event)
       when kind in [:managed_capability_record, "managed_capability_record"],
       do: managed_capability_record_rows(event)

  defp operational_event_semantic_rows_for(kind, event)
       when kind in [:source_capability_posture, "source_capability_posture"],
       do: source_capability_posture_rows(event)

  defp operational_event_semantic_rows_for(kind, event)
       when kind in [:source_health_event, "source_health_event"],
       do: source_health_operational_event_rows(event)

  defp operational_event_semantic_rows_for(kind, event)
       when kind in [:connection_state_snapshot, "connection_state_snapshot"],
       do: connection_state_operational_event_rows(event)

  defp operational_event_semantic_rows_for(kind, event)
       when kind in [
              :link_rf_lock_state_snapshot,
              "link_rf_lock_state_snapshot",
              :link_frame_sync_state_snapshot,
              "link_frame_sync_state_snapshot"
            ],
       do: link_rf_state_operational_event_rows(event)

  defp operational_event_semantic_rows_for(kind, event)
       when kind in [:operational_observable_snapshot, "operational_observable_snapshot"],
       do: operational_observable_snapshot_operational_event_rows(event)

  defp operational_event_semantic_rows_for(_kind, _event), do: []

  defp operational_observable_snapshot_operational_event_rows(event) do
    case event.kind do
      kind
      when kind in [
             :operational_observable_metric_sampled,
             "operational_observable_metric_sampled"
           ] ->
        operational_observable_metric_operational_event_rows(event)

      _other ->
        operational_observable_state_operational_event_rows(event)
    end
  end

  defp operational_observable_metric_operational_event_rows(event) do
    payload = event.payload || %{}
    current = event.current || %{}
    causality = event.causality || %{}

    [
      row("Operational metric sample", state_value(causality, :source_record_id)),
      row("Observed", event.occurred_at),
      row("Observable", state_value(payload, :observable_id)),
      row("Resource", state_value(payload, :resource_id)),
      row("Scope kind", state_value(payload, :scope_kind)),
      row("Transport", state_value(payload, :transport_id)),
      row("Source endpoint", state_value(payload, :source_endpoint_id)),
      row("Ground station", state_value(payload, :ground_station_id)),
      row("Link", state_value(payload, :link_id)),
      row("Value", operational_metric_value(current, payload)),
      row("Unit", state_value(payload, :unit)),
      row("Replay run", state_value(payload, :replay_run_id))
    ]
  end

  defp operational_metric_value(current, payload) do
    [
      :value,
      :downlink_bitrate,
      :downlink_bitrate_bps,
      :uplink_bitrate,
      :uplink_bitrate_bps,
      :bitrate,
      :snr_db,
      :snr,
      :signal_to_noise_ratio_db,
      :eb_n0_db,
      :ebn0_db,
      :energy_per_bit_to_noise_density_db,
      :symbol_rate_sps,
      :symbol_rate,
      :symbols_per_second,
      :doppler_hz,
      :doppler,
      :frequency_offset_hz,
      :carrier_frequency_offset_hz
    ]
    |> Enum.find_value(fn field ->
      state_value(current, field) || state_value(payload, field)
    end)
  end

  defp operational_observable_state_operational_event_rows(event) do
    payload = event.payload || %{}
    current = event.current || %{}
    causality = event.causality || %{}

    [
      row("Operational observable snapshot", state_value(causality, :source_record_id)),
      row("Observed", event.occurred_at),
      row("Observable", state_value(payload, :observable_id)),
      row("Resource", state_value(payload, :resource_id)),
      row("Scope kind", state_value(payload, :scope_kind)),
      row("Transport", state_value(payload, :transport_id)),
      row("Source endpoint", state_value(payload, :source_endpoint_id)),
      row("Ground station", state_value(payload, :ground_station_id)),
      row("Link", state_value(payload, :link_id)),
      row("State", state_value(current, :state) || state_value(payload, :state)),
      row("Replay run", state_value(payload, :replay_run_id))
    ]
  end

  defp link_rf_state_operational_event_rows(event) do
    payload = event.payload || %{}
    current = event.current || %{}
    causality = event.causality || %{}

    [
      row("RF state snapshot", state_value(causality, :source_record_id)),
      row("Observed", event.occurred_at),
      row("Observable", state_value(payload, :observable_id)),
      row("Resource", state_value(payload, :resource_id)),
      row("Scope kind", state_value(payload, :scope_kind)),
      row("Transport", state_value(payload, :transport_id)),
      row("Source endpoint", state_value(payload, :source_endpoint_id)),
      row("Ground station", state_value(payload, :ground_station_id)),
      row("Link", state_value(payload, :link_id)),
      row("RF state", state_value(current, :state) || state_value(payload, :state)),
      row("Replay run", state_value(payload, :replay_run_id))
    ]
  end

  defp connection_state_operational_event_rows(event) do
    payload = event.payload || %{}
    current = event.current || %{}
    causality = event.causality || %{}

    [
      row("Connection state snapshot", state_value(causality, :source_record_id)),
      row("Observed", event.occurred_at),
      row("Observable", state_value(payload, :observable_id)),
      row("Resource", state_value(payload, :resource_id)),
      row("Scope kind", state_value(payload, :scope_kind)),
      row("Transport", state_value(payload, :transport_id)),
      row("Spacecraft", state_value(payload, :spacecraft_id)),
      row("Contact", state_value(payload, :contact_id)),
      row("Source endpoint", state_value(payload, :source_endpoint_id)),
      row("Ground station", state_value(payload, :ground_station_id)),
      row("Link", state_value(payload, :link_id)),
      row("Adapter", state_value(payload, :adapter_key)),
      row(
        "Connection state",
        state_value(current, :connection_state) || state_value(payload, :connection_state)
      ),
      row(
        "Normalized state",
        state_value(current, :normalized_state) || state_value(payload, :normalized_state)
      ),
      row("State", state_value(current, :state) || state_value(payload, :state)),
      row("Replay run", state_value(payload, :replay_run_id))
    ]
  end

  defp source_health_operational_event_rows(event) do
    payload = event.payload || %{}
    current = event.current || %{}

    [
      row("Source health event", state_value(payload, :source_health_event_id)),
      row("Observed", event.occurred_at),
      row("Logical source", state_value(payload, :logical_source)),
      row("Data source", state_value(payload, :data_source_id)),
      row("Source binding", state_value(payload, :source_binding_id)),
      row("Realm", state_value(payload, :data_realm)),
      row("Dataset", state_value(payload, :dataset)),
      row("Replay run", state_value(payload, :replay_run_id)),
      row("Event type", state_value(payload, :event_type)),
      row(
        "Source health",
        state_value(current, :source_health) || state_value(payload, :source_health)
      ),
      row("Previous source health", state_value(payload, :previous_source_health)),
      row("Reason", state_value(current, :reason) || state_value(payload, :reason)),
      row("Source payload", state_value(payload, :source_payload))
    ]
  end

  defp source_capability_posture_rows(event) do
    payload = event.payload || %{}
    current = event.current || %{}

    [
      row("Source capability posture", state_value(payload, :source_capability_posture_id)),
      row("Dashboard", state_value(payload, :dashboard_id)),
      row("Dashboard version", state_value(payload, :dashboard_version)),
      row("Resolve", state_value(payload, :resolve_id)),
      row("Source request", state_value(payload, :source_request_id)),
      row("Logical source", state_value(payload, :logical_source)),
      row("Data source", state_value(payload, :data_source_id)),
      row("Source binding", state_value(payload, :source_binding_id)),
      row("Realm", state_value(payload, :realm)),
      row("Dataset", state_value(payload, :dataset)),
      row("Replay run", state_value(payload, :replay_run_id)),
      row(
        "Capability status",
        state_value(current, :capability_status) || state_value(payload, :status)
      ),
      row("Requested sampling", state_value(payload, :requested_sampling)),
      row("Supported sampling", state_value(payload, :supported_sampling)),
      row("Requested products", state_value(payload, :requested_products)),
      row("Supported products", state_value(payload, :supported_products)),
      row("Requested time axis", state_value(payload, :requested_time_axis)),
      row("Executed time axis", state_value(payload, :executed_time_axis)),
      row("Supported time axes", state_value(payload, :supported_time_axes)),
      row("Fallbacks", state_value(payload, :fallbacks)),
      row("Unsupported", state_value(payload, :unsupported)),
      row("Source execution status", state_value(payload, :source_execution_status)),
      row("Source execution cache status", state_value(payload, :source_execution_cache_status)),
      row(
        "Source execution operator action",
        state_value(payload, :source_execution_operator_action)
      ),
      row(
        "Source execution runtime action",
        state_value(payload, :source_execution_runtime_action)
      ),
      row("Source execution warnings", state_value(payload, :source_execution_warning_codes))
    ]
  end

  defp transport_capability_record_rows(event) do
    payload = event.payload || %{}

    [
      row("Transport capability record", state_value(payload, :transport_record_id)),
      row("Operational event", event.event_id),
      row("Occurred", event.occurred_at),
      row("Kind", event.kind),
      row("Contact", state_value(payload, :contact_id)),
      row("Path", state_value(payload, :path_id)),
      row("Capability instance", state_value(payload, :capability_instance_id)),
      row("Family", state_value(payload, :family_key)),
      row("Binding set", state_value(payload, :binding_set_id)),
      row("Binding set version", state_value(payload, :binding_set_version)),
      row("Activation", state_value(payload, :activation_id)),
      row("Partition affinity", state_value(payload, :partition_affinity)),
      row("Partition value", state_value(payload, :partition_value)),
      row("Event kind", state_value(payload, :event_kind)),
      row("Timer", state_value(payload, :timer_key)),
      row("Emitted record kinds", state_value(payload, :emitted_record_kinds)),
      row("Emitted record count", state_value(payload, :emitted_record_count)),
      row("Action request count", state_value(payload, :action_request_count)),
      row("State snapshot", state_value(payload, :state_snapshot)),
      row("Record metadata", state_value(payload, :record_metadata)),
      row("Recorded", state_value(payload, :recorded_at)),
      row("Replay run", state_value(payload, :replay_run_id))
    ]
  end

  defp transport_action_request_rows(event) do
    payload = event.payload || %{}

    [
      row("Transport action request", state_value(payload, :action_request_id)),
      row("Operational event", event.event_id),
      row("Occurred", event.occurred_at),
      row("Kind", event.kind),
      row("Contact", state_value(payload, :contact_id)),
      row("Path", state_value(payload, :path_id)),
      row("Capability instance", state_value(payload, :capability_instance_id)),
      row("Family", state_value(payload, :family_key)),
      row("Binding set", state_value(payload, :binding_set_id)),
      row("Binding set version", state_value(payload, :binding_set_version)),
      row("Activation", state_value(payload, :activation_id)),
      row("Partition affinity", state_value(payload, :partition_affinity)),
      row("Partition value", state_value(payload, :partition_value)),
      row("Source endpoint", state_value(payload, :source_endpoint_ref)),
      row("Command release attempt", state_value(payload, :command_release_attempt_id)),
      row("Command request", state_value(payload, :command_request_id)),
      row("Command", state_value(payload, :command_name)),
      row("Signal phase", state_value(payload, :signal_phase)),
      row("Action kind", state_value(payload, :action_kind)),
      row("Request document", state_value(payload, :request_document)),
      row("Requested", state_value(payload, :requested_at)),
      row("Action metadata", state_value(payload, :action_metadata)),
      row("Replay run", state_value(payload, :replay_run_id))
    ]
  end

  defp transport_timer_event_rows(event) do
    payload = event.payload || %{}

    [
      row("Transport timer event", state_value(payload, :timer_event_id)),
      row("Operational event", event.event_id),
      row("Occurred", event.occurred_at),
      row("Kind", event.kind),
      row("Contact", state_value(payload, :contact_id)),
      row("Path", state_value(payload, :path_id)),
      row("Capability instance", state_value(payload, :capability_instance_id)),
      row("Family", state_value(payload, :family_key)),
      row("Binding set", state_value(payload, :binding_set_id)),
      row("Binding set version", state_value(payload, :binding_set_version)),
      row("Activation", state_value(payload, :activation_id)),
      row("Partition affinity", state_value(payload, :partition_affinity)),
      row("Partition value", state_value(payload, :partition_value)),
      row("Timer", state_value(payload, :timer_key)),
      row("Event kind", state_value(payload, :event_kind)),
      row("Due", state_value(payload, :due_at)),
      row("Timer metadata", state_value(payload, :timer_metadata)),
      row("Replay run", state_value(payload, :replay_run_id))
    ]
  end

  defp managed_timer_event_rows(event) do
    payload = event.payload || %{}

    [
      row("Managed timer event", state_value(payload, :timer_event_id)),
      row("Operational event", event.event_id),
      row("Occurred", event.occurred_at),
      row("Kind", event.kind),
      row("Capability instance", state_value(payload, :capability_instance_id)),
      row("Family", state_value(payload, :family_key)),
      row("Binding set", state_value(payload, :binding_set_id)),
      row("Binding set version", state_value(payload, :binding_set_version)),
      row("Activation", state_value(payload, :activation_id)),
      row("Partition affinity", state_value(payload, :partition_affinity)),
      row("Partition value", state_value(payload, :partition_value)),
      row("Packet", state_value(payload, :packet_id)),
      row("Evidence", state_value(payload, :evidence_id)),
      row("Timer", state_value(payload, :timer_key)),
      row("Event kind", state_value(payload, :event_kind)),
      row("Due", state_value(payload, :due_at)),
      row("Timer metadata", state_value(payload, :timer_metadata)),
      row("Replay run", state_value(payload, :replay_run_id))
    ]
  end

  defp managed_action_request_rows(event) do
    payload = event.payload || %{}

    [
      row("Managed action request", state_value(payload, :action_request_id)),
      row("Operational event", event.event_id),
      row("Occurred", event.occurred_at),
      row("Kind", event.kind),
      row("Capability instance", state_value(payload, :capability_instance_id)),
      row("Family", state_value(payload, :family_key)),
      row("Binding set", state_value(payload, :binding_set_id)),
      row("Binding set version", state_value(payload, :binding_set_version)),
      row("Activation", state_value(payload, :activation_id)),
      row("Partition affinity", state_value(payload, :partition_affinity)),
      row("Partition value", state_value(payload, :partition_value)),
      row("Packet", state_value(payload, :packet_id)),
      row("Evidence", state_value(payload, :evidence_id)),
      row("Action kind", state_value(payload, :action_kind)),
      row("Request document", state_value(payload, :request_document)),
      row("Requested", state_value(payload, :requested_at)),
      row("Replay run", state_value(payload, :replay_run_id))
    ]
  end

  defp managed_capability_record_rows(event) do
    payload = event.payload || %{}

    [
      row("Managed capability record", state_value(payload, :capability_record_id)),
      row("Operational event", event.event_id),
      row("Occurred", event.occurred_at),
      row("Kind", event.kind),
      row("Capability instance", state_value(payload, :capability_instance_id)),
      row("Family", state_value(payload, :family_key)),
      row("Binding set", state_value(payload, :binding_set_id)),
      row("Binding set version", state_value(payload, :binding_set_version)),
      row("Activation", state_value(payload, :activation_id)),
      row("Partition affinity", state_value(payload, :partition_affinity)),
      row("Partition value", state_value(payload, :partition_value)),
      row("Packet", state_value(payload, :packet_id)),
      row("Evidence", state_value(payload, :evidence_id)),
      row("Timer", state_value(payload, :timer_key)),
      row("Event kind", state_value(payload, :event_kind)),
      row("Emitted record kinds", state_value(payload, :emitted_record_kinds)),
      row("Emitted record count", state_value(payload, :emitted_record_count)),
      row("Action request count", state_value(payload, :action_request_count)),
      row("State snapshot", state_value(payload, :state_snapshot)),
      row("Record metadata", state_value(payload, :record_metadata)),
      row("Recorded", state_value(payload, :recorded_at)),
      row("Replay run", state_value(payload, :replay_run_id))
    ]
  end

  defp resolve_command_release_attempt(%DataLink{} = link, organization_id, mission_id) do
    release_attempt_row =
      CommandReleaseAttemptRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.command_release_attempt_id == ^link.target_id
      )
      |> Repo.one()

    case release_attempt_row do
      %CommandReleaseAttemptRow{} = release_attempt_row ->
        release_attempt = CommandReleaseAttemptRow.to_domain(release_attempt_row)

        transport_action_event =
          command_release_attempt_transport_action_event(
            release_attempt,
            organization_id,
            mission_id
          )

        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           command_release_attempt_rows(release_attempt, transport_action_event),
           command_release_attempt_related_links(
             link,
             release_attempt,
             organization_id,
             mission_id
           )
         )}

      nil ->
        {:error,
         inspector(
           link,
           :missing,
           "Command release attempt was not found in this mission.",
           []
         )}
    end
  end

  defp resolve_command_queue_entry(%DataLink{} = link, organization_id, mission_id) do
    queue_entry_row =
      CommandQueueEntryRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.command_queue_entry_id == ^link.target_id
      )
      |> Repo.one()

    case queue_entry_row do
      %CommandQueueEntryRow{} = queue_entry_row ->
        queue_entry = CommandQueueEntryRow.to_domain(queue_entry_row)

        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           command_queue_entry_rows(queue_entry),
           command_queue_entry_related_links(link, queue_entry)
         )}

      nil ->
        {:error,
         inspector(link, :missing, "Command queue entry was not found in this mission.", [])}
    end
  end

  defp command_queue_entry_rows(queue_entry) do
    [
      row("Command queue entry", queue_entry.command_queue_entry_id),
      row("Lifecycle state", queue_entry.lifecycle_state),
      row("Command request", queue_entry.command_request_id),
      row("Source endpoint", queue_entry.source_endpoint_ref),
      row("Queue lane", queue_entry.queue_lane_key),
      row("Priority", queue_entry.priority),
      row("Queue sequence", queue_entry.queue_sequence),
      row("Not before", queue_entry.not_before),
      row("Expires at", queue_entry.expires_at),
      row("Enqueued at", queue_entry.enqueued_at),
      row("Enqueued by", queue_entry.enqueued_by),
      row("Metadata", queue_entry.metadata)
    ]
  end

  defp command_queue_entry_related_links(%DataLink{} = link, queue_entry) do
    [
      related_link(
        link,
        :command_request,
        queue_entry.command_request_id,
        "Command request"
      )
    ]
  end

  defp resolve_command_request(%DataLink{} = link, organization_id, mission_id) do
    request_row =
      CommandRequestRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.command_request_id == ^link.target_id
      )
      |> Repo.one()

    case request_row do
      %CommandRequestRow{} = request_row ->
        request = CommandRequestRow.to_domain(request_row)

        {:ok,
         inspector(
           link,
           :resolved,
           nil,
           command_request_rows(request),
           command_request_related_links(link, request, organization_id, mission_id)
         )}

      nil ->
        {:error, inspector(link, :missing, "Command request was not found in this mission.", [])}
    end
  end

  defp command_request_rows(request) do
    [
      row("Command request", request.command_request_id),
      row("Lifecycle state", request.lifecycle_state),
      row("Verification state", request.verification_state),
      row("Source endpoint", request.source_endpoint_ref),
      row("Command", request.command_name),
      row("Command display name", request.command_display_name),
      row("Command id", request.command_id),
      row("Command snapshot", request.command_snapshot_id),
      row("Priority", request.priority),
      row("Not before", request.not_before),
      row("Expires at", request.expires_at),
      row("Requested at", request.requested_at),
      row("Requested by", request.requested_by),
      row("Source command stage", request.source_command_stage_id),
      row("Source staged command item", request.source_staged_command_item_id),
      row("Argument values", request.argument_values),
      row("Resolved argument values", request.resolved_argument_values),
      row("Significance", request.significance),
      row("Critical", request.critical),
      row("Hazardous", request.hazardous),
      row("Subsystem", request.subsystem),
      row("Group", request.group_name),
      row("Preferred uplink service", request.preferred_uplink_service),
      row("Release policy hint", request.release_policy_hint),
      row("APID", request.apid),
      row("Service type", request.service_type),
      row("Service subtype", request.service_subtype),
      row("Opcode", request.opcode),
      row("Metadata", request.metadata)
    ]
  end

  defp command_request_related_links(%DataLink{} = link, request, organization_id, mission_id) do
    queue_entry_links =
      CommandQueueEntryRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.command_request_id == ^request.command_request_id
      )
      |> order_by([row], asc: row.enqueued_at, asc: row.command_queue_entry_id)
      |> Repo.all()
      |> Enum.map(fn queue_entry_row ->
        related_link(
          link,
          :command_queue_entry,
          queue_entry_row.command_queue_entry_id,
          "Command queue entry"
        )
      end)

    release_attempt_links =
      CommandReleaseAttemptRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.command_request_id == ^request.command_request_id
      )
      |> order_by([row], asc: row.attempted_at, asc: row.command_release_attempt_id)
      |> Repo.all()
      |> Enum.map(fn release_attempt_row ->
        related_link(
          link,
          :command_release_attempt,
          release_attempt_row.command_release_attempt_id,
          "Command release attempt"
        )
      end)

    queue_entry_links ++ release_attempt_links
  end

  defp command_release_attempt_rows(release_attempt, transport_action_event) do
    transport_action_payload =
      case transport_action_event do
        nil -> %{}
        event -> event.payload || %{}
      end

    [
      row("Command release attempt", release_attempt.command_release_attempt_id),
      row("Lifecycle state", release_attempt.lifecycle_state),
      row("Verification state", release_attempt.verification_state),
      row("Failure reason", release_attempt.failure_reason),
      row("Command request", release_attempt.command_request_id),
      row("Command queue entry", release_attempt.command_queue_entry_id),
      row("Command", release_attempt.command_name),
      row("Command id", release_attempt.command_id),
      row("Command snapshot", release_attempt.command_snapshot_id),
      row("Source endpoint", release_attempt.source_endpoint_ref),
      row("Transport action request", state_value(transport_action_payload, :action_request_id)),
      row("Signal phase", state_value(transport_action_payload, :signal_phase)),
      row("Action kind", state_value(transport_action_payload, :action_kind)),
      row(
        "Transport operational event",
        transport_action_event && transport_action_event.event_id
      ),
      row("Realized contact", release_attempt.realized_contact_id),
      row("Path", release_attempt.path_id),
      row("Transport binding", release_attempt.transport_binding_id),
      row("Layout kind", release_attempt.layout_kind),
      row("Preferred uplink service", release_attempt.preferred_uplink_service),
      row("APID", release_attempt.apid),
      row("Service type", release_attempt.service_type),
      row("Service subtype", release_attempt.service_subtype),
      row("Opcode", release_attempt.opcode),
      row("Encoded size bytes", release_attempt.encoded_size_bytes),
      row("Attempted at", release_attempt.attempted_at),
      row("Released at", release_attempt.released_at),
      row("Released by", release_attempt.released_by),
      row("Metadata", release_attempt.metadata)
    ]
  end

  defp command_release_attempt_transport_action_event(
         release_attempt,
         organization_id,
         mission_id
       ) do
    case state_value(release_attempt.metadata, :transport_action_request_id) do
      action_request_id when is_binary(action_request_id) and action_request_id != "" ->
        OperationalEventRow
        |> where(
          [row],
          row.organization_id == ^organization_id and row.mission_id == ^mission_id and
            row.source_record_kind == "transport_action_request" and
            row.source_record_id == ^action_request_id
        )
        |> order_by([row], asc: row.occurred_at, asc: row.event_id)
        |> limit(1)
        |> Repo.one()
        |> case do
          %OperationalEventRow{} = event_row -> OperationalEventRow.to_domain(event_row)
          nil -> nil
        end

      _missing ->
        nil
    end
  end

  defp command_release_attempt_related_links(
         %DataLink{} = link,
         release_attempt,
         organization_id,
         mission_id
       ) do
    verifier_links =
      CommandVerifierInstanceRow
      |> where(
        [row],
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.command_release_attempt_id == ^release_attempt.command_release_attempt_id
      )
      |> order_by([row], asc: row.matched_at, asc: row.command_verifier_instance_id)
      |> Repo.all()
      |> Enum.map(fn verifier_row ->
        related_link(
          link,
          :command_verifier_instance,
          verifier_row.command_verifier_instance_id,
          "Command verifier instance"
        )
      end)

    [
      related_link(
        link,
        :command_request,
        release_attempt.command_request_id,
        "Command request"
      ),
      related_link(
        link,
        :command_queue_entry,
        release_attempt.command_queue_entry_id,
        "Command queue entry"
      ),
      related_link(
        link,
        :source_endpoint,
        release_attempt.source_endpoint_ref,
        "Source endpoint"
      ),
      related_link(
        link,
        :contact,
        release_attempt.realized_contact_id,
        "Contact"
      ),
      related_link(
        link,
        :transport_action_request,
        state_value(release_attempt.metadata, :transport_action_request_id),
        "Transport action request"
      )
      | verifier_links
    ]
  end

  defp command_verifier_instance_rows(verifier_instance) do
    [
      row("Command verifier instance", verifier_instance.command_verifier_instance_id),
      row("Verifier", verifier_instance.verifier_id),
      row("Verifier name", verifier_instance.verifier_name),
      row("Lifecycle state", verifier_instance.lifecycle_state),
      row("Severity", verifier_instance.severity),
      row("Phase", verifier_instance.phase),
      row("Command release attempt", verifier_instance.command_release_attempt_id),
      row("Command request", verifier_instance.command_request_id),
      row("Command", verifier_instance.command_name),
      row("Command id", verifier_instance.command_id),
      row("Command snapshot", verifier_instance.command_snapshot_id),
      row("Source endpoint", verifier_instance.source_endpoint_ref),
      row("Matched record kind", verifier_instance.matched_record_kind),
      row("Matched record", verifier_instance.matched_record_id),
      row("Matched at", verifier_instance.matched_at),
      row("Failure reason", verifier_instance.failure_reason),
      row("Delay until", verifier_instance.delay_until),
      row("Timeout at", verifier_instance.timeout_at),
      row("Success criteria", verifier_instance.success_criteria),
      row("Failure criteria", verifier_instance.failure_criteria),
      row("Metadata", verifier_instance.metadata)
    ]
  end

  defp command_verifier_instance_related_links(%DataLink{} = link, verifier_instance) do
    [
      related_link(
        link,
        :command_release_attempt,
        verifier_instance.command_release_attempt_id,
        "Command release attempt"
      ),
      related_link(
        link,
        :command_request,
        verifier_instance.command_request_id,
        "Command request"
      ),
      matched_record_related_link(
        link,
        verifier_instance.matched_record_kind,
        verifier_instance.matched_record_id
      )
    ]
  end

  defp matched_record_related_link(%DataLink{} = link, matched_record_kind, matched_record_id) do
    with target when is_atom(target) <- DataLink.parse_resolvable_target(matched_record_kind),
         id when is_binary(id) and id != "" <- string_id(matched_record_id) do
      related_link(link, target, id, target_text(target))
    else
      _missing -> nil
    end
  end

  defp source_health_event_rows(event) do
    [
      row("Source health event", event.source_health_event_id),
      row("Observed", event.observed_at),
      row("Logical source", event.logical_source),
      row("Data source", event.data_source_id),
      row("Source binding", event.source_binding_id),
      row("Realm", event.realm),
      row("Dataset", event.dataset),
      row("Replay run", event.replay_run_id),
      row("Event type", event.event_type),
      row("Source health", event.source_health),
      row("Previous source health", event.previous_source_health),
      row("Reason", event.reason),
      row("Payload", event.payload)
    ]
  end

  defp source_watermark_event_rows(event) do
    [
      row("Source watermark event", event.source_watermark_event_id),
      row("Source watermark key", event.source_watermark_key),
      row("Observed", event.observed_at),
      row("Logical source", event.logical_source),
      row("Data source", event.data_source_id),
      row("Source binding", event.source_binding_id),
      row("Realm", event.realm),
      row("Dataset", event.dataset),
      row("Replay run", event.replay_run_id),
      row("Event type", event.event_type),
      row("Complete through", event.complete_through),
      row("Previous complete through", event.previous_complete_through),
      row("Latest receipt time", event.latest_receipt_time),
      row("Previous latest receipt time", event.previous_latest_receipt_time),
      row("Retention starts at", event.retention_starts_at),
      row("Previous retention starts at", event.previous_retention_starts_at),
      row("Sample count", event.sample_count),
      row("Confidence", event.confidence),
      row("Reason", event.reason),
      row("Payload", event.payload)
    ]
  end

  defp source_binding_event_rows(event) do
    [
      row("Source binding event", event.data_binding_event_id),
      row("Binding", event.binding_id),
      row("Event type", event.event_type),
      row("Previous status", event.previous_status),
      row("Current status", event.current_status),
      row("Previous binding version", event.previous_binding_version),
      row("Current binding version", event.current_binding_version),
      row("Previous logical source", event.previous_logical_source),
      row("Current logical source", event.current_logical_source),
      row("Previous realm", event.previous_realm),
      row("Current realm", event.current_realm),
      row("Previous data source", event.previous_data_source_id),
      row("Current data source", event.current_data_source_id),
      row("Previous dataset", event.previous_dataset),
      row("Current dataset", event.current_dataset),
      row("Previous priority", event.previous_priority),
      row("Current priority", event.current_priority),
      row("Previous active from", event.previous_active_from),
      row("Current active from", event.current_active_from),
      row("Previous active to", event.previous_active_to),
      row("Current active to", event.current_active_to),
      row("Actor", event.actor_id),
      row("Occurred", event.occurred_at),
      row("Payload", event.payload)
    ]
  end

  defp effective_interval_rows(%EffectiveInterval{} = interval) do
    [
      row("Operational interval", interval.interval_id),
      row("Kind", interval.kind),
      row("Subject kind", interval.subject_kind),
      row("Subject", interval.subject_id),
      row("Starts", interval.starts_at),
      row("Ends", interval.ends_at),
      row("Source event", interval.source_event_id),
      row("Superseded by event", interval.superseded_by_event_id),
      row("Payload", interval.payload),
      row("Metadata", interval.metadata)
    ]
  end

  defp source_binding_data_interval_rows(interval_id, %DataBindingInterval{} = interval) do
    [
      row("Source binding interval", interval_id),
      row("Binding", interval.binding_id),
      row("Data binding event", interval.data_binding_event_id),
      row("Event type", interval.event_type),
      row("Status", interval.status),
      row("Binding version", interval.binding_version),
      row("Logical source", interval.logical_source),
      row("Realm", interval.realm),
      row("Data source", interval.data_source_id),
      row("Dataset", interval.dataset),
      row("Priority", interval.priority),
      row("Started", interval.started_at),
      row("Ended", interval.ended_at),
      row("Active from", interval.active_from),
      row("Active to", interval.active_to)
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

  defp telemetry_backfill_lifecycle_event_rows(event, organization_id, mission_id) do
    [
      row("Backfill lifecycle event", event.backfill_lifecycle_event_id),
      row("Backfill run", event.backfill_run_id),
      row("Event type", event.event_type),
      row("Workflow", backfill_lifecycle_payload_value(event.payload, :workflow)),
      row("Workflow stage", backfill_lifecycle_payload_value(event.payload, :stage)),
      row("Workflow run", backfill_lifecycle_payload_value(event.payload, :run_id)),
      row("Dashboard context", dashboard_context_value(event.payload, :dashboard_id)),
      row(
        "Dashboard context version",
        dashboard_context_value(event.payload, :dashboard_version)
      ),
      row(
        "Dashboard context time mode",
        dashboard_context_value(event.payload, :dashboard_time_mode)
      ),
      row(
        "Dashboard context replay run",
        dashboard_context_value(event.payload, :dashboard_replay_run_id)
      ),
      row(
        "Dashboard context data view",
        dashboard_context_value(event.payload, :dashboard_data_view)
      ),
      row(
        "Dashboard context limit mode",
        dashboard_context_value(event.payload, :dashboard_limit_mode)
      ),
      row(
        "Comparison review request",
        comparison_review_origin_value(event.payload, :request_event_id)
      ),
      row(
        "Comparison review kind",
        comparison_review_origin_value(event.payload, :request_kind)
      ),
      row(
        "Comparison review open count",
        comparison_review_origin_value(event.payload, :open_count)
      ),
      row(
        "Comparison review placements",
        comparison_review_origin_value(event.payload, :open_placement_ids)
      ),
      row(
        "Comparison review workflow kind",
        comparison_review_origin_value(event.payload, :workflow_kind)
      ),
      row(
        "Comparison review workflow action",
        comparison_review_origin_value(event.payload, :workflow_action)
      ),
      row(
        "Comparison review workflow selection kind",
        comparison_review_origin_value(event.payload, :workflow_selection_kind)
      ),
      row(
        "Comparison review workflow selection count",
        comparison_review_origin_value(event.payload, :workflow_selection_count)
      ),
      row(
        "Comparison review primary data view",
        comparison_review_origin_value(event.payload, :primary_data_view)
      ),
      row(
        "Comparison review compare data view",
        comparison_review_origin_value(event.payload, :compare_data_view)
      ),
      row(
        "Comparison review scope kind",
        comparison_review_origin_value(event.payload, :scope_kind)
      ),
      row(
        "Comparison review scope ids",
        comparison_review_origin_value(event.payload, :scope_ids)
      ),
      row(
        "Comparison review contact ids",
        comparison_review_origin_value(event.payload, :contact_ids)
      ),
      row(
        "Comparison review resource ids",
        comparison_review_origin_value(event.payload, :resource_ids)
      ),
      row(
        "Comparison review transport ids",
        comparison_review_origin_value(event.payload, :transport_ids)
      ),
      row(
        "Comparison review source endpoint ids",
        comparison_review_origin_value(event.payload, :source_endpoint_ids)
      ),
      row(
        "Comparison review ground station ids",
        comparison_review_origin_value(event.payload, :ground_station_ids)
      ),
      row(
        "Comparison review scope link ids",
        comparison_review_origin_value(event.payload, :scope_link_ids)
      ),
      row("Request mode", backfill_lifecycle_payload_value(event.payload, :request_mode)),
      row("Request group", backfill_lifecycle_payload_value(event.payload, :request_group_id)),
      row("Request item", backfill_lifecycle_request_item(event.payload)),
      row("Occurred", event.occurred_at),
      row("Realm", event.realm),
      row("Replay run", event.replay_run_id),
      row("Data source", event.data_source_id),
      row("Source binding", event.binding_id),
      row("Observable", event.observable_id),
      row("Point", event.point_id),
      row("Spacecraft", event.spacecraft_id),
      row("Source from", event.source_from),
      row("Source to", event.source_to),
      row("Receipt from", event.receipt_from),
      row("Receipt to", event.receipt_to),
      row("Sample count", event.sample_count),
      row("Authority", event.authority),
      row("Reason", event.reason),
      row("Actor", event.actor_id),
      row("Actor kind", event.actor_kind),
      row("Payload", event.payload)
    ]
    |> Kernel.++(telemetry_backfill_lifecycle_group_rows(event, organization_id, mission_id))
    |> Kernel.++(telemetry_backfill_lifecycle_failure_rows(event))
    |> Kernel.++(telemetry_backfill_lifecycle_retry_rows(event))
    |> Kernel.++(telemetry_backfill_lifecycle_missing_replacement_rows(event))
    |> Kernel.++(telemetry_backfill_lifecycle_stale_replacement_rows(event))
    |> Kernel.++(telemetry_backfill_lifecycle_correction_rows(event))
    |> Kernel.++(telemetry_backfill_lifecycle_late_data_policy_rows(event))
    |> Kernel.++(telemetry_backfill_lifecycle_job_rows(event))
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

  defp telemetry_backfill_lifecycle_group_rows(event, organization_id, mission_id) do
    case backfill_lifecycle_payload_value(event.payload, :request_group_id) do
      group_id when is_binary(group_id) and group_id != "" ->
        lifecycle_events =
          mission_id
          |> TelemetryStorage.list_backfill_lifecycle_events(
            organization_id: organization_id,
            limit: 1_000
          )

        group_events =
          Enum.filter(
            lifecycle_events,
            &(backfill_lifecycle_payload_value(&1.payload, :request_group_id) == group_id)
          )

        group =
          BackfillLifecycleGroup.summary(group_events, lifecycle_events,
            retry_ready_fun: &backfill_lifecycle_group_retry_ready?/1
          )

        [
          row("Request group state", group.state),
          row("Request group terminal", group.terminal?),
          row("Request group size", group.size),
          row("Request group progress", group.progress),
          row("Request group job progress", backfill_lifecycle_group_job_progress(group_events)),
          row("Request group job items", backfill_lifecycle_group_job_items(group_events)),
          row(
            "Request group retried items",
            backfill_lifecycle_group_retried_items(group_events)
          ),
          row(
            "Request group corrected items",
            backfill_lifecycle_group_corrected_items(group_events)
          ),
          row(
            "Request group correction tasks",
            backfill_lifecycle_group_correction_tasks(group_events)
          ),
          row("Request group requested", group.requested),
          row("Request group approved", group.approved),
          row("Request group started", group.started),
          row("Request group completed", group.completed),
          row("Request group failed", group.failed),
          row("Request group resolved failed", group.resolved_failed),
          row("Request group retry resolved", group.retry_resolved),
          row("Request group correction requested", group.correction_requested),
          row("Request group correction started", group.correction_started),
          row("Request group correction completed", group.correction_completed),
          row("Request group correction superseded", group.correction_superseded),
          row("Request group request eligible", group.request_eligible),
          row("Request group approve eligible", group.approve_eligible),
          row("Request group reject eligible", group.reject_eligible),
          row("Request group start eligible", group.start_eligible),
          row("Request group complete eligible", group.complete_eligible),
          row("Request group fail eligible", group.fail_eligible),
          row("Request group retryable failed", group.retryable_failed),
          row("Request group nonretryable failed", group.nonretryable_failed),
          row("Request group failed items", group.failed_items),
          row("Request group failed item events", group.failed_item_events)
        ]

      _other ->
        []
    end
  end

  defp telemetry_backfill_lifecycle_failure_rows(event) do
    source = backfill_lifecycle_payload_value(event.payload, :source)
    failure = state_value(source, :failure)
    source_window = state_value(source, :source_window)
    source_identity = state_value(source, :source_identity)

    [
      row("Workflow failure code", state_value(failure, :code)),
      row("Workflow failure detail", state_value(failure, :detail)),
      row("Workflow retryable", state_value(failure, :retryable)),
      row("Workflow retry blockers", state_value(failure, :retry_blockers)),
      row("Workflow recovery action", state_value(failure, :recovery_action)),
      row("Workflow source point", state_value(source, :point_id)),
      row("Workflow source realm", state_value(source_identity, :realm)),
      row("Workflow source replay run", state_value(source_identity, :replay_run_id)),
      row("Workflow source data source", state_value(source_identity, :data_source_id)),
      row("Workflow source binding", state_value(source_identity, :source_binding_id)),
      row("Workflow source from", state_value(source_window, :from_observed_at)),
      row("Workflow source to", state_value(source_window, :to_observed_at)),
      row("Workflow receipt from", state_value(source_window, :from_receipt_time)),
      row("Workflow receipt to", state_value(source_window, :to_receipt_time)),
      row("Workflow source limit", state_value(source, :source_limit))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp backfill_lifecycle_group_job_progress(group_events) when is_list(group_events) do
    statuses =
      group_events
      |> backfill_lifecycle_group_job_item_details()
      |> Enum.map(&Map.fetch!(&1, :job_status))

    if statuses == [] do
      nil
    else
      statuses
      |> Enum.frequencies()
      |> Enum.sort_by(fn {status, _count} ->
        backfill_lifecycle_group_job_status_order(status)
      end)
      |> Enum.map_join(", ", fn {status, count} -> "#{status} #{count}" end)
    end
  end

  defp backfill_lifecycle_group_job_items(group_events) when is_list(group_events) do
    group_events
    |> backfill_lifecycle_group_job_item_details()
    |> case do
      [] ->
        nil

      details ->
        Enum.map_join(details, "; ", fn detail ->
          [
            detail.item_label,
            detail.run_id,
            detail.job_status,
            detail.job_id,
            backfill_lifecycle_group_job_text_token("event", detail.event_id),
            backfill_lifecycle_group_job_time_token("started", detail.job_started_at),
            backfill_lifecycle_group_job_time_token("completed", detail.job_completed_at)
          ]
          |> Enum.reject(&blank_text?/1)
          |> Enum.join(" ")
        end)
    end
  end

  defp backfill_lifecycle_group_job_item_details(group_events) when is_list(group_events) do
    requested_events = BackfillLifecycleGroup.effective_requested_events(group_events)
    effective_events = BackfillLifecycleGroup.effective_events(group_events)
    latest_event_by_item = BackfillLifecycleGroup.latest_event_by_item(effective_events)

    requested_events
    |> Enum.sort_by(&backfill_lifecycle_group_item_sort_key/1)
    |> Enum.map(fn requested_event ->
      item_key = BackfillLifecycleGroup.item_key(requested_event)
      latest_event = Map.get(latest_event_by_item, item_key, requested_event)
      run_id = latest_event.backfill_run_id || requested_event.backfill_run_id
      job = backfill_lifecycle_group_job(run_id)

      %{
        item_label: backfill_lifecycle_group_item_label(latest_event, requested_event),
        event_id: latest_event.backfill_lifecycle_event_id,
        run_id: run_id,
        job_id: backfill_lifecycle_group_job_id(job),
        job_status: backfill_lifecycle_group_job_status(job),
        job_started_at: backfill_lifecycle_group_job_started_at(job),
        job_completed_at: backfill_lifecycle_group_job_completed_at(job)
      }
    end)
  end

  defp backfill_lifecycle_group_item_sort_key(event) do
    {backfill_lifecycle_payload_value(event.payload, :request_item_index) || 0,
     event.point_id || event.observable_id || event.backfill_run_id}
  end

  defp backfill_lifecycle_group_item_label(latest_event, requested_event) do
    index =
      backfill_lifecycle_payload_value(latest_event.payload, :request_item_index) ||
        backfill_lifecycle_payload_value(requested_event.payload, :request_item_index)

    point =
      latest_event.point_id ||
        latest_event.observable_id ||
        requested_event.point_id ||
        requested_event.observable_id ||
        latest_event.backfill_run_id ||
        requested_event.backfill_run_id

    [index, point]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(":")
  end

  defp backfill_lifecycle_group_job_id(job_result) do
    case job_result do
      {:ok, job} -> job.job_id
      {:error, _reason} -> nil
    end
  end

  defp backfill_lifecycle_group_job_status(job_result) do
    case job_result do
      {:ok, job} -> Atom.to_string(job.status)
      {:error, _reason} -> "missing"
    end
  end

  defp backfill_lifecycle_group_job_started_at({:ok, job}), do: job.started_at
  defp backfill_lifecycle_group_job_started_at({:error, _reason}), do: nil

  defp backfill_lifecycle_group_job_completed_at({:ok, job}), do: job.completed_at
  defp backfill_lifecycle_group_job_completed_at({:error, _reason}), do: nil

  defp backfill_lifecycle_group_job_time_token(_label, nil), do: nil

  defp backfill_lifecycle_group_job_time_token(label, %DateTime{} = value) do
    "#{label}=#{DateTime.to_iso8601(value)}"
  end

  defp backfill_lifecycle_group_job_text_token(_label, nil), do: nil
  defp backfill_lifecycle_group_job_text_token(_label, ""), do: nil

  defp backfill_lifecycle_group_job_text_token(label, value) when is_binary(value) do
    "#{label}=#{value}"
  end

  defp backfill_lifecycle_group_job(run_id) when is_binary(run_id) and run_id != "" do
    Jobs.fetch_job_for_run(:telemetry_historical_data_workflow, run_id)
  end

  defp backfill_lifecycle_group_job(_run_id), do: {:error, :missing_run_id}

  defp backfill_lifecycle_group_job_status_order("queued"), do: {0, "queued"}
  defp backfill_lifecycle_group_job_status_order("running"), do: {1, "running"}
  defp backfill_lifecycle_group_job_status_order("completed"), do: {2, "completed"}
  defp backfill_lifecycle_group_job_status_order("failed"), do: {3, "failed"}
  defp backfill_lifecycle_group_job_status_order("missing"), do: {4, "missing"}
  defp backfill_lifecycle_group_job_status_order(status), do: {5, status}

  defp blank_text?(nil), do: true
  defp blank_text?(""), do: true
  defp blank_text?(_value), do: false

  defp backfill_lifecycle_group_retried_items(group_events) when is_list(group_events) do
    group_events
    |> backfill_lifecycle_group_resolution_items(
      :retry_source_event_id,
      &backfill_lifecycle_group_retry_item/2
    )
  end

  defp backfill_lifecycle_group_corrected_items(group_events) when is_list(group_events) do
    group_events
    |> backfill_lifecycle_group_resolution_items(
      :corrects_event_id,
      &backfill_lifecycle_group_correction_item/2
    )
  end

  defp backfill_lifecycle_group_correction_tasks(group_events) when is_list(group_events) do
    group_events
    |> backfill_lifecycle_group_resolution_items(
      :corrects_event_id,
      &backfill_lifecycle_group_correction_task_item/2
    )
  end

  defp backfill_lifecycle_group_resolution_items(group_events, source_key, format_fun) do
    source_failed_event_by_id =
      group_events
      |> Enum.filter(&(backfill_lifecycle_payload_value(&1.payload, :stage) == "failed"))
      |> Map.new(&{&1.backfill_lifecycle_event_id, &1})

    group_events
    |> Enum.reduce(%{}, fn event, latest_event_by_source_id ->
      source_event_id = backfill_lifecycle_payload_value(event.payload, source_key)

      if Map.has_key?(source_failed_event_by_id, source_event_id) do
        Map.put(latest_event_by_source_id, source_event_id, event)
      else
        latest_event_by_source_id
      end
    end)
    |> Map.values()
    |> Enum.sort_by(fn event ->
      source_event_id = backfill_lifecycle_payload_value(event.payload, source_key)
      source_event = Map.fetch!(source_failed_event_by_id, source_event_id)
      backfill_lifecycle_group_item_sort_key(source_event)
    end)
    |> Enum.map(fn event ->
      source_event_id = backfill_lifecycle_payload_value(event.payload, source_key)
      source_event = Map.fetch!(source_failed_event_by_id, source_event_id)
      format_fun.(source_event, event)
    end)
    |> case do
      [] -> nil
      items -> Enum.join(items, "; ")
    end
  end

  defp backfill_lifecycle_group_retry_item(source_event, retry_event) do
    [
      backfill_lifecycle_group_resolution_item_label(source_event),
      source_event.backfill_run_id,
      "retried",
      backfill_lifecycle_payload_value(retry_event.payload, :retry_job_status),
      backfill_lifecycle_payload_value(retry_event.payload, :retry_job_id)
    ]
    |> Enum.reject(&blank_text?/1)
    |> Enum.join(" ")
  end

  defp backfill_lifecycle_group_correction_item(source_event, correction_event) do
    [
      backfill_lifecycle_group_resolution_item_label(source_event),
      source_event.backfill_run_id,
      "corrected",
      correction_event.backfill_run_id,
      backfill_lifecycle_payload_value(correction_event.payload, :stage),
      backfill_lifecycle_payload_value(correction_event.payload, :corrects_job_id)
    ]
    |> Enum.reject(&blank_text?/1)
    |> Enum.join(" ")
  end

  defp backfill_lifecycle_group_correction_task_item(source_event, correction_event) do
    stage = backfill_lifecycle_payload_value(correction_event.payload, :stage)

    [
      backfill_lifecycle_group_resolution_item_label(source_event),
      source_event.backfill_run_id,
      "replacement",
      correction_event.backfill_run_id,
      "stage",
      stage,
      "next",
      backfill_lifecycle_group_correction_next_action(stage)
    ]
    |> Enum.reject(&blank_text?/1)
    |> Enum.join(" ")
  end

  defp backfill_lifecycle_group_correction_next_action("requested"), do: "approve"
  defp backfill_lifecycle_group_correction_next_action("approved"), do: "start"
  defp backfill_lifecycle_group_correction_next_action("started"), do: "complete"
  defp backfill_lifecycle_group_correction_next_action("retried"), do: "complete"
  defp backfill_lifecycle_group_correction_next_action("completed"), do: "done"
  defp backfill_lifecycle_group_correction_next_action("failed"), do: "review"
  defp backfill_lifecycle_group_correction_next_action(_stage), do: "inspect"

  defp backfill_lifecycle_group_resolution_item_label(event) do
    event.point_id || event.observable_id || event.backfill_run_id
  end

  defp telemetry_backfill_lifecycle_retry_rows(event) do
    [
      row(
        "Workflow retry action",
        backfill_lifecycle_payload_value(event.payload, :retry_action)
      ),
      row(
        "Workflow retry source event",
        backfill_lifecycle_payload_value(event.payload, :retry_source_event_id)
      ),
      row(
        "Workflow retry source event type",
        backfill_lifecycle_payload_value(event.payload, :retry_source_event_type)
      ),
      row("Workflow retry job", backfill_lifecycle_payload_value(event.payload, :retry_job_id)),
      row(
        "Workflow retry job status",
        backfill_lifecycle_payload_value(event.payload, :retry_job_status)
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp telemetry_backfill_lifecycle_missing_replacement_rows(event) do
    [
      row(
        "Missing replacement action",
        backfill_lifecycle_payload_value(event.payload, :missing_replacement_action)
      ),
      row(
        "Missing replacement source event",
        backfill_lifecycle_payload_value(event.payload, :missing_replacement_source_event_id)
      ),
      row(
        "Missing replacement source event type",
        backfill_lifecycle_payload_value(event.payload, :missing_replacement_source_event_type)
      ),
      row(
        "Missing replacement run",
        backfill_lifecycle_payload_value(event.payload, :missing_replacement_run_id)
      ),
      row(
        "Missing replacement expected job type",
        backfill_lifecycle_payload_value(event.payload, :missing_replacement_expected_job_type)
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp telemetry_backfill_lifecycle_stale_replacement_rows(event) do
    [
      row(
        "Stale replacement action",
        backfill_lifecycle_payload_value(event.payload, :stale_replacement_action)
      ),
      row(
        "Stale replacement source event",
        backfill_lifecycle_payload_value(event.payload, :stale_replacement_source_event_id)
      ),
      row(
        "Stale replacement source event type",
        backfill_lifecycle_payload_value(event.payload, :stale_replacement_source_event_type)
      ),
      row(
        "Stale replacement run",
        backfill_lifecycle_payload_value(event.payload, :stale_replacement_run_id)
      ),
      row(
        "Stale replacement job",
        backfill_lifecycle_payload_value(event.payload, :stale_replacement_job_id)
      ),
      row(
        "Stale replacement job status",
        backfill_lifecycle_payload_value(event.payload, :stale_replacement_job_status)
      ),
      row(
        "Stale replacement job started",
        backfill_lifecycle_payload_value(event.payload, :stale_replacement_job_started_at)
      ),
      row(
        "Stale replacement job age seconds",
        backfill_lifecycle_payload_value(event.payload, :stale_replacement_job_age_seconds)
      ),
      row(
        "Stale replacement stale after seconds",
        backfill_lifecycle_payload_value(event.payload, :stale_replacement_stale_after_seconds)
      ),
      row(
        "Stale replacement requeued job",
        backfill_lifecycle_payload_value(event.payload, :stale_replacement_requeued_job_id)
      ),
      row(
        "Stale replacement requeued job status",
        backfill_lifecycle_payload_value(event.payload, :stale_replacement_requeued_job_status)
      ),
      row(
        "Stale replacement requeued job attempts",
        backfill_lifecycle_payload_value(
          event.payload,
          :stale_replacement_requeued_job_attempt_count
        )
      ),
      row(
        "Stale replacement requeued reason",
        backfill_lifecycle_payload_value(
          event.payload,
          :stale_replacement_requeued_failure_reason
        )
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp telemetry_backfill_lifecycle_correction_rows(event) do
    [
      row(
        "Workflow correction action",
        backfill_lifecycle_payload_value(event.payload, :recovery_action)
      ),
      row(
        "Workflow correction source",
        backfill_lifecycle_payload_value(event.payload, :correction_source)
      ),
      row(
        "Workflow correction source event type",
        backfill_lifecycle_payload_value(event.payload, :correction_source_event_type)
      ),
      row(
        "Workflow correction source run",
        backfill_lifecycle_payload_value(event.payload, :corrects_run_id)
      ),
      row(
        "Workflow correction source event",
        backfill_lifecycle_payload_value(event.payload, :corrects_event_id)
      ),
      row(
        "Workflow correction source job",
        backfill_lifecycle_payload_value(event.payload, :corrects_job_id)
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp telemetry_backfill_lifecycle_late_data_policy_rows(event) do
    [
      row(
        "Late data policy decision",
        backfill_lifecycle_payload_value(event.payload, :policy_decision)
      ),
      row(
        "Late data execution mode",
        backfill_lifecycle_payload_value(event.payload, :execution_mode)
      ),
      row(
        "Late data source event",
        backfill_lifecycle_payload_value(event.payload, :source_event_id)
      ),
      row(
        "Late data source event type",
        backfill_lifecycle_payload_value(event.payload, :source_event_type)
      ),
      row(
        "Late data selected samples",
        backfill_lifecycle_payload_value(event.payload, :selected_sample_count)
      ),
      row(
        "Late data write validity",
        backfill_lifecycle_payload_value(event.payload, :write_validity_state)
      ),
      row(
        "Late data current projection",
        backfill_lifecycle_payload_value(event.payload, :record_current_values)
      ),
      row(
        "Late data latest refresh",
        backfill_lifecycle_payload_value(event.payload, :refresh_latest_value)
      ),
      row(
        "Late data projection effect",
        backfill_lifecycle_payload_value(event.payload, :projection_effect)
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp telemetry_backfill_lifecycle_job_rows(event) do
    with run_id when is_binary(run_id) and run_id != "" <-
           telemetry_backfill_workflow_run_id(event),
         {:ok, %Jobs.Job{} = job} <-
           Jobs.fetch_job_for_run(:telemetry_historical_data_workflow, run_id) do
      [
        row("Workflow job", job.job_id),
        row("Workflow job status", job.status),
        row("Workflow job attempts", job.attempt_count),
        row("Workflow job started", job.started_at),
        row("Workflow job completed", job.completed_at),
        row("Workflow job failure", job.failure_reason)
      ]
    else
      _other -> telemetry_backfill_lifecycle_missing_job_rows(event)
    end
  end

  defp telemetry_backfill_lifecycle_missing_job_rows(%{event_type: event_type})
       when event_type in [
              :backfill_missing_replacement_inspected,
              :import_missing_replacement_inspected
            ] do
    [row("Workflow job status", "missing")]
  end

  defp telemetry_backfill_lifecycle_missing_job_rows(_event), do: []

  defp telemetry_backfill_workflow_run_id(event) do
    backfill_lifecycle_payload_value(event.payload, :run_id) || event.backfill_run_id
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

  defp backfill_lifecycle_request_item(payload) do
    case {
      backfill_lifecycle_payload_value(payload, :request_item_index),
      backfill_lifecycle_payload_value(payload, :request_item_count)
    } do
      {nil, _count} -> nil
      {_index, nil} -> nil
      {index, count} -> "#{index}/#{count}"
    end
  end

  defp backfill_lifecycle_group_retryable?(event) do
    failure =
      event.payload
      |> state_value(:source)
      |> state_value(:failure)

    case state_value(failure, :recovery_action) do
      "correct_workflow_request" ->
        false

      _recovery_action ->
        case state_value(failure, :retryable) do
          false -> false
          "false" -> false
          _other -> true
        end
    end
  end

  defp backfill_lifecycle_group_retry_ready?(event) do
    backfill_lifecycle_group_retryable?(event) and backfill_lifecycle_group_job_failed?(event)
  end

  defp backfill_lifecycle_group_job_failed?(event) do
    with run_id when is_binary(run_id) and run_id != "" <-
           telemetry_backfill_workflow_run_id(event),
         {:ok, %Jobs.Job{status: :failed}} <-
           Jobs.fetch_job_for_run(:telemetry_historical_data_workflow, run_id) do
      true
    else
      _other -> false
    end
  end

  defp backfill_lifecycle_payload_value(payload, key), do: state_value(payload, key)

  defp dashboard_context_value(payload, key) do
    payload
    |> state_value(:dashboard_context)
    |> state_value(key)
  end

  defp comparison_review_origin_value(payload, key) do
    payload
    |> state_value(:comparison_review_origin)
    |> state_value(key)
  end

  defp comparison_review_request_kind(payload) do
    state_value(payload, :review_kind) || state_value(payload, :request_kind)
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

  defp operational_resource_related_links(%DataLink{} = link, persisted_resource \\ nil) do
    resource = operational_resource_context(link, persisted_resource)

    [
      related_operational_resource_link(
        link,
        :transport,
        state_value(resource, :transport_id),
        "Transport"
      ),
      related_operational_resource_link(
        link,
        :source_endpoint,
        state_value(resource, :source_endpoint_id),
        "Source endpoint"
      ),
      related_operational_resource_link(
        link,
        :ground_station,
        state_value(resource, :ground_station_id),
        "Ground station"
      ),
      related_operational_resource_link(
        link,
        :link,
        state_value(resource, :link_id),
        "Link"
      )
    ]
  end

  defp related_operational_resource_link(
         %DataLink{target: target, target_id: target_id},
         target,
         target_id,
         _label
       ),
       do: nil

  defp related_operational_resource_link(%DataLink{} = link, target, target_id, label) do
    related_link(link, target, target_id, label)
  end

  defp operational_resource_actions(%DataLink{} = link, persisted_resource \\ nil) do
    data_context = context_value(link.context, :data) || %{}
    resource = operational_resource_context(link, persisted_resource)

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
      operational_resource_action(
        "dashboard-operational-resource-inventory",
        "View source inventory",
        :source_inventory,
        inventory_query,
        link.context
      ),
      operational_resource_action(
        "dashboard-operational-resource-health",
        "View source health",
        :source_health,
        source_query,
        link.context
      )
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp operational_resource_action(_action_id, _label, _target, query, _context)
       when map_size(query) == 0,
       do: nil

  defp operational_resource_action(action_id, label, target, query, context) do
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

  defp operational_resource_context(%DataLink{} = link, persisted_resource) do
    link.context
    |> context_value(:operational_resource)
    |> merge_operational_resource_context(link, persisted_resource)
  end

  defp merge_operational_resource_context(context, %DataLink{} = link, persisted_resource) do
    context
    |> context_map_or_empty()
    |> Map.put_new(:transport_id, operational_resource_transport_id(link, persisted_resource))
    |> Map.put_new(
      :source_endpoint_id,
      operational_resource_source_endpoint_id(persisted_resource)
    )
    |> Map.put_new(:ground_station_id, operational_resource_ground_station_id(persisted_resource))
    |> Map.put_new(:link_id, operational_resource_link_id(persisted_resource))
  end

  defp operational_resource_transport_id(
         %DataLink{target: :transport, target_id: target_id},
         _resource
       ),
       do: target_id

  defp operational_resource_transport_id(_link, %GroundStation{} = ground_station),
    do: metadata_value(ground_station.metadata, [:transport_id])

  defp operational_resource_transport_id(_link, resource)
       when is_map(resource) and not is_struct(resource),
       do: state_value(resource, :transport_id)

  defp operational_resource_transport_id(_link, _resource), do: nil

  defp operational_resource_source_endpoint_id(%Transport{} = transport),
    do: metadata_value(transport.metadata, [:source_endpoint_id, :source_endpoint_ref])

  defp operational_resource_source_endpoint_id(%SourceEndpoint{} = source_endpoint),
    do: source_endpoint.source_endpoint_id

  defp operational_resource_source_endpoint_id(%GroundStation{} = ground_station),
    do: metadata_value(ground_station.metadata, [:source_endpoint_id, :source_endpoint_ref])

  defp operational_resource_source_endpoint_id(resource)
       when is_map(resource) and not is_struct(resource),
       do: state_value(resource, :source_endpoint_id)

  defp operational_resource_source_endpoint_id(_resource), do: nil

  defp operational_resource_ground_station_id(%Transport{} = transport),
    do: metadata_value(transport.metadata, [:ground_station_id, :antenna_id])

  defp operational_resource_ground_station_id(%SourceEndpoint{} = source_endpoint),
    do: metadata_value(source_endpoint.metadata, [:ground_station_id, :antenna_id])

  defp operational_resource_ground_station_id(%GroundStation{} = ground_station),
    do: ground_station.ground_station_id

  defp operational_resource_ground_station_id(resource)
       when is_map(resource) and not is_struct(resource),
       do: state_value(resource, :ground_station_id)

  defp operational_resource_ground_station_id(_resource), do: nil

  defp operational_resource_link_id(%Transport{} = transport),
    do: metadata_value(transport.metadata, [:link_id, :link_assignment_id, :link_assignment_ref])

  defp operational_resource_link_id(%SourceEndpoint{} = source_endpoint),
    do:
      metadata_value(source_endpoint.metadata, [
        :link_id,
        :link_assignment_id,
        :link_assignment_ref
      ])

  defp operational_resource_link_id(%GroundStation{} = ground_station),
    do:
      metadata_value(ground_station.metadata, [
        :link_id,
        :link_assignment_id,
        :link_assignment_ref
      ])

  defp operational_resource_link_id(resource) when is_map(resource) and not is_struct(resource),
    do: state_value(resource, :link_id)

  defp operational_resource_link_id(_resource), do: nil

  defp routing_rule_for_link_assignment(
         organization_id,
         mission_id,
         %LinkAssignment{} = assignment
       ) do
    RoutingRuleStore.list_routing_rules(organization_id, mission_id)
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

  defp telemetry_sample_related_links(%DataLink{} = link, sample, organization_id, mission_id) do
    [
      related_link(link, :telemetry_point, sample.point_id, "Telemetry point"),
      related_link(link, :raw_evidence, sample.evidence_id, "Raw evidence")
      | sample_limit_event_links(link, sample, organization_id, mission_id)
    ]
  end

  defp sample_limit_event_links(%DataLink{} = link, sample, organization_id, mission_id) do
    TelemetryLimitEventRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.source_sample_type == "telemetry_sample" and row.sample_id == ^sample.sample_id
    )
    |> order_by([row], desc: row.receipt_time)
    |> limit(5)
    |> Repo.all()
    |> Enum.map(fn event_row ->
      event = TelemetryLimitEventRow.to_domain(event_row)
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

  defp limit_event_related_links(%DataLink{} = link, event) do
    [
      related_link(link, :telemetry_point, event.point_id, "Telemetry point"),
      limit_event_sample_link(link, event),
      related_link(link, :limit_definition, event.limit_definition_id, "Limit definition")
    ]
  end

  defp limit_event_sample_link(
         %DataLink{} = link,
         %{source_sample_type: :telemetry_sample} = event
       ) do
    related_link(link, :telemetry_sample, event.sample_id, "Telemetry sample")
  end

  defp limit_event_sample_link(_link, _event), do: nil

  defp limit_definition_related_links(%DataLink{} = link, definition) do
    [
      related_link(link, :telemetry_point, definition.point_id, "Telemetry point")
    ]
  end

  defp limit_definition_lifecycle_event_related_links(%DataLink{} = link, event) do
    [
      related_link(link, :telemetry_point, event.point_id, "Telemetry point"),
      related_link(link, :limit_definition, event.limit_definition_id, "Limit definition"),
      related_link(
        link,
        :operational_event,
        "operational_event:limit_definition_lifecycle_event:#{event.limit_definition_lifecycle_event_id}",
        "Operational event",
        :source_event
      )
    ]
  end

  defp limit_definition_interval_related_links(
         %DataLink{} = link,
         %DefinitionInterval{} = interval
       ) do
    [
      related_link(link, :telemetry_point, interval.point_id, "Telemetry point"),
      related_link(link, :limit_definition, interval.limit_definition_id, "Limit definition"),
      related_link(
        link,
        :limit_definition_lifecycle_event,
        interval.limit_definition_lifecycle_event_id,
        "Limit definition lifecycle event",
        :source_event
      ),
      related_link(
        link,
        :operational_event,
        "operational_event:limit_definition_lifecycle_event:#{interval.limit_definition_lifecycle_event_id}",
        "Operational event",
        :source_event
      )
    ]
  end

  defp mission_event_related_links(%DataLink{} = link, event) do
    [
      mission_event_source_link(link, event),
      mission_event_subject_link(link, event),
      contact_related_link(link, event.scheduled_contact_id, event.realized_contact_id)
    ]
  end

  defp mission_event_source_link(
         %DataLink{} = link,
         %{source_record_kind: :limit_event, source_record_id: source_record_id}
       ) do
    related_link(link, :limit_event, source_record_id, "Limit event")
  end

  defp mission_event_source_link(
         %DataLink{} = link,
         %{source_record_kind: :operational_event, source_record_id: source_record_id}
       ) do
    related_link(link, :operational_event, source_record_id, "Operational event", :source_event)
  end

  defp mission_event_source_link(_link, _event), do: nil

  defp mission_event_subject_link(
         %DataLink{} = link,
         %{subject_kind: :telemetry_point, subject_id: subject_id}
       ) do
    related_link(link, :telemetry_point, subject_id, "Telemetry point")
  end

  defp mission_event_subject_link(_link, _event), do: nil

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

  defp find_effective_interval(%DataLink{} = link, organization_id, mission_id) do
    link.target
    |> effective_intervals(organization_id, mission_id, effective_interval_opts(link))
    |> Enum.find(&(&1.interval_id == link.target_id))
  end

  defp effective_interval_opts(%DataLink{} = link) do
    opts = [event_limit: 1_000]

    case replay_run_id(link.context) do
      replay_run_id when is_binary(replay_run_id) and replay_run_id != "" ->
        Keyword.put(opts, :replay_run_id, replay_run_id)

      _other ->
        opts
    end
  end

  defp effective_intervals(:binding_set_interval, organization_id, mission_id, opts),
    do: OperationalEvents.binding_set_intervals(organization_id, mission_id, opts)

  defp effective_intervals(:application_binding_interval, organization_id, mission_id, opts),
    do: OperationalEvents.application_binding_intervals(organization_id, mission_id, opts)

  defp effective_intervals(:catalog_revision_interval, organization_id, mission_id, opts),
    do: OperationalEvents.catalog_revision_intervals(organization_id, mission_id, opts)

  defp effective_intervals(:source_binding_interval, organization_id, mission_id, opts),
    do: OperationalEvents.source_binding_intervals(organization_id, mission_id, opts)

  defp effective_intervals(:source_health_interval, organization_id, mission_id, opts),
    do: OperationalEvents.source_health_intervals(organization_id, mission_id, opts)

  defp effective_intervals(:transport_execution_interval, organization_id, mission_id, opts),
    do: OperationalEvents.transport_execution_intervals(organization_id, mission_id, opts)

  defp effective_intervals(target, organization_id, mission_id, opts)
       when target in [
              :transport_connection_state_interval,
              :ground_station_connection_state_interval
            ],
       do: OperationalEvents.connection_state_intervals(organization_id, mission_id, opts)

  defp effective_intervals(
         :ground_station_antenna_pointing_state_interval,
         organization_id,
         mission_id,
         opts
       ) do
    opts = Keyword.put(opts, :observable_id, ["ground.station.antenna_pointing_state"])

    OperationalEvents.operational_observable_state_intervals(organization_id, mission_id, opts)
  end

  defp effective_intervals(target, organization_id, mission_id, opts)
       when target in [:link_rf_lock_state_interval, :link_frame_sync_state_interval],
       do: OperationalEvents.link_rf_state_intervals(organization_id, mission_id, opts)

  defp effective_intervals(_target, _organization_id, _mission_id, _opts), do: []

  defp find_source_binding_data_interval(target_id, organization_id, mission_id) do
    DataSources.list_data_binding_intervals(organization_id, mission_id)
    |> Enum.find(&(source_binding_data_interval_id(&1) == target_id))
  end

  defp source_binding_data_interval_id(%DataBindingInterval{} = interval) do
    "effective_interval:source_binding:#{interval.data_binding_event_id}"
  end

  defp limit_definition_interval_activation_key(target_id) do
    case string_id(target_id) do
      "effective_interval:limit_definition:" <> activation_key -> activation_key
      activation_key -> activation_key
    end
  end

  defp fetch_limit_definition_for_interval(event, organization_id, mission_id) do
    case Limits.fetch_limit_definition(
           organization_id,
           mission_id,
           event.limit_definition_id,
           event.limit_definition_version,
           include_unscoped?: true
         ) do
      {:ok, definition} -> definition
      {:error, :limit_definition_not_found} -> nil
    end
  end

  defp source_binding_event_related_links(%DataLink{} = link, event) do
    [
      related_link(
        link,
        :operational_event,
        "operational_event:dashboard_data_binding_event:#{event.data_binding_event_id}",
        "Operational event",
        :source_event
      )
    ]
  end

  defp effective_interval_related_links(%DataLink{} = link, %EffectiveInterval{} = interval) do
    [
      related_link(
        link,
        :operational_event,
        interval.source_event_id,
        "Source event",
        :source_event
      ),
      related_link(
        link,
        :operational_event,
        interval.superseded_by_event_id,
        "Superseding event",
        :follow_up_event
      )
      | effective_interval_resource_links(link, interval)
    ]
  end

  defp effective_interval_resource_links(
         %DataLink{} = link,
         %EffectiveInterval{kind: :application_binding, payload: payload}
       ) do
    [
      related_link(
        link,
        :source_endpoint,
        context_value(payload, :source_endpoint_ref),
        "Source endpoint"
      )
    ]
  end

  defp effective_interval_resource_links(
         %DataLink{} = link,
         %EffectiveInterval{kind: :transport_execution, payload: payload}
       ) do
    [
      related_link(
        link,
        :transport,
        context_value(payload, :capability_instance_id),
        "Transport"
      ),
      related_link(
        link,
        :contact,
        context_value(payload, :realized_contact_id) || context_value(payload, :contact_id),
        "Contact"
      )
    ]
  end

  defp effective_interval_resource_links(_link, _interval), do: []

  defp source_binding_data_interval_related_links(
         %DataLink{} = link,
         %DataBindingInterval{} = interval
       ) do
    [
      related_link(
        link,
        :source_binding_event,
        interval.data_binding_event_id,
        "Source binding event",
        :source_event
      ),
      related_link(
        link,
        :operational_event,
        "operational_event:dashboard_data_binding_event:#{interval.data_binding_event_id}",
        "Operational event",
        :source_event
      )
    ]
  end

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

  defp contact_related_link(%DataLink{} = link, scheduled_contact_id, realized_contact_id) do
    related_link(
      link,
      :contact,
      realized_contact_id || scheduled_contact_id,
      "Contact"
    )
  end

  defp related_link(%DataLink{} = source_link, target, target_id, label, relationship_kind \\ nil) do
    case string_id(target_id) do
      nil ->
        nil

      target_id ->
        %DataLink{
          link_id: related_link_id(target, target_id),
          label: label,
          target: target,
          target_id: target_id,
          relationship_kind: relationship_kind,
          context: source_link.context,
          presentation: :side_panel,
          source: :annotation
        }
    end
  end

  defp related_link_id(target, target_id), do: "inspector:#{target}:#{target_id}"

  defp dedupe_related_links(links) do
    Enum.uniq_by(links, &{&1.target, &1.target_id})
  end

  defp source_context(context) when is_map(context) do
    %{
      realm: nested_context_value(context, :data, :realm),
      data_view: nested_context_value(context, :data, :view),
      data_source_id: nested_context_value(context, :data, :data_source_id),
      source_binding_id: nested_context_value(context, :data, :source_binding_id),
      time_mode: nested_context_value(context, :time, :mode),
      time_axis: nested_context_value(context, :time, :axis),
      replay_run_id: replay_run_id(context),
      placement_id: nested_context_value(context, :selection, :placement_id),
      timestamp_ms: nested_context_value(context, :selection, :timestamp_ms)
    }
    |> Enum.flat_map(fn
      {_key, value} when value in [nil, ""] -> []
      {key, value} -> [{key, value_text(value)}]
    end)
    |> Map.new()
  end

  defp source_context(_context), do: %{}

  defp context_rows(context) when is_map(context) do
    [
      row("Organization", context_value(context, :organization_id)),
      row("Mission", context_value(context, :mission_id)),
      row("Source request", context_value(context, :source_request_id)),
      row("Logical source", context_value(context, :logical_source)),
      row("Observable", context_value(context, :observable_id)),
      row("Scope", context_value(context, :scope) |> primary_scope()),
      row("Time mode", nested_context_value(context, :time, :mode)),
      row("Time axis", nested_context_value(context, :time, :axis)),
      row("Replay run", replay_run_id(context)),
      row("From", nested_context_value(context, :time, :from)),
      row("To", nested_context_value(context, :time, :to)),
      row("Data realm", nested_context_value(context, :data, :realm)),
      row("Data view", nested_context_value(context, :data, :view)),
      row("Series role", nested_context_value(context, :selection, :series_role)),
      row("Compare of", nested_context_value(context, :selection, :compare_of)),
      row("Data source", nested_context_value(context, :data, :data_source_id)),
      row("Source binding", nested_context_value(context, :data, :source_binding_id)),
      row("Limit mode", nested_context_value(context, :limit, :semantics_mode)),
      row("Sampling", nested_context_value(context, :sampling, :mode))
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp context_rows(_context), do: []

  defp navigation_context(context) when is_map(context) do
    from =
      context
      |> nested_context_value(:navigation, :from)
      |> navigation_from_context()

    trail =
      context
      |> nested_context_value(:navigation, :trail)
      |> navigation_trail_context()

    %{from: from, trail: trail}
    |> Enum.reject(fn
      {_key, value} when value in [nil, []] -> true
      {_key, value} when is_map(value) -> map_size(value) == 0
      _entry -> false
    end)
    |> Map.new()
    |> case do
      navigation when map_size(navigation) > 0 -> navigation
      _empty -> nil
    end
  end

  defp navigation_context(_context), do: nil

  defp navigation_from_context(from) when is_map(from) do
    %{
      link_id: context_value(from, :link_id),
      target: context_value(from, :target),
      target_id: context_value(from, :target_id),
      label: context_value(from, :label),
      relationship_kind: context_value(from, :relationship_kind),
      relationship_label: context_value(from, :relationship_label)
    }
    |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
    |> Map.new()
  end

  defp navigation_from_context(_from), do: %{}

  defp navigation_trail_context(entries) when is_list(entries) do
    entries
    |> Enum.map(&navigation_from_context/1)
    |> Enum.reject(&(&1 == %{}))
    |> Enum.take(-3)
  end

  defp navigation_trail_context(_entries), do: []

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

  defp fetch_contact(contact_id, organization_id, mission_id) do
    fetch_scheduled_contact(contact_id, organization_id, mission_id) ||
      fetch_realized_contact(contact_id, organization_id, mission_id)
  end

  defp fetch_scheduled_contact(contact_id, organization_id, mission_id) do
    ScheduledContactRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.scheduled_contact_id == ^contact_id
    )
    |> Repo.one()
    |> case do
      %ScheduledContactRow{} = row -> {:scheduled, ScheduledContactRow.to_domain(row)}
      nil -> nil
    end
  end

  defp fetch_realized_contact(contact_id, organization_id, mission_id) do
    RealizedContactRow
    |> where(
      [row],
      row.organization_id == ^organization_id and row.mission_id == ^mission_id and
        row.realized_contact_id == ^contact_id
    )
    |> Repo.one()
    |> case do
      %RealizedContactRow{} = row -> {:realized, RealizedContactRow.to_domain(row)}
      nil -> nil
    end
  end

  defp string_id(value) when is_binary(value) and value != "", do: value
  defp string_id(_value), do: nil

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

  defp unsupported_message(%DataLink{} = link) do
    "Dashboard data-link target #{target_text(link.target)} is not supported by the inspector yet."
  end

  defp title(%DataLink{label: label}) when is_binary(label) and label != "", do: label
  defp title(%DataLink{target: target}), do: target_text(target)

  defp row(_label, nil), do: nil
  defp row(_label, ""), do: nil
  defp row(label, value), do: %{label: label, value: value_text(value)}

  defp primary_scope(nil), do: nil
  defp primary_scope(%{primary: primary}), do: primary_scope(primary)
  defp primary_scope(%{"primary" => primary}), do: primary_scope(primary)

  defp primary_scope(%{} = primary) do
    kind = context_value(primary, :kind)
    mode = context_value(primary, :mode)
    ids = context_value(primary, :ids)

    [kind, mode, ids]
    |> Enum.reject(&is_nil/1)
    |> Enum.map_join(":", &value_text/1)
  end

  defp primary_scope(other), do: other

  defp nested_context_value(context, section, key) do
    context
    |> context_value(section)
    |> context_value(key)
  end

  defp replay_run_id(context) do
    nested_context_value(context, :time, :replay_run_id) ||
      nested_context_value(context, :data, :replay_run_id) ||
      context_value(context, :replay_run_id)
  end

  defp context_value(context, key) when is_map(context) and is_atom(key) do
    Map.get(context, key, Map.get(context, Atom.to_string(key)))
  end

  defp context_value(_context, _key), do: nil

  defp context_map_or_empty(context) when is_map(context), do: context
  defp context_map_or_empty(_context), do: %{}

  defp metadata_value(metadata, keys) when is_list(keys) do
    Enum.find_value(keys, &metadata_value(metadata, &1))
  end

  defp metadata_value(metadata, key) when is_map(metadata) and is_atom(key) do
    Map.get(metadata, key, Map.get(metadata, Atom.to_string(key)))
  end

  defp metadata_value(_metadata, _key), do: nil

  defp state_value(state, key), do: context_value(state, key)

  defp data_ref_text(nil), do: nil
  defp data_ref_text(value) when is_atom(value), do: Atom.to_string(value)
  defp data_ref_text(value) when is_binary(value), do: value
  defp data_ref_text(value), do: to_string(value)

  defp value_text(value) when is_boolean(value), do: to_string(value)
  defp value_text(value) when is_atom(value), do: Atom.to_string(value)
  defp value_text(value) when is_binary(value), do: value
  defp value_text(value) when is_integer(value), do: Integer.to_string(value)
  defp value_text(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 3)
  defp value_text(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp value_text(values) when is_list(values), do: Enum.map_join(values, ",", &value_text/1)
  defp value_text(value), do: inspect(value)

  defp target_text(nil), do: "unknown"

  defp target_text(target) when is_atom(target) do
    target
    |> Atom.to_string()
    |> String.replace("_", " ")
  end

  defp target_text(target) when is_binary(target), do: String.replace(target, "_", " ")

  defp format_key(key) do
    key
    |> Atom.to_string()
    |> String.replace("_", " ")
  end
end
