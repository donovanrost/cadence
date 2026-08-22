defmodule Cadence.Dev.SreObservabilityDemo do
  alias Cadence.Reads.Telemetry, as: TelemetryReads
  @moduledoc false

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Accounts.OrganizationMembership
  alias Cadence.Accounts.OrganizationMembershipRow
  alias Cadence.Contacts.{Path, ProviderBinding, RealizedContact, ScheduledContact}
  alias Cadence.Commanding.{CommandQueueEntry, CommandQueueEntryRow}
  alias Cadence.Commanding.{CommandRequest, CommandRequestRow}
  alias Cadence.Control.MissionRuntimeReconciler
  alias Cadence.Control.Missions, as: ControlMissions
  alias Cadence.Dashboards.{Document, Management, Placement, Section, WidgetDef}
  alias Cadence.Management.DataSources
  alias Cadence.Limits.Event, as: LimitEvent
  alias Cadence.Limits.Store, as: LimitStore
  alias Cadence.Missions.Mission
  alias Cadence.Observability
  alias Cadence.Organizations.Organization
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.PacketDefinition
  alias Cadence.Runtime.MissionRuntimeSpec

  require Logger

  @definitions """
  version: "1.0.0"
  packets:
    - name: SRE_DEMO_HOUSEKEEPING
      apid: 42
      items:
        - name: uptime_seconds
          bit_offset: 0
          bit_size: 16
          data_type: uint
          endianness: big
        - name: battery_voltage
          bit_offset: 16
          bit_size: 16
          data_type: uint
          endianness: big
  """

  @frame_size 64
  @provider_binding_id "sre-demo-tcp-downlink"

  def run do
    Logger.configure(level: demo_log_level())
    configure_shared_demo_persistence()

    run_id =
      System.get_env("CADENCE_DASHBOARD_DEMO_RUN_ID") ||
        System.get_env("CADENCE_SRE_DEMO_RUN_ID") || run_id()

    rate_hz =
      positive_float_env(
        "CADENCE_DASHBOARD_DEMO_RATE_HZ",
        positive_float_env("CADENCE_SRE_DEMO_RATE_HZ", 2.0)
      )

    duration_seconds =
      positive_integer_env(
        "CADENCE_DASHBOARD_DEMO_CONTACT_SECONDS",
        positive_integer_env("CADENCE_SRE_DEMO_CONTACT_SECONDS", 3600)
      )

    ids = %{
      organization_id: "org-sre-demo-#{run_id}",
      mission_id: "mission-sre-demo-#{run_id}",
      spacecraft_id: "spacecraft-sre-demo-#{run_id}",
      source_endpoint_id: "source-sre-demo-#{run_id}",
      binding_set_id: "binding-sre-demo-#{run_id}",
      dashboard_id: "dashboard-sre-demo-#{run_id}",
      investigation_dashboard_id: "dashboard-sre-demo-investigation-#{run_id}",
      scheduled_contact_id: "contact-sre-demo-#{run_id}",
      downlink_path_id: "path-sre-demo-downlink-#{run_id}",
      command_request_id: "command-sre-demo-#{run_id}",
      command_queue_entry_id: "command-queue-sre-demo-#{run_id}",
      limit_event_id: "limit-event-sre-demo-#{run_id}",
      nominal_limit_event_id: "limit-event-sre-demo-nominal-#{run_id}",
      backfill_run_id: "backfill-sre-demo-#{run_id}"
    }

    {:ok, _started} = Application.ensure_all_started(:cadence)
    {:ok, _started} = Application.ensure_all_started(:cadence_simulator)

    result =
      Observability.with_root_span(
        "cadence.sre_demo.setup",
        %{attributes: %{"cadence.demo.run.id" => run_id}},
        fn -> setup(ids, rate_hz, duration_seconds) end
      )

    case result do
      {:ok, state} ->
        announce(state)
        monitor(state)

      {:error, reason} ->
        Observability.log(
          :error,
          "cadence.sre_demo.setup_failed",
          "Cadence SRE observability demo failed to start",
          error_class: Observability.error_class(reason)
        )

        raise "SRE observability demo failed: #{inspect(reason)}"
    end
  end

  defp setup(ids, rate_hz, duration_seconds) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    with :ok <- ensure_data_sources(),
         {:ok, _organization} <- persist_organization(ids),
         :ok <- ensure_browser_access(ids),
         {:ok, _mission} <- persist_mission(ids),
         {:ok, _spacecraft} <- persist_spacecraft(ids),
         {:ok, source_endpoint} <- persist_source_endpoint(ids),
         {:ok, _binding_set} <- activate_packet_binding(ids),
         {:ok, scheduled_contact} <-
           schedule_contact(ids, source_endpoint, now, duration_seconds),
         {:ok, realized_contact} <- await_realized_contact(ids, scheduled_contact),
         {:ok, path_snapshot} <- fetch_downlink_path(ids, realized_contact),
         {:ok, port} <- listening_port(path_snapshot),
         {:ok, simulator} <- start_simulator(ids, port, rate_hz),
         :ok <- await_telemetry_source_ready(ids),
         {:ok, dashboards} <- persist_native_dashboards(ids),
         :ok <- publish_dashboards(ids, dashboards),
         :ok <- persist_alarm_context(ids, now),
         :ok <- persist_command_context(ids, now),
         :ok <- persist_source_health_context(ids, now),
         :ok <- persist_historical_data_context(ids, now),
         {:ok, management} <- persist_dashboard_management_context(ids, dashboards, now) do
      Observability.log(
        :info,
        "cadence.sre_demo.started",
        "Cadence SRE observability demo started",
        mission_id: ids.mission_id,
        realized_contact_id: realized_contact.realized_contact_id,
        path_id: ids.downlink_path_id
      )

      {:ok,
       %{
         ids: ids,
         port: port,
         rate_hz: rate_hz,
         dashboard: dashboards.overview,
         dashboards: dashboards,
         management: management,
         simulator: simulator,
         scheduled_contact: scheduled_contact,
         realized_contact: realized_contact
       }}
    end
  end

  defp persist_organization(ids) do
    ids.organization_id
    |> then(fn organization_id ->
      Organization.new(%{
        organization_id: organization_id,
        slug: organization_id,
        display_name: "SRE Observability Demo"
      })
    end)
    |> Cadence.Organizations.persist_organization()
  end

  defp persist_mission(ids) do
    ids.mission_id
    |> then(fn mission_id ->
      Mission.new(%{
        mission_id: mission_id,
        organization_id: ids.organization_id,
        slug: mission_id,
        display_name: "SRE Telemetry Exercise"
      })
    end)
    |> Cadence.Missions.persist_mission()
  end

  defp ensure_browser_access(ids) do
    browser_email =
      System.get_env("CADENCE_DASHBOARD_DEMO_BROWSER_EMAIL") ||
        System.get_env("CADENCE_SRE_DEMO_BROWSER_EMAIL") ||
        System.get_env("CADENCE_ADMIN_EMAIL")

    with email when is_binary(email) <- browser_email,
         {:ok, user} <- Cadence.Accounts.fetch_user_by_email(email) do
      case Cadence.Accounts.fetch_user_membership(user.user_id, ids.organization_id) do
        {:ok, _membership} ->
          :ok

        {:error, :not_found} ->
          membership =
            OrganizationMembership.new(%{
              user_id: user.user_id,
              organization_id: ids.organization_id,
              role: :organization_admin,
              metadata: %{"source" => "sre_observability_demo"}
            })

          membership
          |> OrganizationMembershipRow.changeset()
          |> Cadence.Repo.insert()
          |> case do
            {:ok, _row} -> :ok
            {:error, reason} -> {:error, reason}
          end
      end
    else
      nil -> :ok
      {:error, :not_found} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist_spacecraft(ids) do
    spacecraft =
      Spacecraft.new(%{
        spacecraft_id: ids.spacecraft_id,
        mission_id: ids.mission_id,
        display_name: "SRE-DEMO-1",
        scid: 11
      })

    Cadence.SpacecraftStore.persist_spacecraft(ids.organization_id, spacecraft)
  end

  defp persist_source_endpoint(ids) do
    source_endpoint =
      SourceEndpoint.new(%{
        source_endpoint_id: ids.source_endpoint_id,
        mission_id: ids.mission_id,
        spacecraft_id: ids.spacecraft_id,
        source_ref: "sre-demo/tcp/downlink",
        display_name: "SRE demo telemetry endpoint"
      })

    Cadence.SourceEndpoints.persist_source_endpoint(ids.organization_id, source_endpoint)
  end

  defp activate_packet_binding(ids) do
    packet_definition =
      PacketDefinition.new(%{
        mission_id: ids.mission_id,
        packet_definition_id: "packet-sre-demo-#{ids.mission_id}",
        packet_name: "SRE_DEMO_HOUSEKEEPING",
        apid: 42,
        version: 1,
        fields: [
          %{
            field_id: "uptime_seconds",
            name: "uptime_seconds",
            offset_bits: 0,
            size_bits: 16,
            data_type: :uint
          },
          %{
            field_id: "battery_voltage",
            name: "battery_voltage",
            offset_bits: 16,
            size_bits: 16,
            data_type: :uint
          }
        ]
      })

    binding_set =
      BindingSet.new(%{
        mission_id: ids.mission_id,
        binding_set_id: ids.binding_set_id,
        version: 1,
        rules: [
          BindingRule.new(%{
            binding_rule_id: "rule-sre-demo-#{ids.mission_id}",
            handler_key: :definition_bound_telemetry,
            packet_kind: :space_packet,
            apid: 42,
            priority: 10,
            handler_configuration: packet_definition
          })
        ]
      })

    with {:ok, persisted_binding_set} <-
           Cadence.Governance.persist_binding_set(ids.organization_id, binding_set),
         content_sha256 <- MissionRuntimeSpec.content_sha256(persisted_binding_set),
         {:ok, activation} <-
           Cadence.Activations.record_binding_set_activation(
             ids.organization_id,
             ids.mission_id,
             persisted_binding_set.binding_set_id,
             persisted_binding_set.version,
             binding_set_content_sha256: content_sha256,
             metadata: %{"activated_by" => demo_actor()}
           ),
         {:ok, _mission_control} <- ControlMissions.ensure_started(ids.mission_id),
         {:ok, _generation_applied} <-
           MissionRuntimeReconciler.apply_generation(
             ids.mission_id,
             activation,
             persisted_binding_set
           ) do
      {:ok, persisted_binding_set}
    end
  end

  defp schedule_contact(ids, source_endpoint, now, duration_seconds) do
    scheduled_contact =
      ScheduledContact.new(%{
        scheduled_contact_id: ids.scheduled_contact_id,
        organization_id: ids.organization_id,
        mission_id: ids.mission_id,
        source_endpoint_refs: [source_endpoint.source_endpoint_id],
        contact_intents: [:telemetry_downlink],
        starts_at: DateTime.add(now, 2, :second),
        ends_at: DateTime.add(now, duration_seconds, :second),
        metadata: %{"purpose" => "sre_observability_demo"},
        paths: [
          Path.new(%{
            path_id: ids.downlink_path_id,
            direction: :downlink,
            selection_role: :selected,
            source_endpoint_ref: source_endpoint.source_endpoint_id,
            provider_bindings: [
              ProviderBinding.new(%{
                provider_binding_id: @provider_binding_id,
                adapter_key: :tcp_socket,
                configuration: %{
                  mode: :listen,
                  host: "127.0.0.1",
                  port: 0,
                  ingress_protocol_family: :tm,
                  frame_size: @frame_size,
                  ingress_metadata: %{frame_size: @frame_size, ocf_length: 0}
                }
              })
            ]
          })
        ]
      })

    Cadence.Contacts.persist_scheduled_contact(ids.organization_id, scheduled_contact)
  end

  defp ensure_data_sources do
    _sources = DataSources.ensure_default_managed_sources!()
    :ok
  end

  defp persist_native_dashboards(ids) do
    scope_override = %{
      primary: %{kind: :spacecraft, mode: :one, ids: [ids.spacecraft_id]}
    }

    overview = %Document{
      dashboard_id: ids.dashboard_id,
      organization_id: ids.organization_id,
      mission_id: ids.mission_id,
      name: "Flight Day 42 — Pass Overview",
      description:
        "Live spacecraft telemetry, operational state, and investigation handoffs for the active pass.",
      defaults: %{
        time: %{
          mode: :live,
          axis: :generation_time,
          refresh_ms: 1_000,
          window_seconds: 300
        },
        scope: scope_override,
        data: %{realm: :flight, source_mode: :primary, allowed_realms: [:flight]},
        limits: %{semantics_mode: :observed, limit_set_name: "FLIGHT"}
      },
      sections: [
        %Section{
          section_id: "section-pass-health",
          title: "Pass health",
          description: "The minimum telemetry needed to hold operator attention."
        },
        %Section{
          section_id: "section-engineering-detail",
          title: "Engineering detail",
          description: "Progressive detail for investigation without leaving the dashboard.",
          collapsed_by_default?: true
        }
      ],
      placements: [
        time_series_placement(
          "placement-sre-demo-uptime-trend",
          "Spacecraft Uptime",
          "SRE_DEMO_HOUSEKEEPING.uptime_seconds",
          %{x: 0, y: 0, w: 8, h: 4},
          scope_override,
          "section-pass-health"
        ),
        value_tile_placement(
          "placement-sre-demo-uptime-current",
          "Current Uptime",
          "SRE_DEMO_HOUSEKEEPING.uptime_seconds",
          %{x: 8, y: 0, w: 4, h: 2},
          scope_override,
          "section-pass-health"
        ),
        time_series_placement(
          "placement-sre-demo-battery-trend",
          "Battery Voltage",
          "SRE_DEMO_HOUSEKEEPING.battery_voltage",
          %{x: 0, y: 4, w: 8, h: 4},
          scope_override,
          "section-pass-health"
        ),
        value_tile_placement(
          "placement-sre-demo-battery-current",
          "Current Battery Voltage",
          "SRE_DEMO_HOUSEKEEPING.battery_voltage",
          %{x: 8, y: 4, w: 4, h: 2},
          scope_override,
          "section-pass-health"
        ),
        status_matrix_placement(
          "placement-sre-demo-engineering-matrix",
          "Housekeeping Status",
          [
            "SRE_DEMO_HOUSEKEEPING.uptime_seconds",
            "SRE_DEMO_HOUSEKEEPING.battery_voltage"
          ],
          %{x: 0, y: 8, w: 12, h: 3},
          scope_override,
          "section-engineering-detail"
        )
      ],
      metadata: %{
        tags: ["ops-demo", "flight-day-42", "live-telemetry", "active-pass"],
        demo_story: "active_pass"
      }
    }

    investigation = %Document{
      dashboard_id: ids.investigation_dashboard_id,
      organization_id: ids.organization_id,
      mission_id: ids.mission_id,
      name: "Flight Day 42 — Battery Investigation",
      description:
        "A focused analysis surface reached from the alarm rail without losing mission context.",
      defaults: overview.defaults,
      sections: [
        %Section{
          section_id: "section-investigation",
          title: "Battery excursion",
          description: "Correlate the active limit condition with the neighboring telemetry."
        },
        %Section{
          section_id: "section-investigation-reference",
          title: "Reference values",
          description: "Current values for rapid comparison.",
          collapsed_by_default?: true
        }
      ],
      placements: [
        time_series_placement(
          "placement-sre-demo-investigation-battery",
          "Battery Voltage — 5 Minute Trend",
          "SRE_DEMO_HOUSEKEEPING.battery_voltage",
          %{x: 0, y: 0, w: 12, h: 5},
          scope_override,
          "section-investigation"
        ),
        time_series_placement(
          "placement-sre-demo-investigation-uptime",
          "Spacecraft Uptime Correlation",
          "SRE_DEMO_HOUSEKEEPING.uptime_seconds",
          %{x: 0, y: 5, w: 8, h: 4},
          scope_override,
          "section-investigation"
        ),
        value_tile_placement(
          "placement-sre-demo-investigation-current",
          "Current Battery Voltage",
          "SRE_DEMO_HOUSEKEEPING.battery_voltage",
          %{x: 8, y: 5, w: 4, h: 2},
          scope_override,
          "section-investigation-reference"
        )
      ],
      metadata: %{
        tags: ["ops-demo", "flight-day-42", "investigation", "battery"],
        demo_story: "alarm_investigation"
      }
    }

    with {:ok, overview} <- Cadence.Dashboards.persist_document(ids.organization_id, overview),
         {:ok, investigation} <-
           Cadence.Dashboards.persist_document(ids.organization_id, investigation) do
      {:ok, %{overview: overview, investigation: investigation}}
    end
  end

  defp time_series_placement(
         placement_id,
         title,
         observable,
         layout,
         scope_override,
         section_id
       ) do
    %Placement{
      placement_id: placement_id,
      section_id: section_id,
      layout: layout,
      scope_override: scope_override,
      widget_def: %WidgetDef{
        widget_type_id: "cadence.time_series",
        widget_type_version: 1,
        title: title,
        binding: %{
          source: :telemetry,
          observables: [observable],
          scope_mode: :override,
          data_mode: :context,
          value_type: :engineering,
          sampling: :raw_series,
          overlays: [:limits, :events]
        },
        options: %{
          annotation_layers: ["mission-contacts"],
          legend: true,
          legend_mode: "always",
          window_seconds: 300,
          show_min_max_band: true,
          shared_tooltip: true
        }
      }
    }
  end

  defp value_tile_placement(
         placement_id,
         title,
         observable,
         layout,
         scope_override,
         section_id
       ) do
    %Placement{
      placement_id: placement_id,
      section_id: section_id,
      layout: layout,
      scope_override: scope_override,
      widget_def: %WidgetDef{
        widget_type_id: "cadence.value_tile",
        widget_type_version: 1,
        title: title,
        binding: %{
          source: :telemetry,
          observables: [observable],
          scope_mode: :override,
          data_mode: :context,
          value_type: :engineering,
          sampling: :latest,
          overlays: [:limits]
        },
        options: %{precision: 0}
      }
    }
  end

  defp status_matrix_placement(
         placement_id,
         title,
         observables,
         layout,
         scope_override,
         section_id
       ) do
    %Placement{
      placement_id: placement_id,
      section_id: section_id,
      layout: layout,
      scope_override: scope_override,
      widget_def: %WidgetDef{
        widget_type_id: "cadence.status_matrix",
        widget_type_version: 1,
        title: title,
        binding: %{
          source: :telemetry,
          observables: observables,
          scope_mode: :override,
          data_mode: :context,
          value_type: :engineering,
          sampling: :latest,
          overlays: [:limits]
        },
        options: %{precision: 0, window_seconds: 300}
      }
    }
  end

  defp publish_dashboards(ids, dashboards) do
    dashboards
    |> Map.values()
    |> Enum.reduce_while(:ok, fn document, :ok ->
      case Cadence.Dashboards.publish_document(
             ids.organization_id,
             ids.mission_id,
             document.dashboard_id,
             Document.version(document),
             published_by: demo_actor()
           ) do
        {:ok, _version} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {:dashboard_publish_failed, reason}}}
      end
    end)
  end

  defp persist_alarm_context(ids, observed_at) do
    alarm = %LimitEvent{
      limit_event_id: ids.limit_event_id,
      mission_id: ids.mission_id,
      spacecraft_id: ids.spacecraft_id,
      point_id: "SRE_DEMO_HOUSEKEEPING.battery_voltage",
      point_name: "Battery voltage",
      source_sample_type: :telemetry_sample,
      sample_id: "#{ids.limit_event_id}-sample",
      limit_definition_id: "#{ids.mission_id}-battery-flight-limit",
      limit_definition_version: 3,
      limit_set_name: "FLIGHT",
      evaluated_value: 24,
      limit_state: :red,
      normalized_state: :red,
      violation: true,
      generation_time: observed_at,
      receipt_time: observed_at,
      provenance: %{
        "demo" => "flight_day_42",
        "operator_note" => "Voltage excursion under investigation"
      }
    }

    nominal = %LimitEvent{
      limit_event_id: ids.nominal_limit_event_id,
      mission_id: ids.mission_id,
      spacecraft_id: ids.spacecraft_id,
      point_id: "SRE_DEMO_HOUSEKEEPING.uptime_seconds",
      point_name: "Spacecraft uptime",
      source_sample_type: :telemetry_sample,
      sample_id: "#{ids.nominal_limit_event_id}-sample",
      limit_definition_id: "#{ids.mission_id}-uptime-flight-limit",
      limit_definition_version: 1,
      limit_set_name: "FLIGHT",
      evaluated_value: 4_200,
      limit_state: :green,
      normalized_state: :green,
      violation: false,
      generation_time: observed_at,
      receipt_time: observed_at,
      provenance: %{"demo" => "flight_day_42"}
    }

    events = [alarm, nominal]

    Ecto.Multi.new()
    |> LimitStore.add_event_inserts(events)
    |> Ecto.Multi.run(:latest_limit_states, fn repo, _changes ->
      LimitStore.persist_latest_states(repo, events)
    end)
    |> Cadence.Repo.transaction()
    |> case do
      {:ok, _changes} -> :ok
      {:error, operation, reason, _changes} -> {:error, {operation, reason}}
    end
  end

  defp persist_command_context(ids, observed_at) do
    request =
      CommandRequest.new(%{
        command_request_id: ids.command_request_id,
        organization_id: ids.organization_id,
        mission_id: ids.mission_id,
        source_endpoint_ref: ids.source_endpoint_id,
        command_snapshot_id: "#{ids.mission_id}-command-snapshot",
        command_id: "EPS_SET_CHARGE_MODE",
        command_name: "EPS_SET_CHARGE_MODE",
        command_display_name: "Set battery charge mode",
        lifecycle_state: :queued,
        verification_state: :pending,
        priority: 1,
        not_before: DateTime.add(observed_at, 45, :minute),
        requested_by: %{"display_name" => "Flight Director", "role" => "operator"},
        requested_at: observed_at,
        argument_values: %{"mode" => "RECOVERY"},
        resolved_argument_values: %{"mode" => 2},
        significance: :critical,
        critical: true,
        hazardous: false,
        subsystem: "EPS",
        group_name: "Battery Recovery",
        metadata: %{
          "spacecraft_id" => ids.spacecraft_id,
          "demo" => "flight_day_42"
        }
      })

    queue_entry =
      CommandQueueEntry.new(%{
        command_queue_entry_id: ids.command_queue_entry_id,
        organization_id: ids.organization_id,
        mission_id: ids.mission_id,
        command_request_id: ids.command_request_id,
        source_endpoint_ref: ids.source_endpoint_id,
        queue_lane_key: ids.source_endpoint_id,
        priority: 1,
        queue_sequence: 1,
        not_before: DateTime.add(observed_at, 45, :minute),
        lifecycle_state: :pending,
        enqueued_by: %{"service_identity_id" => demo_actor()},
        enqueued_at: observed_at,
        metadata: %{
          "spacecraft_id" => ids.spacecraft_id,
          "demo" => "flight_day_42"
        }
      })

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:command_request, CommandRequestRow.changeset(request))
    |> Ecto.Multi.insert(:command_queue_entry, CommandQueueEntryRow.changeset(queue_entry))
    |> Cadence.Repo.transaction()
    |> case do
      {:ok, _changes} -> :ok
      {:error, operation, reason, _changes} -> {:error, {operation, reason}}
    end
  end

  defp persist_source_health_context(ids, observed_at) do
    Cadence.Control.DataSources.record_health_observation(%{
      organization_id: ids.organization_id,
      mission_id: ids.mission_id,
      logical_source: :telemetry,
      data_source_id: "managed_questdb_primary",
      source_binding_id: "default_flight_telemetry",
      realm: :flight,
      dataset: "flight",
      source_health: :degraded,
      reason: :watermark_lag,
      observed_at: observed_at,
      payload: %{
        "demo" => "flight_day_42",
        "lag_seconds" => 18,
        "operator_note" => "Historical completeness review requested"
      }
    })
    |> case do
      {:ok, _event, _status} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist_historical_data_context(ids, observed_at) do
    Cadence.Telemetry.DataManagement.record_historical_data_workflow_request(
      :backfill,
      %{
        organization_id: ids.organization_id,
        mission_id: ids.mission_id,
        data_source_id: "managed_questdb_primary",
        binding_id: "default_flight_telemetry",
        realm: :flight,
        backfill_run_id: ids.backfill_run_id,
        requested_at: observed_at,
        requested_by: %{"display_name" => "Telemetry Analyst"},
        metadata: %{
          "dashboard_id" => ids.investigation_dashboard_id,
          "reason" => "Verify completeness around the battery excursion",
          "demo" => "flight_day_42"
        }
      },
      ["SRE_DEMO_HOUSEKEEPING.battery_voltage"]
    )
    |> case do
      {:ok, _events} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp persist_dashboard_management_context(ids, dashboards, observed_at) do
    runtime_context = %{
      spacecraft_id: ids.spacecraft_id,
      time_mode: "live",
      time_axis: "generation_time",
      realm: "flight",
      data_source_id: "managed_questdb_primary",
      source_binding_id: "default_flight_telemetry"
    }

    snapshot_context =
      Map.merge(runtime_context, %{
        from: DateTime.add(observed_at, -300, :second) |> DateTime.to_iso8601(),
        to: DateTime.to_iso8601(observed_at)
      })

    library_widget =
      value_tile_placement(
        "library-preview",
        "Battery Voltage — Standard",
        "SRE_DEMO_HOUSEKEEPING.battery_voltage",
        %{x: 0, y: 0, w: 4, h: 2},
        %{primary: %{kind: :spacecraft, mode: :one, ids: [ids.spacecraft_id]}},
        nil
      ).widget_def
      |> WidgetDef.to_map()

    with {:ok, share} <-
           Management.create_share(
             ids.organization_id,
             ids.mission_id,
             dashboards.overview.dashboard_id,
             runtime_context,
             created_by: demo_actor(),
             expires_in_hours: 24
           ),
         {:ok, snapshot} <-
           Management.create_snapshot(
             ids.organization_id,
             ids.mission_id,
             dashboards.investigation,
             snapshot_context,
             created_by: demo_actor()
           ),
         {:ok, library_item} <-
           Management.create_library_item(
             ids.organization_id,
             ids.mission_id,
             %{
               name: "Battery Voltage — Flight Standard",
               description: "Reusable, limit-aware battery voltage tile.",
               change_summary: "Demo baseline",
               widget_definition: library_widget
             },
             created_by: demo_actor()
           ),
         {:ok, playlist} <-
           Management.create_playlist(
             ids.organization_id,
             ids.mission_id,
             %{
               name: "Flight Day 42 Ops Rotation",
               description: "Overview and investigation views for the active pass.",
               dashboard_ids: [
                 dashboards.overview.dashboard_id,
                 dashboards.investigation.dashboard_id
               ],
               dwell_seconds: 20,
               wallboard_mode: true
             },
             created_by: demo_actor()
           ),
         {:ok, artifact} <- Cadence.Dashboards.export_bundle(dashboards.overview),
         {:ok, deployment} <-
           Management.record_deployment(
             ids.organization_id,
             ids.mission_id,
             dashboards.overview,
             artifact,
             "demo",
             status: "validated",
             created_by: demo_actor()
           ) do
      {:ok,
       %{
         share: share,
         snapshot: snapshot,
         library_item: library_item,
         playlist: playlist,
         deployment: deployment
       }}
    end
  end

  defp demo_actor, do: "cadence-dashboard-demo"

  defp await_realized_contact(ids, scheduled_contact) do
    realized_contact_id = scheduled_contact.scheduled_contact_id <> "_run"

    wait_until(
      fn ->
        case Cadence.Contacts.fetch_realized_contact(
               ids.organization_id,
               ids.mission_id,
               realized_contact_id
             ) do
          {:ok, %RealizedContact{lifecycle_state: :active} = realized_contact} ->
            {:ok, realized_contact}

          _not_active_yet ->
            :retry
        end
      end,
      150,
      100
    )
  end

  defp fetch_downlink_path(ids, realized_contact) do
    Cadence.path_runtime_snapshot(
      ids.organization_id,
      ids.mission_id,
      realized_contact.realized_contact_id,
      ids.downlink_path_id
    )
  end

  defp listening_port(%{provider_runtimes: [provider_runtime]}) do
    case provider_runtime.port do
      port when is_integer(port) and port > 0 -> {:ok, port}
      _not_listening -> {:error, :provider_not_listening}
    end
  end

  defp listening_port(_snapshot), do: {:error, :unexpected_provider_runtime}

  defp start_simulator(ids, port, rate_hz) do
    CadenceSimulator.start_simulator(
      target_id: ids.source_endpoint_id,
      rate_hz: rate_hz,
      output: {:tcp, "127.0.0.1", port},
      definitions_content: @definitions,
      provider: CadenceSimulator.Providers.DatabaseDynamics,
      parallel_mode: :parallel,
      frame: %{format: :tm, frame_size: @frame_size, scid: 11, vcid: 2}
    )
  end

  defp await_telemetry_source_ready(ids) do
    wait_until(
      fn ->
        now = DateTime.utc_now()

        case TelemetryReads.sample_history_result(
               ids.organization_id,
               ids.mission_id,
               "SRE_DEMO_HOUSEKEEPING.uptime_seconds",
               realm: :flight,
               data_source_id: "managed_questdb_primary",
               source_binding_id: "default_flight_telemetry",
               dataset: "flight",
               spacecraft_id: ids.spacecraft_id,
               from_generation_time: DateTime.add(now, -60, :second),
               to_generation_time: now,
               limit: 10,
               order: :asc
             ) do
          {:ok, %{samples: [_sample | _rest]}} -> {:ok, :ready}
          _not_ready -> :retry
        end
      end,
      150,
      100
    )
    |> case do
      {:ok, :ready} -> :ok
    end
  end

  defp announce(state) do
    cadence_url = System.get_env("CADENCE_DASHBOARD_DEMO_CADENCE_URL") || "http://localhost:4001"
    grafana_url = System.get_env("CADENCE_DASHBOARD_DEMO_GRAFANA_URL") || "http://localhost:3000"
    mission_ops_url = "#{cadence_url}/missions/#{state.ids.mission_id}/ops"

    IO.puts("""

    Cadence Dashboard + Ops demo is live.

      service.name:       #{System.get_env("OTEL_SERVICE_NAME") || "cadence"}
      mission:            #{state.ids.mission_id}
      scheduled contact:  #{state.scheduled_contact.scheduled_contact_id}
      realized contact:   #{state.realized_contact.realized_contact_id}
      telemetry rate:     #{state.rate_hz} Hz
      TCP ingress port:   #{state.port}
      Grafana:            #{grafana_url}/d/cadence-sre-overview/cadence-sre-overview

      Start here:         #{mission_ops_url}/dashboards
      Pass overview:      #{mission_ops_url}/dashboards/#{state.dashboard.dashboard_id}?time_mode=live
      Investigation:      #{mission_ops_url}/dashboards/#{state.dashboards.investigation.dashboard_id}?time_mode=live
      Alarm workspace:    #{mission_ops_url}/alarms
      Command workspace:  #{mission_ops_url}/commands
      Explore:            #{mission_ops_url}/explore
      Timeline:           #{mission_ops_url}/timeline
      Data sources:       #{mission_ops_url}/data-sources
      Data operations:    #{mission_ops_url}/data-operations
      Activity:           #{mission_ops_url}/dashboards/#{state.dashboard.dashboard_id}/activity
      Diagnostics:        #{mission_ops_url}/dashboards/#{state.dashboard.dashboard_id}/diagnostics
      Editor:             #{mission_ops_url}/dashboards/#{state.dashboard.dashboard_id}/edit
      Settings:           #{mission_ops_url}/dashboards/#{state.dashboard.dashboard_id}/settings
      Frozen snapshot:    #{mission_ops_url}/dashboard-snapshots/#{state.management.snapshot.dashboard_snapshot_id}
      Authenticated share: #{mission_ops_url}/dashboard-shares/#{state.management.share.dashboard_share_id}
      Playlist:           #{mission_ops_url}/dashboards/playlists/#{state.management.playlist.dashboard_playlist_id}/present

    Stop this process with Ctrl-C when the exercise is complete.
    """)
  end

  defp monitor(state) do
    Process.sleep(10_000)

    profiler = Cadence.Telemetry.Profiler.snapshot(state.ids.mission_id)
    simulator = CadenceSimulator.simulator_stats(state.simulator)

    IO.puts(
      "Dashboard demo heartbeat: evidence=#{profiler.ingress_count} " <>
        "samples=#{profiler.dispatch.sample_count} simulator_packets=#{simulator.packet_count}"
    )

    monitor(state)
  end

  defp wait_until(fun, attempts, sleep_ms) when attempts > 0 do
    case fun.() do
      {:ok, value} ->
        {:ok, value}

      :retry ->
        Process.sleep(sleep_ms)
        wait_until(fun, attempts - 1, sleep_ms)
    end
  end

  defp wait_until(_fun, 0, _sleep_ms), do: {:error, :timeout}

  defp positive_integer_env(name, default) do
    case Integer.parse(System.get_env(name, "")) do
      {value, ""} when value > 0 -> value
      _invalid -> default
    end
  end

  defp positive_float_env(name, default) do
    case Float.parse(System.get_env(name, "")) do
      {value, ""} when value > 0 -> value
      _invalid -> default
    end
  end

  defp run_id do
    DateTime.utc_now()
    |> DateTime.to_unix(:second)
    |> Integer.to_string()
  end

  defp demo_log_level do
    level =
      System.get_env("CADENCE_DASHBOARD_DEMO_LOG_LEVEL") ||
        System.get_env("CADENCE_SRE_DEMO_LOG_LEVEL") || "info"

    case String.downcase(level) do
      "debug" -> :debug
      "warning" -> :warning
      "error" -> :error
      _other -> :info
    end
  end

  defp configure_shared_demo_persistence do
    # The demo intentionally runs outside the Phoenix BEAM while its dashboard
    # is rendered by Phoenix. Keep the live projection and the records it
    # references in the shared Postgres compatibility stores so both nodes see
    # the same current values with valid packet/evidence provenance.
    Application.put_env(
      :cadence,
      :ingress_archive,
      module: Cadence.IngressArchive.Postgres
    )

    Application.put_env(
      :cadence,
      :protocol_record_archive,
      module: Cadence.Protocol.RecordArchive.Postgres
    )

    Application.put_env(
      :cadence,
      :telemetry_current_value_store,
      module: Cadence.Telemetry.CurrentValueStore.Postgres
    )
  end
end

Cadence.Dev.SreObservabilityDemo.run()
