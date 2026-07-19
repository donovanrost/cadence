defmodule Cadence.Dev.SreObservabilityDemo do
  @moduledoc false

  alias Cadence.ApplicationDispatch.{BindingRule, BindingSet}
  alias Cadence.Accounts.OrganizationMembership
  alias Cadence.Contacts.{Path, ProviderBinding, RealizedContact, ScheduledContact}
  alias Cadence.Dashboards.{Document, Placement, WidgetDef}
  alias Cadence.Missions.Mission
  alias Cadence.Observability
  alias Cadence.Organizations.Organization
  alias Cadence.Persistence.Schemas.OrganizationMembershipRow
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft
  alias Cadence.Telemetry.PacketDefinition

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

    run_id = System.get_env("CADENCE_SRE_DEMO_RUN_ID") || run_id()
    rate_hz = positive_float_env("CADENCE_SRE_DEMO_RATE_HZ", 2.0)
    duration_seconds = positive_integer_env("CADENCE_SRE_DEMO_CONTACT_SECONDS", 3600)

    ids = %{
      organization_id: "org-sre-demo-#{run_id}",
      mission_id: "mission-sre-demo-#{run_id}",
      spacecraft_id: "spacecraft-sre-demo-#{run_id}",
      source_endpoint_id: "source-sre-demo-#{run_id}",
      binding_set_id: "binding-sre-demo-#{run_id}",
      dashboard_id: "dashboard-sre-demo-#{run_id}",
      scheduled_contact_id: "contact-sre-demo-#{run_id}",
      downlink_path_id: "path-sre-demo-downlink-#{run_id}"
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

    with {:ok, _organization} <- persist_organization(ids),
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
         {:ok, dashboard} <- persist_native_dashboard(ids) do
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
         dashboard: dashboard,
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
    |> Cadence.persist_organization()
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
      System.get_env("CADENCE_SRE_DEMO_BROWSER_EMAIL") ||
        System.get_env("CADENCE_BOOTSTRAP_ADMIN_EMAIL")

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

    Cadence.persist_spacecraft(ids.organization_id, spacecraft)
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

    Cadence.persist_source_endpoint(ids.organization_id, source_endpoint)
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
           Cadence.persist_binding_set(ids.organization_id, binding_set),
         {:ok, _activation} <-
           Cadence.activate_binding_set(
             ids.organization_id,
             ids.mission_id,
             persisted_binding_set.binding_set_id,
             persisted_binding_set.version,
             activated_by: %{"service_identity_id" => "sre-observability-demo"}
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

    Cadence.persist_scheduled_contact(ids.organization_id, scheduled_contact)
  end

  defp persist_native_dashboard(ids) do
    scope_override = %{
      primary: %{kind: :spacecraft, mode: :one, ids: [ids.spacecraft_id]}
    }

    document = %Document{
      dashboard_id: ids.dashboard_id,
      organization_id: ids.organization_id,
      mission_id: ids.mission_id,
      name: "SRE Demo — Live Spacecraft Telemetry",
      description:
        "Live APID 42 telemetry generated by CadenceSimulator over the realized TCP contact.",
      defaults: %{
        time: %{
          mode: :live,
          axis: :generation_time,
          refresh_ms: 1_000,
          window_seconds: 300
        },
        scope: scope_override,
        data: %{realm: :flight, source_mode: :primary, allowed_realms: [:flight]}
      },
      placements: [
        time_series_placement(
          "placement-sre-demo-uptime-trend",
          "Spacecraft Uptime",
          "SRE_DEMO_HOUSEKEEPING.uptime_seconds",
          %{x: 0, y: 0, w: 8, h: 4},
          scope_override
        ),
        value_tile_placement(
          "placement-sre-demo-uptime-current",
          "Current Uptime",
          "SRE_DEMO_HOUSEKEEPING.uptime_seconds",
          %{x: 8, y: 0, w: 4, h: 2},
          scope_override
        ),
        time_series_placement(
          "placement-sre-demo-battery-trend",
          "Battery Voltage",
          "SRE_DEMO_HOUSEKEEPING.battery_voltage",
          %{x: 0, y: 4, w: 8, h: 4},
          scope_override
        ),
        value_tile_placement(
          "placement-sre-demo-battery-current",
          "Current Battery Voltage",
          "SRE_DEMO_HOUSEKEEPING.battery_voltage",
          %{x: 8, y: 4, w: 4, h: 2},
          scope_override
        )
      ],
      metadata: %{labels: ["sre-demo", "live-telemetry", "simulator"]}
    }

    Cadence.Dashboards.persist_document(ids.organization_id, document)
  end

  defp time_series_placement(placement_id, title, observable, layout, scope_override) do
    %Placement{
      placement_id: placement_id,
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
          overlays: []
        },
        options: %{legend: true, window_seconds: 300}
      }
    }
  end

  defp value_tile_placement(placement_id, title, observable, layout, scope_override) do
    %Placement{
      placement_id: placement_id,
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
          overlays: []
        },
        options: %{precision: 0}
      }
    }
  end

  defp await_realized_contact(ids, scheduled_contact) do
    realized_contact_id = scheduled_contact.scheduled_contact_id <> "_run"

    wait_until(
      fn ->
        case Cadence.fetch_realized_contact(
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

        case Cadence.telemetry_history_result(
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
    IO.puts("""

    Cadence SRE observability demo is live.

      service.name:       #{System.get_env("OTEL_SERVICE_NAME") || "cadence"}
      mission:            #{state.ids.mission_id}
      scheduled contact:  #{state.scheduled_contact.scheduled_contact_id}
      realized contact:   #{state.realized_contact.realized_contact_id}
      telemetry rate:     #{state.rate_hz} Hz
      TCP ingress port:   #{state.port}
      Grafana:            http://localhost:3000/d/cadence-sre-overview/cadence-sre-overview
      Cadence dashboard:  http://localhost:4001/missions/#{state.ids.mission_id}/ops/dashboards/#{state.dashboard.dashboard_id}?time_mode=live

    Stop this process with Ctrl-C when the exercise is complete.
    """)
  end

  defp monitor(state) do
    Process.sleep(10_000)

    profiler = Cadence.Telemetry.Profiler.snapshot(state.ids.mission_id)
    simulator = CadenceSimulator.simulator_stats(state.simulator)

    IO.puts(
      "SRE demo heartbeat: evidence=#{profiler.ingress_count} " <>
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
    case System.get_env("CADENCE_SRE_DEMO_LOG_LEVEL", "info") |> String.downcase() do
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
