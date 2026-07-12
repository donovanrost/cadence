defmodule Cadence.Dashboards.Sources.OperationalObservablesTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{
    DataBinding,
    DataLink,
    DataSource,
    Field,
    Frame,
    PlannedSourceRequest,
    ResolvedSourceBinding,
    ResolveWarning,
    SourceResult
  }

  alias Cadence.Commanding.CommandQueueEntry
  alias Cadence.Comms.Transport
  alias Cadence.Contacts.{RealizedContact, ScheduledContact}
  alias Cadence.Dashboards.Sources.OperationalObservables
  alias Cadence.Limits.Event
  alias Cadence.OperationalEvents.EffectiveInterval
  alias Cadence.OperationalEvents.Event, as: OperationalEvent
  alias Cadence.SourceEndpoints.SourceEndpoint
  alias Cadence.Spacecraft

  test "capabilities advertise the first-party operational observable registry" do
    capabilities = OperationalObservables.capabilities()

    assert capabilities.logical_source == :operational_observables
    assert capabilities.metadata.registry_version == 1
    assert "comms.transport.downlink_bitrate" in capabilities.metadata.observable_ids
    assert "comms.transport.uplink_bitrate" in capabilities.metadata.observable_ids
    assert "ground.station.connection_state" in capabilities.metadata.observable_ids
    assert "ground.station.antenna_pointing_state" in capabilities.metadata.observable_ids
    assert "runtime.managed_activity" in capabilities.metadata.observable_ids
    assert "runtime.transport_activity" in capabilities.metadata.observable_ids

    assert capabilities.metadata.metric_history_contracts == [
             %{
               observables: [
                 "link.snr_db",
                 "link.eb_n0_db",
                 "link.symbol_rate_sps",
                 "link.doppler_hz"
               ],
               product: :link_rf_metric_history,
               product_family: :link_rf
             },
             %{
               observables: [
                 "comms.transport.downlink_bitrate",
                 "comms.transport.uplink_bitrate"
               ],
               product: :transport_bitrate_history,
               product_family: :transport_bitrate
             },
             %{
               observables: ["ingress.processing_latency_ms"],
               product: :ingress_processing_latency_history,
               product_family: :runtime_ingress
             }
           ]

    assert %{
             observables: [
               "comms.transport.connection_state",
               "ground.station.connection_state"
             ],
             product: :connection_state_history,
             product_family: :connection_state,
             sampling: :event_history,
             shape: :events
           } in capabilities.metadata.source_backing_contracts

    assert %{
             observables: ["runtime.managed_activity"],
             product: :managed_runtime_activity_history,
             product_family: :runtime_managed,
             sampling: :event_history,
             shape: :events
           } in capabilities.metadata.source_backing_contracts

    assert %{
             observables: ["runtime.transport_activity"],
             product: :transport_runtime_activity_history,
             product_family: :runtime_transport,
             sampling: :event_history,
             shape: :events
           } in capabilities.metadata.source_backing_contracts

    assert %{
             observables: [
               "link.snr_db",
               "link.eb_n0_db",
               "link.symbol_rate_sps",
               "link.doppler_hz"
             ],
             product: :link_rf_metric_history,
             product_family: :link_rf,
             sampling: :raw_series,
             shape: :wide
           } in capabilities.metadata.source_backing_contracts

    assert Enum.any?(capabilities.metadata.source_backing_contracts, fn contract ->
             contract.product == :operational_latest and
               contract.sampling == :latest and
               "link.snr_db" in contract.observables and
               "commanding.queue_depth" in contract.observables and
               "comms.transport.execution_state" not in contract.observables
           end)

    assert Enum.any?(capabilities.metadata.source_backing_contracts, fn contract ->
             contract.product == :operational_metric_history and
               contract.sampling == :raw_series and
               "link.snr_db" in contract.observables and
               "comms.transport.downlink_bitrate" in contract.observables
           end)

    assert MapSet.new(capabilities.metadata.source_backed_observable_ids) ==
             MapSet.new(OperationalObservables.backed_observable_ids())
  end

  test "source backing contracts cover backed observables and advertised products" do
    capabilities = OperationalObservables.capabilities()
    contracts = capabilities.metadata.source_backing_contracts

    contract_observable_ids =
      contracts
      |> Enum.flat_map(& &1.observables)
      |> MapSet.new()

    assert MapSet.subset?(
             MapSet.new(OperationalObservables.backed_observable_ids()),
             contract_observable_ids
           )

    assert Enum.all?(contracts, &(&1.product in capabilities.supported_products))
    assert Enum.all?(contracts, &(&1.sampling in capabilities.supported_sampling))
    assert Enum.all?(contracts, &(&1.shape in capabilities.supported_shapes))

    assert OperationalObservables.source_backing_contracts() == contracts
  end

  test "mixed latest operational revision reads each source family once" do
    revision_fun = fn family, organization_id, mission_id, opts ->
      send(self(), {:revision_family, family, organization_id, mission_id, opts})
      "#{family}:revision"
    end

    request =
      source_request()
      |> Map.put(:observables, [
        "commanding.queue_depth",
        "ingress.processing_latency_ms",
        "comms.transport.downlink_bitrate"
      ])
      |> Map.put(:sampling, %{mode: :latest})

    assert {:ok, facts} =
             OperationalObservables.facts(request,
               source_binding: source_binding(),
               command_queue_revision_fun: &revision_fun.(:command_queue_depth, &1, &2, &3),
               ingress_processing_latency_revision_fun:
                 &revision_fun.(:ingress_processing_latency, &1, &2, &3),
               transport_bitrate_revision_fun: &revision_fun.(:transport_bitrate, &1, &2, &3)
             )

    assert facts.data_revision =~ "operational_latest:"

    assert_received {:revision_family, :command_queue_depth, "org-1", "mission-1", queue_opts}

    assert_received {:revision_family, :ingress_processing_latency, "org-1", "mission-1",
                     ingress_opts}

    assert_received {:revision_family, :transport_bitrate, "org-1", "mission-1", bitrate_opts}
    refute_received {:revision_family, :command_queue_depth, "org-1", "mission-1", _opts}
    refute_received {:revision_family, :ingress_processing_latency, "org-1", "mission-1", _opts}
    refute_received {:revision_family, :transport_bitrate, "org-1", "mission-1", _opts}

    assert queue_opts[:dataset] == "operational_observables"
    assert ingress_opts[:dataset] == "operational_observables"
    assert bitrate_opts[:dataset] == "operational_observables"
  end

  test "latest facts fail closed for history-only transport execution observables" do
    revision_fun = fn organization_id, mission_id, opts ->
      send(self(), {:transport_execution_revision, organization_id, mission_id, opts})
      "transport_execution_state:revision"
    end

    request =
      source_request()
      |> Map.put(:observables, ["comms.transport.execution_state"])
      |> Map.put(:sampling, %{mode: :latest})

    assert {:error, warning} =
             OperationalObservables.facts(request,
               source_binding: source_binding(),
               transport_execution_state_revision_fun: revision_fun
             )

    assert warning.code == :unsupported_operational_observable_backing
    assert warning.details.requested_mode == :latest
    assert warning.details.observables == ["comms.transport.execution_state"]
    refute_received {:transport_execution_revision, _organization_id, _mission_id, _opts}
  end

  test "resolves constellation health into a matrix frame" do
    latest_states_fun = fn organization_id, mission_id, opts ->
      send(self(), {:latest_states, organization_id, mission_id, opts})

      [
        event("sc-1", :yellow),
        event("sc-1", :red),
        event("sc-2", :green)
      ]
    end

    spacecraft_fun = fn organization_id, mission_id, opts ->
      send(self(), {:spacecraft, organization_id, mission_id, opts})

      [
        spacecraft("sc-1"),
        spacecraft("sc-2"),
        spacecraft("sc-quiet")
      ]
    end

    result =
      OperationalObservables.resolve(source_request(),
        latest_states_fun: latest_states_fun,
        spacecraft_fun: spacecraft_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{request_id: "ops-request-1", frames: [frame]} = result
    assert %Frame{source: :operational_observables, shape: :matrix, time_axis: nil} = frame

    assert [
             %Field{name: "spacecraft_id", kind: :string, values: ["sc-1", "sc-2", "sc-quiet"]},
             %Field{name: "worst_state", kind: :enum, values: [:red, :green, nil]}
           ] = frame.fields

    assert frame.meta.counts == %{red: 1, green: 1, no_data: 1}
    assert frame.meta.sampling == :constellation_health
    assert frame.meta.data_source_id == "managed_operational_observables"
    assert result.meta.supported_capability == :constellation_health
    refute result.meta.degraded?

    assert_received {:latest_states, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight
    assert opts[:dataset] == "operational_observables"

    assert_received {:spacecraft, "org-1", "mission-1", opts}
    assert opts[:data_source_id] == "managed_operational_observables"
  end

  test "returns a structured warning for unknown operational observable ids" do
    result =
      source_request()
      |> Map.put(:observables, ["HK.counter"])
      |> OperationalObservables.resolve(source_binding: source_binding())

    assert %SourceResult{frames: [], warnings: [warning]} = result
    assert warning.code == :unsupported_operational_observable
    assert warning.severity == :warning
    assert warning.details.observables == ["HK.counter"]

    assert MapSet.new(warning.details.supported_observables) ==
             MapSet.new(OperationalObservables.backed_observable_ids())

    assert result.meta.degraded?
  end

  test "resolves contact phase latest operational observable into a matrix frame" do
    scheduled_contacts_fun = fn organization_id, mission_id, opts ->
      send(self(), {:scheduled_contacts, organization_id, mission_id, opts})

      [
        scheduled_contact("contact-1", :scheduled),
        scheduled_contact("contact-2", :realized, realized_contact_id: "contact-2-run")
      ]
    end

    realized_contacts_fun = fn organization_id, mission_id, opts ->
      send(self(), {:realized_contacts, organization_id, mission_id, opts})

      [
        realized_contact("contact-2-run", :active, scheduled_contact_id: "contact-2"),
        realized_contact("contact-3-run", :completed)
      ]
    end

    result =
      source_request()
      |> Map.put(:observables, ["contacts.phase"])
      |> Map.put(:sampling, %{mode: :latest})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:05:00Z],
        scheduled_contacts_fun: scheduled_contacts_fun,
        realized_contacts_fun: realized_contacts_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :matrix, time_axis: nil} = frame
    assert result.meta.supported_capability == :contacts_phase

    assert [
             %Field{
               name: "observable_id",
               values: ["contacts.phase", "contacts.phase", "contacts.phase", "contacts.phase"]
             },
             %Field{
               name: "contact_id",
               values: ["contact-1", "contact-2", "contact-2-run", "contact-3-run"]
             },
             %Field{name: "contact_kind", values: [:scheduled, :scheduled, :realized, :realized]},
             %Field{name: "phase", values: [:scheduled, :realized, :active, :completed]},
             %Field{
               name: "observed_at",
               values: [
                 ~U[2026-06-17 12:00:00Z],
                 ~U[2026-06-17 12:00:00Z],
                 ~U[2026-06-17 12:00:01Z],
                 ~U[2026-06-17 12:00:01Z]
               ]
             },
             %Field{name: "freshness_state", values: [:fresh, :fresh, :fresh, :fresh]},
             %Field{name: "age_ms", values: [300_000, 300_000, 299_000, 299_000]}
           ] = frame.fields

    assert frame.meta.supported_capability == :contacts_phase
    assert frame.meta.observable_id == "contacts.phase"
    assert frame.meta.returned_points == 4
    assert frame.meta.freshness_checked_at == ~U[2026-06-17 12:05:00Z]
    assert frame.meta.warning_codes == []

    assert Enum.map(frame.meta.links, & &1.target_id) == [
             "contact-1",
             "contact-2-run",
             "contact-3-run"
           ]

    assert_received {:scheduled_contacts, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:realized_contacts, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "resolves absent contact phase rows as an empty latest frame" do
    result =
      source_request()
      |> Map.put(:observables, ["contacts.phase"])
      |> Map.put(:sampling, %{mode: :latest})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:05:00Z],
        scheduled_contacts_fun: fn organization_id, mission_id, opts ->
          send(self(), {:empty_scheduled_contacts, organization_id, mission_id, opts})
          []
        end,
        realized_contacts_fun: fn organization_id, mission_id, opts ->
          send(self(), {:empty_realized_contacts, organization_id, mission_id, opts})
          []
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    refute result.meta.degraded?
    assert frame.meta.supported_capability == :contacts_phase
    assert frame.meta.observable_id == "contacts.phase"
    assert frame.meta.returned_points == 0
    assert frame.meta.freshness_checked_at == nil
    assert frame.meta.warning_codes == []
    assert frame.meta.links == []

    assert [
             %Field{name: "observable_id", values: []},
             %Field{name: "contact_id", values: []},
             %Field{name: "contact_kind", values: []},
             %Field{name: "phase", values: []},
             %Field{name: "observed_at", values: []},
             %Field{name: "freshness_state", values: []},
             %Field{name: "age_ms", values: []}
           ] = frame.fields

    assert_received {:empty_scheduled_contacts, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:empty_realized_contacts, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "preserves replay context in operational observable reader options and links" do
    parent = self()

    scheduled_contacts_fun = fn organization_id, mission_id, opts ->
      send(parent, {:scheduled_contacts, organization_id, mission_id, opts})

      [
        scheduled_contact("replay-contact-1", :realized,
          realized_contact_id: "replay-contact-1-run"
        )
      ]
    end

    realized_contacts_fun = fn organization_id, mission_id, opts ->
      send(parent, {:realized_contacts, organization_id, mission_id, opts})

      [
        realized_contact("replay-contact-1-run", :active,
          scheduled_contact_id: "replay-contact-1"
        )
      ]
    end

    result =
      source_request()
      |> Map.put(:observables, ["contacts.phase"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:time_context, %{
        mode: :replay_run,
        from: ~U[2026-06-17 12:00:00Z],
        to: ~U[2026-06-17 12:10:00Z],
        replay_run_id: "replay-run-1"
      })
      |> Map.put(:data_context, %{
        realm: :replay,
        replay_run_id: "replay-run-1",
        source_contexts: %{
          operational_observables: %{
            data_source_id: "managed_operational_observables_replay",
            source_binding_id: "replay-operational-observables",
            dataset: "operational_observables_replay"
          }
        }
      })
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:05:00Z],
        scheduled_contacts_fun: scheduled_contacts_fun,
        realized_contacts_fun: realized_contacts_fun,
        source_binding: replay_source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert frame.meta.realm == :replay
    assert frame.meta.data_source_id == "managed_operational_observables_replay"
    assert frame.meta.source_binding_id == "replay-operational-observables"
    assert frame.meta.dataset == "operational_observables_replay"
    assert frame.meta.replay_run_id == "replay-run-1"
    assert hd(frame.meta.links).context.data.replay_run_id == "replay-run-1"

    assert hd(frame.meta.links).context.data.data_source_id ==
             "managed_operational_observables_replay"

    assert hd(frame.meta.links).context.data.source_binding_id == "replay-operational-observables"

    assert_receive {:scheduled_contacts, "org-1", "mission-1", scheduled_opts}
    assert scheduled_opts[:realm] == :replay
    assert scheduled_opts[:data_source_id] == "managed_operational_observables_replay"
    assert scheduled_opts[:source_binding_id] == "replay-operational-observables"
    assert scheduled_opts[:dataset] == "operational_observables_replay"
    assert scheduled_opts[:replay_run_id] == "replay-run-1"
    assert scheduled_opts[:from] == ~U[2026-06-17 12:00:00Z]
    assert scheduled_opts[:to] == ~U[2026-06-17 12:10:00Z]

    assert_receive {:realized_contacts, "org-1", "mission-1", realized_opts}
    assert realized_opts[:realm] == :replay
    assert realized_opts[:source_binding_id] == "replay-operational-observables"
    assert realized_opts[:replay_run_id] == "replay-run-1"
  end

  test "filters contact phase rows to the contact runtime scope" do
    result =
      source_request()
      |> Map.put(:observables, ["contacts.phase"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{primary: %{kind: :contact, mode: :one, ids: ["contact-2"]}})
      |> OperationalObservables.resolve(
        scheduled_contacts_fun: fn _organization_id, _mission_id, _opts ->
          [
            scheduled_contact("contact-1", :scheduled),
            scheduled_contact("contact-2", :realized, realized_contact_id: "contact-2-run")
          ]
        end,
        realized_contacts_fun: fn _organization_id, _mission_id, _opts ->
          [
            realized_contact("contact-2-run", :active, scheduled_contact_id: "contact-2"),
            realized_contact("contact-3-run", :completed)
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame]} = result

    assert [
             %Field{name: "observable_id"},
             %Field{name: "contact_id", values: contact_ids} | _rest
           ] =
             frame.fields

    assert contact_ids == ["contact-2", "contact-2-run"]
    assert frame.meta.returned_points == 2
  end

  test "filters contact phase event history rows to multi-contact runtime scope" do
    result =
      source_request()
      |> Map.put(:observables, ["contacts.phase"])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{
        from: ~U[2026-06-17 12:00:00Z],
        to: ~U[2026-06-17 12:10:00Z]
      })
      |> Map.put(:scope_context, %{
        primary: %{kind: :contact, mode: :many, ids: ["contact-alpha", "contact-beta"]}
      })
      |> OperationalObservables.resolve(
        scheduled_contacts_fun: fn _organization_id, _mission_id, _opts ->
          [
            scheduled_contact("contact-alpha", :realized,
              realized_contact_id: "contact-alpha-run"
            ),
            scheduled_contact("contact-beta", :scheduled),
            scheduled_contact("contact-gamma", :scheduled)
          ]
        end,
        realized_contacts_fun: fn _organization_id, _mission_id, _opts ->
          [
            realized_contact("contact-alpha-run", :active, scheduled_contact_id: "contact-alpha"),
            realized_contact("contact-gamma-run", :active, scheduled_contact_id: "contact-gamma")
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result

    assert [
             %Field{name: "time"},
             %Field{name: "observable_id"},
             %Field{name: "resource_id", values: resource_ids},
             %Field{name: "lane_id", values: lane_ids},
             %Field{name: "label"},
             %Field{name: "scope_kind", values: [:contact, :contact, :contact]},
             %Field{name: "contact_id", values: contact_ids},
             %Field{name: "contact_kind", values: [:scheduled, :scheduled, :realized]},
             %Field{name: "phase", values: [:realized, :scheduled, :active]},
             %Field{name: "normalized_state", values: [:realized, :scheduled, :active]}
           ] = frame.fields

    assert resource_ids == ["contact-alpha", "contact-beta", "contact-alpha-run"]
    assert lane_ids == ["contact-alpha", "contact-beta", "contact-alpha"]
    assert contact_ids == ["contact-alpha", "contact-beta", "contact-alpha-run"]
    assert frame.meta.returned_points == 3

    assert Enum.map(frame.meta.links, & &1.target_id) == [
             "contact-alpha-run",
             "contact-beta"
           ]
  end

  test "filters contact phase event history rows to spacecraft runtime scope through source endpoints" do
    result =
      source_request()
      |> Map.put(:observables, ["contacts.phase"])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{
        from: ~U[2026-06-17 12:00:00Z],
        to: ~U[2026-06-17 12:10:00Z]
      })
      |> Map.put(:scope_context, %{
        primary: %{kind: :spacecraft, mode: :one, ids: ["spacecraft-alpha"]}
      })
      |> OperationalObservables.resolve(
        scheduled_contacts_fun: fn _organization_id, _mission_id, _opts ->
          [
            scheduled_contact("contact-alpha", :realized,
              realized_contact_id: "contact-alpha-run",
              source_endpoint_refs: ["endpoint-alpha"]
            ),
            scheduled_contact("contact-beta", :scheduled, source_endpoint_refs: ["endpoint-beta"])
          ]
        end,
        realized_contacts_fun: fn _organization_id, _mission_id, _opts ->
          [
            realized_contact("contact-alpha-run", :active,
              scheduled_contact_id: "contact-alpha",
              source_endpoint_refs: ["endpoint-alpha"]
            ),
            realized_contact("contact-beta-run", :active,
              scheduled_contact_id: "contact-beta",
              source_endpoint_refs: ["endpoint-beta"]
            )
          ]
        end,
        source_endpoints_fun: fn organization_id, mission_id, opts ->
          send(self(), {:source_endpoints, organization_id, mission_id, opts})

          [
            source_endpoint("endpoint-alpha", "Alpha endpoint",
              spacecraft_id: "spacecraft-alpha"
            ),
            source_endpoint("endpoint-beta", "Beta endpoint", spacecraft_id: "spacecraft-beta")
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result

    assert [
             %Field{name: "time"},
             %Field{name: "observable_id"},
             %Field{name: "resource_id", values: resource_ids},
             %Field{name: "lane_id", values: lane_ids},
             %Field{name: "label"},
             %Field{name: "scope_kind", values: [:contact, :contact]},
             %Field{name: "contact_id", values: contact_ids},
             %Field{name: "contact_kind", values: [:scheduled, :realized]},
             %Field{name: "phase", values: [:realized, :active]},
             %Field{name: "normalized_state", values: [:realized, :active]}
           ] = frame.fields

    assert resource_ids == ["contact-alpha", "contact-alpha-run"]
    assert lane_ids == ["contact-alpha", "contact-alpha"]
    assert contact_ids == ["contact-alpha", "contact-alpha-run"]
    assert frame.meta.returned_points == 2
    assert Enum.map(frame.meta.links, & &1.target_id) == ["contact-alpha-run"]

    assert_received {:source_endpoints, "org-1", "mission-1", opts}
    assert opts[:data_source_id] == "managed_operational_observables"
  end

  test "filters contact phase event history rows to source endpoint runtime scope" do
    result =
      source_request()
      |> Map.put(:observables, ["contacts.phase"])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{
        from: ~U[2026-06-17 12:00:00Z],
        to: ~U[2026-06-17 12:10:00Z]
      })
      |> Map.put(:scope_context, %{
        primary: %{kind: :source_endpoint, mode: :one, ids: ["endpoint-alpha"]}
      })
      |> OperationalObservables.resolve(
        scheduled_contacts_fun: fn _organization_id, _mission_id, _opts ->
          [
            scheduled_contact("contact-alpha", :realized,
              realized_contact_id: "contact-alpha-run",
              source_endpoint_refs: ["endpoint-alpha"]
            ),
            scheduled_contact("contact-beta", :scheduled, source_endpoint_refs: ["endpoint-beta"])
          ]
        end,
        realized_contacts_fun: fn _organization_id, _mission_id, _opts ->
          [
            realized_contact("contact-alpha-run", :active,
              scheduled_contact_id: "contact-alpha",
              source_endpoint_refs: ["endpoint-alpha"]
            ),
            realized_contact("contact-beta-run", :active,
              scheduled_contact_id: "contact-beta",
              source_endpoint_refs: ["endpoint-beta"]
            )
          ]
        end,
        source_endpoints_fun: fn organization_id, mission_id, opts ->
          send(self(), {:source_endpoints, organization_id, mission_id, opts})

          [
            source_endpoint("endpoint-alpha", "Alpha endpoint"),
            source_endpoint("endpoint-beta", "Beta endpoint")
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result

    assert [
             %Field{name: "time"},
             %Field{name: "observable_id"},
             %Field{name: "resource_id", values: resource_ids},
             %Field{name: "lane_id", values: lane_ids},
             %Field{name: "label"},
             %Field{name: "scope_kind", values: [:contact, :contact]},
             %Field{name: "contact_id", values: contact_ids},
             %Field{name: "contact_kind", values: [:scheduled, :realized]},
             %Field{name: "phase", values: [:realized, :active]},
             %Field{name: "normalized_state", values: [:realized, :active]}
           ] = frame.fields

    assert resource_ids == ["contact-alpha", "contact-alpha-run"]
    assert lane_ids == ["contact-alpha", "contact-alpha"]
    assert contact_ids == ["contact-alpha", "contact-alpha-run"]
    assert frame.meta.returned_points == 2
    assert Enum.map(frame.meta.links, & &1.target_id) == ["contact-alpha-run"]

    assert_received {:source_endpoints, "org-1", "mission-1", opts}
    assert opts[:data_source_id] == "managed_operational_observables"
  end

  test "filters contact phase event history rows to multi-source-endpoint runtime scope" do
    result =
      source_request()
      |> Map.put(:observables, ["contacts.phase"])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{
        from: ~U[2026-06-17 12:00:00Z],
        to: ~U[2026-06-17 12:10:00Z]
      })
      |> Map.put(:scope_context, %{
        primary: %{kind: :source_endpoint, mode: :many, ids: ["endpoint-alpha", "endpoint-beta"]}
      })
      |> OperationalObservables.resolve(
        scheduled_contacts_fun: fn _organization_id, _mission_id, _opts ->
          [
            scheduled_contact("contact-alpha", :realized,
              realized_contact_id: "contact-alpha-run",
              source_endpoint_refs: ["endpoint-alpha"]
            ),
            scheduled_contact("contact-beta", :scheduled,
              source_endpoint_refs: ["endpoint-beta"]
            ),
            scheduled_contact("contact-gamma", :scheduled,
              source_endpoint_refs: ["endpoint-gamma"]
            )
          ]
        end,
        realized_contacts_fun: fn _organization_id, _mission_id, _opts ->
          [
            realized_contact("contact-alpha-run", :active,
              scheduled_contact_id: "contact-alpha",
              source_endpoint_refs: ["endpoint-alpha"]
            ),
            realized_contact("contact-gamma-run", :active,
              scheduled_contact_id: "contact-gamma",
              source_endpoint_refs: ["endpoint-gamma"]
            )
          ]
        end,
        source_endpoints_fun: fn organization_id, mission_id, opts ->
          send(self(), {:source_endpoints, organization_id, mission_id, opts})

          [
            source_endpoint("endpoint-alpha", "Alpha endpoint"),
            source_endpoint("endpoint-beta", "Beta endpoint"),
            source_endpoint("endpoint-gamma", "Gamma endpoint")
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result

    assert [
             %Field{name: "time"},
             %Field{name: "observable_id"},
             %Field{name: "resource_id", values: resource_ids},
             %Field{name: "lane_id", values: lane_ids},
             %Field{name: "label"},
             %Field{name: "scope_kind", values: [:contact, :contact, :contact]},
             %Field{name: "contact_id", values: contact_ids},
             %Field{name: "contact_kind", values: [:scheduled, :scheduled, :realized]},
             %Field{name: "phase", values: [:realized, :scheduled, :active]},
             %Field{name: "normalized_state", values: [:realized, :scheduled, :active]}
           ] = frame.fields

    assert resource_ids == ["contact-alpha", "contact-beta", "contact-alpha-run"]
    assert lane_ids == ["contact-alpha", "contact-beta", "contact-alpha"]
    assert contact_ids == ["contact-alpha", "contact-beta", "contact-alpha-run"]
    assert frame.meta.returned_points == 3

    assert Enum.map(frame.meta.links, & &1.target_id) == [
             "contact-alpha-run",
             "contact-beta"
           ]

    assert_received {:source_endpoints, "org-1", "mission-1", opts}
    assert opts[:data_source_id] == "managed_operational_observables"
  end

  test "filters contact phase event history rows to ground station runtime scope through source endpoints" do
    result =
      source_request()
      |> Map.put(:observables, ["contacts.phase"])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{
        from: ~U[2026-06-17 12:00:00Z],
        to: ~U[2026-06-17 12:10:00Z]
      })
      |> Map.put(:scope_context, %{
        primary: %{kind: :ground_station, mode: :one, ids: ["ground-alpha"]}
      })
      |> OperationalObservables.resolve(
        scheduled_contacts_fun: fn _organization_id, _mission_id, _opts ->
          [
            scheduled_contact("contact-alpha", :realized,
              realized_contact_id: "contact-alpha-run",
              source_endpoint_refs: ["endpoint-alpha"]
            ),
            scheduled_contact("contact-beta", :scheduled, source_endpoint_refs: ["endpoint-beta"])
          ]
        end,
        realized_contacts_fun: fn _organization_id, _mission_id, _opts ->
          [
            realized_contact("contact-alpha-run", :active,
              scheduled_contact_id: "contact-alpha",
              source_endpoint_refs: ["endpoint-alpha"]
            ),
            realized_contact("contact-beta-run", :active,
              scheduled_contact_id: "contact-beta",
              source_endpoint_refs: ["endpoint-beta"]
            )
          ]
        end,
        source_endpoints_fun: fn organization_id, mission_id, opts ->
          send(self(), {:source_endpoints, organization_id, mission_id, opts})

          [
            source_endpoint("endpoint-alpha", "Alpha endpoint",
              ground_station_id: "ground-alpha"
            ),
            source_endpoint("endpoint-beta", "Beta endpoint", ground_station_id: "ground-beta")
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result

    assert [
             %Field{name: "time"},
             %Field{name: "observable_id"},
             %Field{name: "resource_id", values: resource_ids},
             %Field{name: "lane_id", values: lane_ids},
             %Field{name: "label"},
             %Field{name: "scope_kind", values: [:contact, :contact]},
             %Field{name: "contact_id", values: contact_ids},
             %Field{name: "contact_kind", values: [:scheduled, :realized]},
             %Field{name: "phase", values: [:realized, :active]},
             %Field{name: "normalized_state", values: [:realized, :active]}
           ] = frame.fields

    assert resource_ids == ["contact-alpha", "contact-alpha-run"]
    assert lane_ids == ["contact-alpha", "contact-alpha"]
    assert contact_ids == ["contact-alpha", "contact-alpha-run"]
    assert frame.meta.returned_points == 2
    assert Enum.map(frame.meta.links, & &1.target_id) == ["contact-alpha-run"]

    assert_received {:source_endpoints, "org-1", "mission-1", opts}
    assert opts[:data_source_id] == "managed_operational_observables"
  end

  test "filters contact phase event history rows to multi-ground-station runtime scope through source endpoints" do
    result =
      source_request()
      |> Map.put(:observables, ["contacts.phase"])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{
        from: ~U[2026-06-17 12:00:00Z],
        to: ~U[2026-06-17 12:10:00Z]
      })
      |> Map.put(:scope_context, %{
        primary: %{kind: :ground_station, mode: :many, ids: ["ground-alpha", "ground-beta"]}
      })
      |> OperationalObservables.resolve(
        scheduled_contacts_fun: fn _organization_id, _mission_id, _opts ->
          [
            scheduled_contact("contact-alpha", :realized,
              realized_contact_id: "contact-alpha-run",
              source_endpoint_refs: ["endpoint-alpha"]
            ),
            scheduled_contact("contact-beta", :scheduled,
              source_endpoint_refs: ["endpoint-beta"]
            ),
            scheduled_contact("contact-gamma", :scheduled,
              source_endpoint_refs: ["endpoint-gamma"]
            )
          ]
        end,
        realized_contacts_fun: fn _organization_id, _mission_id, _opts ->
          [
            realized_contact("contact-alpha-run", :active,
              scheduled_contact_id: "contact-alpha",
              source_endpoint_refs: ["endpoint-alpha"]
            ),
            realized_contact("contact-gamma-run", :active,
              scheduled_contact_id: "contact-gamma",
              source_endpoint_refs: ["endpoint-gamma"]
            )
          ]
        end,
        source_endpoints_fun: fn organization_id, mission_id, opts ->
          send(self(), {:source_endpoints, organization_id, mission_id, opts})

          [
            source_endpoint("endpoint-alpha", "Alpha endpoint",
              ground_station_id: "ground-alpha"
            ),
            source_endpoint("endpoint-beta", "Beta endpoint", ground_station_id: "ground-beta"),
            source_endpoint("endpoint-gamma", "Gamma endpoint", ground_station_id: "ground-gamma")
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result

    assert [
             %Field{name: "time"},
             %Field{name: "observable_id"},
             %Field{name: "resource_id", values: resource_ids},
             %Field{name: "lane_id", values: lane_ids},
             %Field{name: "label"},
             %Field{name: "scope_kind", values: [:contact, :contact, :contact]},
             %Field{name: "contact_id", values: contact_ids},
             %Field{name: "contact_kind", values: [:scheduled, :scheduled, :realized]},
             %Field{name: "phase", values: [:realized, :scheduled, :active]},
             %Field{name: "normalized_state", values: [:realized, :scheduled, :active]}
           ] = frame.fields

    assert resource_ids == ["contact-alpha", "contact-beta", "contact-alpha-run"]
    assert lane_ids == ["contact-alpha", "contact-beta", "contact-alpha"]
    assert contact_ids == ["contact-alpha", "contact-beta", "contact-alpha-run"]
    assert frame.meta.returned_points == 3

    assert Enum.map(frame.meta.links, & &1.target_id) == [
             "contact-alpha-run",
             "contact-beta"
           ]

    assert_received {:source_endpoints, "org-1", "mission-1", opts}
    assert opts[:data_source_id] == "managed_operational_observables"
  end

  test "resolves contact phase event history into state events" do
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:00:02Z]

    result =
      source_request()
      |> Map.put(:observables, ["contacts.phase"])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{from: from_time, to: to_time})
      |> OperationalObservables.resolve(
        scheduled_contacts_fun: fn organization_id, mission_id, opts ->
          send(self(), {:history_scheduled_contacts, organization_id, mission_id, opts})

          [
            scheduled_contact("contact-1", :scheduled),
            scheduled_contact("contact-late", :scheduled, starts_at: ~U[2026-06-17 12:05:00Z])
          ]
        end,
        realized_contacts_fun: fn organization_id, mission_id, opts ->
          send(self(), {:history_realized_contacts, organization_id, mission_id, opts})

          [realized_contact("contact-1-run", :active, scheduled_contact_id: "contact-1")]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result

    assert %Frame{source: :operational_observables, shape: :events, time_axis: :occurred_at} =
             frame

    assert result.meta.supported_capability == :contacts_phase_history
    assert frame.meta.supported_capability == :contacts_phase_history
    assert frame.meta.sampling == :event_history
    assert frame.meta.returned_points == 2

    assert [
             %Field{name: "time", values: [~U[2026-06-17 12:00:00Z], ~U[2026-06-17 12:00:01Z]]},
             %Field{name: "observable_id", values: ["contacts.phase", "contacts.phase"]},
             %Field{name: "resource_id", values: ["contact-1", "contact-1-run"]},
             %Field{name: "lane_id", values: ["contact-1", "contact-1"]},
             %Field{name: "label", values: ["scheduled / contact-1", "realized / contact-1-run"]},
             %Field{name: "scope_kind", values: [:contact, :contact]},
             %Field{name: "contact_id", values: ["contact-1", "contact-1-run"]},
             %Field{name: "contact_kind", values: [:scheduled, :realized]},
             %Field{name: "phase", values: [:scheduled, :active]},
             %Field{name: "normalized_state", values: [:scheduled, :active]}
           ] = frame.fields

    assert Enum.map(frame.meta.links, & &1.target_id) == ["contact-1", "contact-1-run"]

    assert_received {:history_scheduled_contacts, "org-1", "mission-1", opts}
    assert opts[:from] == from_time
    assert opts[:to] == to_time

    assert_received {:history_realized_contacts, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "resolves connection state observables from configured operational resources and snapshots" do
    transports_fun = fn organization_id, mission_id, opts ->
      send(self(), {:transports, organization_id, mission_id, opts})

      [
        transport("transport-alpha", "Lab TCP",
          source_endpoint_id: "endpoint-alpha",
          ground_station_id: "dss-14"
        ),
        transport("transport-beta", "Backup TCP", source_endpoint_id: "endpoint-beta")
      ]
    end

    source_endpoints_fun = fn organization_id, mission_id, opts ->
      send(self(), {:source_endpoints, organization_id, mission_id, opts})

      [
        source_endpoint("endpoint-alpha", "Goldstone DSS-14", ground_station_id: "dss-14"),
        source_endpoint("endpoint-beta", "Backup Antenna")
      ]
    end

    connection_snapshots_fun = fn organization_id, mission_id, opts ->
      send(self(), {:connection_snapshots, organization_id, mission_id, opts})

      [
        %{
          transport_id: "transport-alpha",
          source_endpoint_id: "endpoint-alpha",
          adapter_key: :tcp_socket,
          connection_state: :connected,
          observed_at: ~U[2026-06-17 12:03:00Z]
        }
      ]
    end

    result =
      source_request()
      |> Map.put(:observables, [
        "comms.transport.connection_state",
        "ground.station.connection_state"
      ])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{
        primary: %{kind: :source_endpoint, mode: :one, ids: ["endpoint-alpha"]}
      })
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:03:02Z],
        transports_fun: transports_fun,
        source_endpoints_fun: source_endpoints_fun,
        connection_snapshots_fun: connection_snapshots_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :matrix, time_axis: nil} = frame
    assert result.meta.supported_capability == :connection_state
    assert frame.meta.supported_capability == :connection_state
    assert frame.meta.returned_points == 2

    assert Enum.map(frame.meta.links, &{&1.target, &1.target_id}) == [
             {:transport, "transport-alpha"},
             {:source_endpoint, "endpoint-alpha"},
             {:ground_station, "dss-14"}
           ]

    assert [
             %Field{
               name: "observable_id",
               values: [
                 "comms.transport.connection_state",
                 "ground.station.connection_state"
               ]
             },
             %Field{name: "resource_id", values: ["transport-alpha", "dss-14"]},
             %Field{name: "label", values: ["Lab TCP", "Goldstone DSS-14"]},
             %Field{name: "scope_kind", values: [:transport, :ground_station]},
             %Field{name: "transport_id", values: ["transport-alpha", "transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha", "endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14", "dss-14"]},
             %Field{name: "link_id", values: [nil, nil]},
             %Field{name: "adapter_key", values: [:tcp_socket, :tcp_socket]},
             %Field{name: "connection_state", values: [:connected, :connected]},
             %Field{
               name: "observed_at",
               values: [~U[2026-06-17 12:03:00Z], ~U[2026-06-17 12:03:00Z]]
             },
             %Field{name: "freshness_state", values: [:fresh, :fresh]},
             %Field{name: "age_ms", values: [2_000, 2_000]}
           ] = frame.fields

    assert_received {:transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:source_endpoints, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"

    assert_received {:connection_snapshots, "org-1", "mission-1", opts}
    assert opts[:data_source_id] == "managed_operational_observables"
  end

  test "marks configured ground-station connection rows missing when runtime snapshots are absent" do
    result =
      source_request()
      |> Map.put(:observables, ["ground.station.connection_state"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{primary: %{kind: :ground_station, mode: :one, ids: ["dss-14"]}})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:03:02Z],
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:missing_ground_station_transports, organization_id, mission_id, opts})
          []
        end,
        source_endpoints_fun: fn organization_id, mission_id, opts ->
          send(
            self(),
            {:missing_ground_station_source_endpoints, organization_id, mission_id, opts}
          )

          [
            source_endpoint("endpoint-alpha", "Goldstone DSS-14", ground_station_id: "dss-14")
          ]
        end,
        connection_snapshots_fun: fn organization_id, mission_id, opts ->
          send(
            self(),
            {:missing_ground_station_connection_snapshots, organization_id, mission_id, opts}
          )

          []
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{
             frames: [frame],
             warnings: [%ResolveWarning{code: :missing_snapshot, severity: :warning} = warning]
           } = result

    assert result.meta.degraded?
    assert warning.message == "Operational observable snapshot is missing"
    assert warning.details.supported_capability == :connection_state
    assert warning.details.frame_ids == ["ops-request-1:connection_state"]
    assert warning.details.observable_ids == ["ground.station.connection_state"]
    assert frame.meta.supported_capability == :connection_state
    assert frame.meta.observable_ids == ["ground.station.connection_state"]
    assert frame.meta.returned_points == 1
    assert frame.meta.warning_codes == [:missing_snapshot]
    assert frame.meta.freshness_checked_at == ~U[2026-06-17 12:03:02Z]

    assert Enum.map(frame.meta.links, &{&1.target, &1.target_id}) == [
             {:source_endpoint, "endpoint-alpha"},
             {:ground_station, "dss-14"}
           ]

    assert [
             %Field{name: "observable_id", values: ["ground.station.connection_state"]},
             %Field{name: "resource_id", values: ["dss-14"]},
             %Field{name: "label", values: ["Goldstone DSS-14"]},
             %Field{name: "scope_kind", values: [:ground_station]},
             %Field{name: "transport_id", values: [nil]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: [nil]},
             %Field{name: "adapter_key", values: [nil]},
             %Field{name: "connection_state", values: [:unknown]},
             %Field{name: "observed_at", values: [nil]},
             %Field{name: "freshness_state", values: [:missing]},
             %Field{name: "age_ms", values: [nil]}
           ] = frame.fields

    assert_received {:missing_ground_station_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:missing_ground_station_source_endpoints, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"

    assert_received {:missing_ground_station_connection_snapshots, "org-1", "mission-1", opts}
    assert opts[:data_source_id] == "managed_operational_observables"
  end

  test "marks configured transport connection rows missing when runtime snapshots are absent" do
    result =
      source_request()
      |> Map.put(:observables, ["comms.transport.connection_state"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{
        primary: %{kind: :transport, mode: :one, ids: ["transport-alpha"]}
      })
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:03:02Z],
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:missing_transport_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            )
          ]
        end,
        source_endpoints_fun: fn organization_id, mission_id, opts ->
          send(
            self(),
            {:missing_transport_source_endpoints, organization_id, mission_id, opts}
          )

          []
        end,
        connection_snapshots_fun: fn organization_id, mission_id, opts ->
          send(
            self(),
            {:missing_transport_connection_snapshots, organization_id, mission_id, opts}
          )

          []
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{
             frames: [frame],
             warnings: [%ResolveWarning{code: :missing_snapshot, severity: :warning} = warning]
           } = result

    assert result.meta.degraded?
    assert warning.message == "Operational observable snapshot is missing"
    assert warning.details.supported_capability == :connection_state
    assert warning.details.frame_ids == ["ops-request-1:connection_state"]
    assert warning.details.observable_ids == ["comms.transport.connection_state"]
    assert frame.meta.supported_capability == :connection_state
    assert frame.meta.observable_ids == ["comms.transport.connection_state"]
    assert frame.meta.returned_points == 1
    assert frame.meta.warning_codes == [:missing_snapshot]
    assert frame.meta.freshness_checked_at == ~U[2026-06-17 12:03:02Z]

    assert Enum.map(frame.meta.links, &{&1.target, &1.target_id}) == [
             {:transport, "transport-alpha"},
             {:source_endpoint, "endpoint-alpha"},
             {:ground_station, "dss-14"},
             {:link, "link-alpha"}
           ]

    assert [
             %Field{name: "observable_id", values: ["comms.transport.connection_state"]},
             %Field{name: "resource_id", values: ["transport-alpha"]},
             %Field{name: "label", values: ["Lab TCP"]},
             %Field{name: "scope_kind", values: [:transport]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "adapter_key", values: [:tcp_socket]},
             %Field{name: "connection_state", values: [:unknown]},
             %Field{name: "observed_at", values: [nil]},
             %Field{name: "freshness_state", values: [:missing]},
             %Field{name: "age_ms", values: [nil]}
           ] = frame.fields

    assert_received {:missing_transport_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:missing_transport_source_endpoints, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"

    assert_received {:missing_transport_connection_snapshots, "org-1", "mission-1", opts}
    assert opts[:data_source_id] == "managed_operational_observables"
  end

  test "filters connection state latest rows to link scope" do
    result =
      source_request()
      |> Map.put(:observables, ["comms.transport.connection_state"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:03:02Z],
        transports_fun: fn _organization_id, _mission_id, _opts ->
          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            ),
            transport("transport-beta", "Backup TCP",
              source_endpoint_id: "endpoint-beta",
              link_assignment_id: "link-beta"
            )
          ]
        end,
        source_endpoints_fun: fn _organization_id, _mission_id, _opts -> [] end,
        connection_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              link_assignment_id: "link-alpha",
              adapter_key: :tcp_socket,
              connection_state: :connected,
              observed_at: ~U[2026-06-17 12:03:00Z],
              interval_id: "effective_interval:transport_connection_state:conn-event-alpha",
              source_event_id: "conn-event-alpha",
              interval: %{
                kind: :transport_connection_state,
                interval_id: "effective_interval:transport_connection_state:conn-event-alpha",
                source_event_id: "conn-event-alpha",
                starts_at: ~U[2026-06-17 12:03:00Z]
              }
            },
            %{
              transport_id: "transport-beta",
              source_endpoint_id: "endpoint-beta",
              link_assignment_id: "link-beta",
              connection_state: :disconnected,
              observed_at: ~U[2026-06-17 12:03:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result

    assert [
             %Field{name: "observable_id", values: ["comms.transport.connection_state"]},
             %Field{name: "resource_id", values: ["transport-alpha"]},
             %Field{name: "label", values: ["Lab TCP"]},
             %Field{name: "scope_kind", values: [:transport]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "adapter_key", values: [:tcp_socket]},
             %Field{name: "connection_state", values: [:connected]} | _rest
           ] = frame.fields

    assert field_values(frame, "interval_id") == [
             "effective_interval:transport_connection_state:conn-event-alpha"
           ]

    assert field_values(frame, "source_event_id") == ["conn-event-alpha"]
    assert "conn-event-alpha" in operational_event_link_ids(frame)

    assert {
             :transport_connection_state_interval,
             "effective_interval:transport_connection_state:conn-event-alpha"
           } in evidence_identities(frame)

    assert {:operational_interval, "conn-event-alpha"} in evidence_identities(frame)
  end

  test "latest RF state frames preserve selected interval evidence from canonical intervals" do
    result =
      source_request()
      |> Map.put(:observables, ["link.rf_lock_state", "link.frame_sync_state"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:10:02Z],
        transports_fun: fn _organization_id, _mission_id, _opts ->
          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            )
          ]
        end,
        link_rf_lock_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              lock_state: :locked,
              observed_at: ~U[2026-06-17 12:10:00Z],
              interval_id: "effective_interval:link_rf_lock_state:rf-lock-event-alpha",
              source_event_id: "rf-lock-event-alpha",
              interval: %{
                kind: :link_rf_lock_state,
                interval_id: "effective_interval:link_rf_lock_state:rf-lock-event-alpha",
                source_event_id: "rf-lock-event-alpha",
                starts_at: ~U[2026-06-17 12:10:00Z]
              }
            }
          ]
        end,
        link_rf_frame_sync_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              frame_sync_state: :synchronized,
              observed_at: ~U[2026-06-17 12:10:01Z],
              interval_id: "effective_interval:link_frame_sync_state:frame-sync-event-alpha",
              source_event_id: "frame-sync-event-alpha",
              interval: %{
                kind: :link_frame_sync_state,
                interval_id: "effective_interval:link_frame_sync_state:frame-sync-event-alpha",
                source_event_id: "frame-sync-event-alpha",
                starts_at: ~U[2026-06-17 12:10:01Z]
              }
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: frames, warnings: []} = result

    lock_frame =
      Enum.find(frames, &(&1.meta.supported_capability == :link_rf_lock_state))

    sync_frame =
      Enum.find(frames, &(&1.meta.supported_capability == :link_rf_frame_sync_state))

    assert field_values(lock_frame, "interval_id") == [
             "effective_interval:link_rf_lock_state:rf-lock-event-alpha"
           ]

    assert field_values(lock_frame, "source_event_id") == ["rf-lock-event-alpha"]
    assert "rf-lock-event-alpha" in operational_event_link_ids(lock_frame)

    assert {
             :link_rf_lock_state_interval,
             "effective_interval:link_rf_lock_state:rf-lock-event-alpha"
           } in evidence_identities(lock_frame)

    assert {:operational_interval, "rf-lock-event-alpha"} in evidence_identities(lock_frame)

    assert field_values(sync_frame, "interval_id") == [
             "effective_interval:link_frame_sync_state:frame-sync-event-alpha"
           ]

    assert field_values(sync_frame, "source_event_id") == ["frame-sync-event-alpha"]
    assert "frame-sync-event-alpha" in operational_event_link_ids(sync_frame)

    assert {
             :link_frame_sync_state_interval,
             "effective_interval:link_frame_sync_state:frame-sync-event-alpha"
           } in evidence_identities(sync_frame)

    assert {:operational_interval, "frame-sync-event-alpha"} in evidence_identities(sync_frame)
  end

  test "latest antenna pointing state preserves ground-station interval evidence" do
    result =
      source_request()
      |> Map.put(:observables, ["ground.station.antenna_pointing_state"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{
        primary: %{kind: :ground_station, mode: :one, ids: ["dss-14"]}
      })
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:10:02Z],
        source_endpoints_fun: fn _organization_id, _mission_id, _opts ->
          [
            source_endpoint("endpoint-alpha", "DSS-14 endpoint",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            )
          ]
        end,
        antenna_pointing_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              observable_id: "ground.station.antenna_pointing_state",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :antenna_adapter,
              acquisition_state: :tracking,
              observed_at: ~U[2026-06-17 12:10:00Z],
              interval_id:
                "effective_interval:operational_observable_state:antenna-pointing-event-alpha",
              source_event_id: "antenna-pointing-event-alpha",
              interval: %EffectiveInterval{
                kind: :operational_observable_state,
                interval_id:
                  "effective_interval:operational_observable_state:antenna-pointing-event-alpha",
                source_event_id: "antenna-pointing-event-alpha",
                starts_at: ~U[2026-06-17 12:10:00Z],
                payload: %{
                  "observable_id" => "ground.station.antenna_pointing_state",
                  "resource_id" => "dss-14"
                }
              }
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result

    assert result.meta.supported_capability == :ground_station_antenna_pointing_state
    assert frame.meta.supported_capability == :ground_station_antenna_pointing_state
    assert frame.meta.product_family == :ground_station
    assert frame.meta.state_color_policy == :antenna_pointing_state
    assert frame.meta.returned_points == 1

    assert [
             %Field{name: "observable_id", values: ["ground.station.antenna_pointing_state"]},
             %Field{name: "resource_id", values: ["dss-14"]},
             %Field{name: "label", values: ["Antenna pointing / DSS-14 endpoint"]},
             %Field{name: "scope_kind", values: [:ground_station]},
             %Field{name: "transport_id", values: [nil]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "adapter_key", values: [:antenna_adapter]},
             %Field{name: "state", values: [:tracking]},
             %Field{name: "normalized_state", values: [:green]} | _rest
           ] = frame.fields

    assert field_values(frame, "interval_id") == [
             "effective_interval:operational_observable_state:antenna-pointing-event-alpha"
           ]

    assert field_values(frame, "source_event_id") == ["antenna-pointing-event-alpha"]
    assert "antenna-pointing-event-alpha" in operational_event_link_ids(frame)

    assert {
             :ground_station_antenna_pointing_state_interval,
             "effective_interval:operational_observable_state:antenna-pointing-event-alpha"
           } in evidence_identities(frame)

    assert {:operational_interval, "antenna-pointing-event-alpha"} in evidence_identities(frame)
  end

  test "resolves connection state event history from runtime snapshots" do
    from_time = ~U[2026-06-17 12:01:00Z]
    to_time = ~U[2026-06-17 12:03:00Z]

    result =
      source_request()
      |> Map.put(:observables, ["comms.transport.connection_state"])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{from: from_time, to: to_time})
      |> Map.put(:scope_context, %{
        primary: %{kind: :transport, mode: :one, ids: ["transport-alpha"]}
      })
      |> OperationalObservables.resolve(
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:history_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14"
            ),
            transport("transport-beta", "Backup TCP", source_endpoint_id: "endpoint-beta")
          ]
        end,
        source_endpoints_fun: fn _organization_id, _mission_id, _opts -> [] end,
        connection_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:history_connection_snapshots, organization_id, mission_id, opts})

          [
            %{
              observable_id: "ground.station.connection_state",
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              adapter_key: :tcp_socket,
              connection_state: :disconnected,
              observed_at: ~U[2026-06-17 12:01:30Z]
            },
            %{
              observable_id: "comms.transport.connection_state",
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              adapter_key: :tcp_socket,
              connection_state: :connecting,
              observed_at: ~U[2026-06-17 12:01:00Z]
            },
            %{
              observable_id: "comms.transport.connection_state",
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              adapter_key: :tcp_socket,
              connection_state: :connected,
              observed_at: ~U[2026-06-17 12:02:00Z]
            },
            %{
              transport_id: "transport-alpha",
              connection_state: :disconnected,
              observed_at: ~U[2026-06-17 12:05:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result

    assert %Frame{source: :operational_observables, shape: :events, time_axis: :occurred_at} =
             frame

    assert result.meta.supported_capability == :connection_state_history
    assert frame.meta.supported_capability == :connection_state_history
    assert frame.meta.sampling == :event_history
    assert frame.meta.returned_points == 2

    assert [
             %Field{name: "time", values: [~U[2026-06-17 12:01:00Z], ~U[2026-06-17 12:02:00Z]]},
             %Field{
               name: "observable_id",
               values: ["comms.transport.connection_state", "comms.transport.connection_state"]
             },
             %Field{name: "resource_id", values: ["transport-alpha", "transport-alpha"]},
             %Field{name: "label", values: ["Lab TCP", "Lab TCP"]},
             %Field{name: "scope_kind", values: [:transport, :transport]},
             %Field{name: "transport_id", values: ["transport-alpha", "transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha", "endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14", "dss-14"]},
             %Field{name: "link_id", values: [nil, nil]},
             %Field{name: "adapter_key", values: [:tcp_socket, :tcp_socket]},
             %Field{name: "connection_state", values: [:connecting, :connected]},
             %Field{name: "normalized_state", values: [:connecting, :connected]}
           ] = frame.fields

    assert_received {:history_transports, "org-1", "mission-1", opts}
    assert opts[:from] == from_time
    assert opts[:to] == to_time

    assert_received {:history_connection_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "resolves antenna pointing state event history filtered to ground-station scope" do
    from_time = ~U[2026-06-17 12:01:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    result =
      source_request()
      |> Map.put(:observables, ["ground.station.antenna_pointing_state"])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{from: from_time, to: to_time})
      |> Map.put(:scope_context, %{
        primary: %{kind: :ground_station, mode: :one, ids: ["dss-14"]}
      })
      |> OperationalObservables.resolve(
        source_endpoints_fun: fn organization_id, mission_id, opts ->
          send(self(), {:antenna_history_source_endpoints, organization_id, mission_id, opts})

          [
            source_endpoint("endpoint-alpha", "DSS-14 endpoint",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            ),
            source_endpoint("endpoint-beta", "DSS-63 endpoint", ground_station_id: "dss-63")
          ]
        end,
        antenna_pointing_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:antenna_history_snapshots, organization_id, mission_id, opts})

          [
            %{
              observable_id: "ground.station.antenna_pointing_state",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              adapter_key: :antenna_adapter,
              pointing_state: :slewing,
              observed_at: ~U[2026-06-17 12:01:30Z]
            },
            %{
              observable_id: "ground.station.antenna_pointing_state",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              adapter_key: :antenna_adapter,
              pointing_state: :tracking,
              observed_at: ~U[2026-06-17 12:02:30Z]
            },
            %{
              observable_id: "ground.station.antenna_pointing_state",
              source_endpoint_id: "endpoint-beta",
              ground_station_id: "dss-63",
              adapter_key: :antenna_adapter,
              pointing_state: :tracking,
              observed_at: ~U[2026-06-17 12:03:30Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result

    assert result.meta.supported_capability == :ground_station_antenna_pointing_state_history
    assert frame.meta.supported_capability == :ground_station_antenna_pointing_state_history
    assert frame.meta.sampling == :event_history
    assert frame.meta.product_family == :ground_station
    assert frame.meta.state_color_policy == :antenna_pointing_state
    assert frame.meta.returned_points == 2

    assert [
             %Field{
               name: "time",
               values: [~U[2026-06-17 12:01:30Z], ~U[2026-06-17 12:02:30Z]]
             },
             %Field{
               name: "observable_id",
               values: [
                 "ground.station.antenna_pointing_state",
                 "ground.station.antenna_pointing_state"
               ]
             },
             %Field{name: "resource_id", values: ["dss-14", "dss-14"]},
             %Field{name: "lane_id", values: ["dss-14", "dss-14"]},
             %Field{
               name: "label",
               values: [
                 "Antenna pointing / DSS-14 endpoint",
                 "Antenna pointing / DSS-14 endpoint"
               ]
             },
             %Field{name: "scope_kind", values: [:ground_station, :ground_station]},
             %Field{name: "transport_id", values: [nil, nil]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha", "endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14", "dss-14"]},
             %Field{name: "link_id", values: ["link-alpha", "link-alpha"]},
             %Field{name: "adapter_key", values: [:antenna_adapter, :antenna_adapter]},
             %Field{name: "state", values: [:slewing, :tracking]},
             %Field{name: "normalized_state", values: [:blue, :green]}
           ] = frame.fields

    assert_received {:antenna_history_source_endpoints, "org-1", "mission-1", opts}
    assert opts[:from] == from_time
    assert opts[:to] == to_time

    assert_received {:antenna_history_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "filters connection state history rows to link scope" do
    result =
      source_request()
      |> Map.put(:observables, ["comms.transport.connection_state"])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{
        from: ~U[2026-06-17 12:01:00Z],
        to: ~U[2026-06-17 12:03:00Z]
      })
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        transports_fun: fn _organization_id, _mission_id, _opts ->
          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            ),
            transport("transport-beta", "Backup TCP",
              source_endpoint_id: "endpoint-beta",
              link_assignment_id: "link-beta"
            )
          ]
        end,
        source_endpoints_fun: fn _organization_id, _mission_id, _opts -> [] end,
        connection_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              transport_id: "transport-alpha",
              link_assignment_id: "link-alpha",
              connection_state: :connecting,
              observed_at: ~U[2026-06-17 12:01:00Z]
            },
            %{
              transport_id: "transport-beta",
              link_assignment_id: "link-beta",
              connection_state: :connected,
              observed_at: ~U[2026-06-17 12:02:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result

    assert [
             %Field{name: "time", values: [~U[2026-06-17 12:01:00Z]]},
             %Field{name: "observable_id", values: ["comms.transport.connection_state"]},
             %Field{name: "resource_id", values: ["transport-alpha"]},
             %Field{name: "label", values: ["Lab TCP"]},
             %Field{name: "scope_kind", values: [:transport]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "adapter_key", values: [:tcp_socket]},
             %Field{name: "connection_state", values: [:connecting]} | _rest
           ] = frame.fields
  end

  test "resolves transport execution event history from operational intervals" do
    from_time = ~U[2026-06-17 12:01:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    transport_execution_intervals_fun = fn organization_id, mission_id, opts ->
      send(self(), {:transport_execution_intervals, organization_id, mission_id, opts})

      [
        transport_execution_interval(
          "interval-1",
          "transport-alpha",
          :initialized,
          ~U[2026-06-17 12:00:30Z],
          ~U[2026-06-17 12:02:00Z]
        ),
        transport_execution_interval(
          "interval-2",
          "transport-alpha",
          :control_input_handled,
          ~U[2026-06-17 12:02:00Z],
          ~U[2026-06-17 12:05:00Z],
          contact_id: "contact-alpha",
          path_id: "uplink-alpha",
          transport_record_id: "record-alpha-2",
          source_event_id: "event-alpha-2"
        ),
        transport_execution_interval(
          "interval-3",
          "transport-beta",
          :timer_handled,
          ~U[2026-06-17 12:02:30Z],
          ~U[2026-06-17 12:03:00Z]
        )
      ]
    end

    result =
      source_request()
      |> Map.put(:observables, ["comms.transport.execution_state"])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{from: from_time, to: to_time})
      |> Map.put(:scope_context, %{
        primary: %{kind: :transport, mode: :one, ids: ["transport-alpha"]}
      })
      |> OperationalObservables.resolve(
        transport_execution_intervals_fun: transport_execution_intervals_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result

    assert %Frame{source: :operational_observables, shape: :events, time_axis: :occurred_at} =
             frame

    assert result.meta.supported_capability == :transport_execution_state_history
    assert frame.meta.supported_capability == :transport_execution_state_history
    assert frame.meta.product_family == :comms_transport
    assert frame.meta.state_color_policy == :transport_execution_state
    assert frame.meta.observable_id == "comms.transport.execution_state"
    assert frame.meta.returned_points == 2

    assert [
             %Field{
               name: "time",
               values: [~U[2026-06-17 12:00:30Z], ~U[2026-06-17 12:02:00Z]]
             },
             %Field{
               name: "ends_at",
               values: [~U[2026-06-17 12:02:00Z], ~U[2026-06-17 12:05:00Z]]
             },
             %Field{
               name: "observable_id",
               values: [
                 "comms.transport.execution_state",
                 "comms.transport.execution_state"
               ]
             },
             %Field{name: "resource_id", values: ["transport-alpha", "transport-alpha"]},
             %Field{name: "lane_id", values: ["transport-alpha", "transport-alpha"]},
             %Field{
               name: "label",
               values: [
                 "Transport execution / transport-alpha",
                 "Transport execution / transport-alpha"
               ]
             },
             %Field{name: "scope_kind", values: [:transport, :transport]},
             %Field{name: "transport_id", values: ["transport-alpha", "transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha", "endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14", "dss-14"]},
             %Field{name: "link_id", values: ["link-alpha", "link-alpha"]},
             %Field{name: "contact_id", values: ["contact-alpha", "contact-alpha"]},
             %Field{name: "path_id", values: ["uplink-alpha", "uplink-alpha"]},
             %Field{name: "transport_record_id", values: ["record-interval-1", "record-alpha-2"]},
             %Field{name: "interval_id", values: ["interval-1", "interval-2"]},
             %Field{name: "source_event_id", values: ["event-interval-1", "event-alpha-2"]},
             %Field{name: "state", values: [:initialized, :control_input_handled]},
             %Field{name: "normalized_state", values: [:initialized, :control_input_handled]}
           ] = frame.fields

    assert [
             %{
               kind: :transport_execution_interval,
               id: "interval-1",
               source: :events,
               confidence: :projected
             },
             %{kind: :operational_interval, id: "event-interval-1", confidence: :direct},
             %{kind: :transport_execution_interval, id: "interval-2", confidence: :projected},
             %{kind: :operational_interval, id: "event-alpha-2", confidence: :direct}
           ] = frame.meta.evidence_refs

    assert_received {:transport_execution_intervals, "org-1", "mission-1", opts}
    assert opts[:from] == from_time
    assert opts[:to] == to_time
    assert opts[:data_source_id] == "managed_operational_observables"
  end

  test "preserves replay context in transport execution interval reader options" do
    from_time = ~U[2026-06-17 12:01:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    transport_execution_intervals_fun = fn organization_id, mission_id, opts ->
      send(self(), {:replay_transport_execution_intervals, organization_id, mission_id, opts})

      [
        transport_execution_interval(
          "replay-interval-1",
          "transport-alpha",
          :initialized,
          ~U[2026-06-17 12:01:30Z],
          ~U[2026-06-17 12:02:30Z]
        )
      ]
    end

    result =
      source_request()
      |> Map.put(:observables, ["comms.transport.execution_state"])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{
        mode: :replay_run,
        from: from_time,
        to: to_time,
        replay_run_id: "replay-run-1"
      })
      |> Map.put(:data_context, %{realm: :replay, replay_run_id: "replay-run-1"})
      |> OperationalObservables.resolve(
        transport_execution_intervals_fun: transport_execution_intervals_fun,
        source_binding: replay_source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert frame.meta.realm == :replay
    assert frame.meta.data_source_id == "managed_operational_observables_replay"
    assert frame.meta.source_binding_id == "replay-operational-observables"
    assert frame.meta.dataset == "operational_observables_replay"
    assert frame.meta.replay_run_id == "replay-run-1"

    assert_received {:replay_transport_execution_intervals, "org-1", "mission-1", opts}
    assert opts[:realm] == :replay
    assert opts[:data_source_id] == "managed_operational_observables_replay"
    assert opts[:source_binding_id] == "replay-operational-observables"
    assert opts[:dataset] == "operational_observables_replay"
    assert opts[:replay_run_id] == "replay-run-1"
    assert opts[:from] == from_time
    assert opts[:to] == to_time
  end

  test "resolves replay managed runtime activity with operational event evidence" do
    from_time = ~U[2026-06-17 12:01:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    action_event =
      managed_runtime_event(
        "managed-action-1",
        :managed_action_request,
        :managed_action_requested,
        ~U[2026-06-17 12:01:30Z],
        action_kind: :schedule_timer,
        runtime_fact_id: "action-request-1",
        request_document: %{delay_ms: 5_000, timer_key: "flush"}
      )

    timer_event =
      managed_runtime_event(
        "managed-timer-1",
        :managed_timer_event,
        :managed_timer_fired,
        ~U[2026-06-17 12:02:30Z],
        timer_key: "flush",
        runtime_fact_id: "timer-event-1"
      )

    managed_runtime_events_fun = fn organization_id, mission_id, opts ->
      send(self(), {:managed_runtime_events, organization_id, mission_id, opts})
      [timer_event, action_event]
    end

    result =
      source_request()
      |> Map.put(:observables, ["runtime.managed_activity"])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{
        mode: :replay_run,
        from: from_time,
        to: to_time,
        replay_run_id: "replay-run-1"
      })
      |> Map.put(:data_context, %{realm: :replay, replay_run_id: "replay-run-1"})
      |> Map.put(:scope_context, %{
        primary: %{kind: :mission, mode: :one, ids: ["mission-1"]}
      })
      |> OperationalObservables.resolve(
        managed_runtime_events_fun: managed_runtime_events_fun,
        source_binding: replay_source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result

    assert %Frame{source: :operational_observables, shape: :events, time_axis: :occurred_at} =
             frame

    assert result.meta.supported_capability == :managed_runtime_activity_history
    assert frame.meta.supported_capability == :managed_runtime_activity_history
    assert frame.meta.product_family == :runtime_managed
    assert frame.meta.state_color_policy == :managed_runtime_activity
    assert frame.meta.observable_id == "runtime.managed_activity"
    assert frame.meta.realm == :replay
    assert frame.meta.dataset == "operational_observables_replay"
    assert frame.meta.replay_run_id == "replay-run-1"
    assert frame.meta.runtime_fact_ids == ["action-request-1", "timer-event-1"]
    assert frame.meta.returned_points == 2

    assert field_values(frame, "source_event_id") == ["managed-action-1", "managed-timer-1"]

    assert field_values(frame, "runtime_fact_kind") == [
             :managed_action_request,
             :managed_timer_event
           ]

    assert field_values(frame, "runtime_fact_id") == ["action-request-1", "timer-event-1"]
    assert field_values(frame, "state") == [:managed_action_requested, :managed_timer_fired]
    assert field_values(frame, "timer_key") == [nil, "flush"]
    assert field_values(frame, "action_kind") == [:schedule_timer, nil]

    assert field_values(frame, "action_request_document_json") == [
             ~s({"delay_ms":5000,"timer_key":"flush"}),
             nil
           ]

    assert "managed-action-1" in operational_event_link_ids(frame)
    assert "managed-timer-1" in operational_event_link_ids(frame)

    assert evidence_identities(frame) == [
             {:operational_event, "managed-action-1"},
             {:operational_event, "managed-timer-1"}
           ]

    assert_received {:managed_runtime_events, "org-1", "mission-1", opts}
    assert opts[:realm] == :replay
    assert opts[:data_source_id] == "managed_operational_observables_replay"
    assert opts[:source_binding_id] == "replay-operational-observables"
    assert opts[:dataset] == "operational_observables_replay"
    assert opts[:replay_run_id] == "replay-run-1"
    assert opts[:from] == from_time
    assert opts[:to] == to_time
  end

  test "resolves replay managed capability record lifecycle with state snapshot evidence" do
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    initialized_event =
      managed_runtime_event(
        "managed-capability-initialized-1",
        :managed_capability_record,
        :managed_capability_initialized,
        ~U[2026-06-17 12:00:30Z],
        runtime_fact_id: "capability-record-initialized-1",
        event_kind: :initialized,
        emitted_record_kinds: [],
        emitted_record_count: 0,
        action_request_count: 0,
        state_snapshot: %{active?: true, heartbeat_count: 0}
      )

    record_event =
      managed_runtime_event(
        "managed-capability-record-handled-1",
        :managed_capability_record,
        :managed_capability_record_handled,
        ~U[2026-06-17 12:01:30Z],
        runtime_fact_id: "capability-record-handled-1",
        event_kind: :record_handled,
        emitted_record_kinds: [:limit_state, :derived_metric],
        emitted_record_count: 2,
        action_request_count: 1,
        state_snapshot: %{active?: true, heartbeat_count: 1},
        record_metadata: %{
          emitted_record_refs: ["limit-state-1", "derived-metric-1"],
          action_request_ids: ["managed-action-request-2"]
        }
      )

    timer_event =
      managed_runtime_event(
        "managed-capability-timer-handled-1",
        :managed_capability_record,
        :managed_capability_timer_handled,
        ~U[2026-06-17 12:02:30Z],
        runtime_fact_id: "capability-record-timer-handled-1",
        event_kind: :timer_handled,
        timer_key: "flush",
        emitted_record_kinds: [:flush_summary],
        emitted_record_count: 1,
        action_request_count: 0,
        state_snapshot: %{active?: false, heartbeat_count: 2}
      )

    result =
      source_request()
      |> Map.put(:observables, ["runtime.managed_activity"])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{
        mode: :replay_run,
        from: from_time,
        to: to_time,
        replay_run_id: "replay-run-1"
      })
      |> Map.put(:data_context, %{realm: :replay, replay_run_id: "replay-run-1"})
      |> OperationalObservables.resolve(
        managed_runtime_events_fun: fn organization_id, mission_id, opts ->
          send(self(), {:managed_capability_events, organization_id, mission_id, opts})
          [timer_event, initialized_event, record_event]
        end,
        source_binding: replay_source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result

    assert frame.meta.supported_capability == :managed_runtime_activity_history

    assert frame.meta.runtime_fact_ids == [
             "capability-record-initialized-1",
             "capability-record-handled-1",
             "capability-record-timer-handled-1"
           ]

    assert field_values(frame, "source_event_id") == [
             "managed-capability-initialized-1",
             "managed-capability-record-handled-1",
             "managed-capability-timer-handled-1"
           ]

    assert field_values(frame, "runtime_fact_kind") == [
             :managed_capability_record,
             :managed_capability_record,
             :managed_capability_record
           ]

    assert field_values(frame, "record_event_kind") == [
             :initialized,
             :record_handled,
             :timer_handled
           ]

    assert field_values(frame, "emitted_record_kinds") == [
             "",
             "derived_metric,limit_state",
             "flush_summary"
           ]

    assert field_values(frame, "emitted_record_count") == [0, 2, 1]
    assert field_values(frame, "action_request_count") == [0, 1, 0]
    assert field_values(frame, "timer_key") == [nil, nil, "flush"]

    assert field_values(frame, "state_snapshot_json") == [
             ~s({"active?":true,"heartbeat_count":0}),
             ~s({"active?":true,"heartbeat_count":1}),
             ~s({"active?":false,"heartbeat_count":2})
           ]

    assert field_values(frame, "record_metadata_json") == [
             nil,
             ~s({"action_request_ids":["managed-action-request-2"],"emitted_record_refs":["limit-state-1","derived-metric-1"]}),
             nil
           ]

    assert evidence_identities(frame) == [
             {:operational_event, "managed-capability-initialized-1"},
             {:operational_event, "managed-capability-record-handled-1"},
             {:operational_event, "managed-capability-timer-handled-1"}
           ]

    assert_received {:managed_capability_events, "org-1", "mission-1", opts}
    assert opts[:replay_run_id] == "replay-run-1"
    assert opts[:from] == from_time
    assert opts[:to] == to_time
  end

  test "resolves replay transport runtime activity with capability action and timer evidence" do
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:04:00Z]

    record_event =
      transport_runtime_event(
        "transport-capability-record-event-1",
        :transport_capability_record,
        :transport_control_input_handled,
        ~U[2026-06-17 12:01:00Z],
        runtime_fact_id: "transport-record-1",
        event_kind: :control_input_handled,
        emitted_record_kinds: [:uplink_frame],
        emitted_record_count: 1,
        action_request_count: 1,
        state_snapshot: %{cop1_state: "active", vcid: 7},
        record_metadata: %{
          emitted_record_refs: ["uplink-frame-1"],
          action_request_ids: ["transport-action-request-1"]
        }
      )

    action_event =
      transport_runtime_event(
        "transport-action-request-event-1",
        :transport_action_request,
        :transport_action_requested,
        ~U[2026-06-17 12:01:30Z],
        runtime_fact_id: "transport-action-request-1",
        action_kind: :release_command,
        command_release_attempt_id: "release-attempt-1",
        command_request_id: "command-request-1",
        command_name: "NOOP",
        signal_phase: :start,
        source_endpoint_ref: "endpoint-alpha",
        request_document: %{command_request_id: "command-request-1", frame_count: 1},
        action_metadata: %{release_attempt_id: "release-attempt-1"}
      )

    timer_event =
      transport_runtime_event(
        "transport-timer-event-1",
        :transport_timer_event,
        :transport_timer_fired,
        ~U[2026-06-17 12:02:00Z],
        runtime_fact_id: "transport-timer-1",
        event_kind: :fired,
        timer_key: "cop1_timeout",
        timer_metadata: %{action_request_id: "transport-action-request-1"}
      )

    satisfied_verifier_instance = %{
      command_verifier_instance_id: "verifier-instance-satisfied",
      command_release_attempt_id: "release-attempt-1",
      command_request_id: "command-request-1",
      lifecycle_state: :satisfied,
      matched_record_kind: :transport_action_request,
      matched_record_id: "transport-action-request-1",
      matched_at: ~U[2026-06-17 12:01:45Z]
    }

    failed_verifier_instance = %{
      command_verifier_instance_id: "verifier-instance-failed",
      command_release_attempt_id: "release-attempt-1",
      command_request_id: "command-request-1",
      lifecycle_state: :failed,
      matched_record_kind: :transport_action_request,
      matched_record_id: "transport-action-request-1",
      matched_at: ~U[2026-06-17 12:01:50Z],
      failure_reason: "failure_criteria_matched"
    }

    telemetry_verifier_instance = %{
      command_verifier_instance_id: "verifier-instance-telemetry-satisfied",
      command_release_attempt_id: "release-attempt-1",
      command_request_id: "command-request-1",
      lifecycle_state: :satisfied,
      matched_record_kind: :telemetry_sample,
      matched_record_id: "verifier-telemetry-sample-1",
      matched_at: ~U[2026-06-17 12:01:55Z]
    }

    capability_verifier_instance = %{
      command_verifier_instance_id: "verifier-instance-capability-satisfied",
      command_release_attempt_id: "release-attempt-1",
      command_request_id: "command-request-1",
      lifecycle_state: :satisfied,
      matched_record_kind: :transport_capability_record,
      matched_record_id: "transport-record-1",
      matched_at: ~U[2026-06-17 12:01:58Z]
    }

    timed_out_verifier_instance = %{
      command_verifier_instance_id: "verifier-instance-timed-out",
      command_release_attempt_id: "release-attempt-1",
      command_request_id: "command-request-1",
      lifecycle_state: :timed_out,
      matched_at: ~U[2026-06-17 12:02:30Z],
      failure_reason: "timed_out"
    }

    result =
      source_request()
      |> Map.put(:observables, ["runtime.transport_activity"])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{
        mode: :replay_run,
        from: from_time,
        to: to_time,
        replay_run_id: "replay-run-1"
      })
      |> Map.put(:data_context, %{realm: :replay, replay_run_id: "replay-run-1"})
      |> Map.put(:scope_context, %{
        primary: %{kind: :transport, mode: :one, ids: ["transport-alpha"]}
      })
      |> OperationalObservables.resolve(
        transport_runtime_events_fun: fn organization_id, mission_id, opts ->
          send(self(), {:transport_runtime_events, organization_id, mission_id, opts})
          [timer_event, record_event, action_event]
        end,
        command_verifier_instances_fun: fn organization_id, mission_id, opts ->
          send(self(), {:command_verifier_instances, organization_id, mission_id, opts})

          [
            satisfied_verifier_instance,
            failed_verifier_instance,
            telemetry_verifier_instance,
            capability_verifier_instance,
            timed_out_verifier_instance
          ]
        end,
        source_binding: replay_source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result

    assert %Frame{source: :operational_observables, shape: :events, time_axis: :occurred_at} =
             frame

    assert result.meta.supported_capability == :transport_runtime_activity_history
    assert frame.meta.supported_capability == :transport_runtime_activity_history
    assert frame.meta.product_family == :runtime_transport
    assert frame.meta.state_color_policy == :transport_runtime_activity
    assert frame.meta.observable_id == "runtime.transport_activity"
    assert frame.meta.realm == :replay
    assert frame.meta.dataset == "operational_observables_replay"
    assert frame.meta.replay_run_id == "replay-run-1"

    assert frame.meta.runtime_fact_ids == [
             "transport-record-1",
             "transport-action-request-1",
             "transport-timer-1"
           ]

    assert field_values(frame, "source_event_id") == [
             "transport-capability-record-event-1",
             "transport-action-request-event-1",
             "transport-timer-event-1"
           ]

    assert field_values(frame, "runtime_fact_kind") == [
             :transport_capability_record,
             :transport_action_request,
             :transport_timer_event
           ]

    assert field_values(frame, "runtime_fact_id") == [
             "transport-record-1",
             "transport-action-request-1",
             "transport-timer-1"
           ]

    assert field_values(frame, "transport_id") == [
             "transport-alpha",
             "transport-alpha",
             "transport-alpha"
           ]

    assert field_values(frame, "contact_id") == [
             "replay-contact-alpha",
             "replay-contact-alpha",
             "replay-contact-alpha"
           ]

    assert field_values(frame, "path_id") == [
             "replay-uplink-path",
             "replay-uplink-path",
             "replay-uplink-path"
           ]

    assert field_values(frame, "source_endpoint_ref") == [nil, "endpoint-alpha", nil]

    assert field_values(frame, "state") == [
             :transport_control_input_handled,
             :transport_action_requested,
             :transport_timer_fired
           ]

    assert field_values(frame, "record_event_kind") == [:control_input_handled, nil, :fired]
    assert field_values(frame, "emitted_record_kinds") == ["uplink_frame", nil, nil]
    assert field_values(frame, "emitted_record_count") == [1, nil, nil]
    assert field_values(frame, "action_request_count") == [1, nil, nil]
    assert field_values(frame, "timer_key") == [nil, nil, "cop1_timeout"]
    assert field_values(frame, "action_kind") == [nil, :release_command, nil]
    assert field_values(frame, "command_release_attempt_id") == [nil, "release-attempt-1", nil]
    assert field_values(frame, "command_request_id") == [nil, "command-request-1", nil]

    assert field_values(frame, "command_verifier_instance_ids") == [
             nil,
             "verifier-instance-satisfied,verifier-instance-failed,verifier-instance-telemetry-satisfied,verifier-instance-capability-satisfied,verifier-instance-timed-out",
             nil
           ]

    assert field_values(frame, "command_verification_state") == [nil, :failed, nil]

    assert field_values(frame, "command_verifier_lifecycle_states") == [
             nil,
             "satisfied,failed,timed_out",
             nil
           ]

    assert field_values(frame, "command_verifier_matched_record_ids") == [
             nil,
             "transport-action-request-1,verifier-telemetry-sample-1,transport-record-1",
             nil
           ]

    assert field_values(frame, "command_verifier_failure_reasons") == [
             nil,
             "failure_criteria_matched,timed_out",
             nil
           ]

    assert field_values(frame, "command_name") == [nil, "NOOP", nil]
    assert field_values(frame, "signal_phase") == [nil, :start, nil]

    assert field_values(frame, "action_request_document_json") == [
             nil,
             ~s({"command_request_id":"command-request-1","frame_count":1}),
             nil
           ]

    assert field_values(frame, "state_snapshot_json") == [
             ~s({"cop1_state":"active","vcid":7}),
             nil,
             nil
           ]

    assert field_values(frame, "record_metadata_json") == [
             ~s({"action_request_ids":["transport-action-request-1"],"emitted_record_refs":["uplink-frame-1"]}),
             ~s({"release_attempt_id":"release-attempt-1"}),
             ~s({"action_request_id":"transport-action-request-1"})
           ]

    assert evidence_identities(frame) == [
             {:operational_event, "transport-capability-record-event-1"},
             {:operational_event, "transport-action-request-event-1"},
             {:operational_event, "transport-timer-event-1"},
             {:command_release_attempt, "release-attempt-1"},
             {:command_verifier_instance, "verifier-instance-satisfied"},
             {:command_verifier_instance, "verifier-instance-failed"},
             {:command_verifier_instance, "verifier-instance-telemetry-satisfied"},
             {:command_verifier_instance, "verifier-instance-capability-satisfied"},
             {:command_verifier_instance, "verifier-instance-timed-out"},
             {:transport_action_request, "transport-action-request-1"},
             {:telemetry_sample, "verifier-telemetry-sample-1"},
             {:transport_capability_record, "transport-record-1"}
           ]

    assert_received {:transport_runtime_events, "org-1", "mission-1", opts}
    assert opts[:realm] == :replay
    assert opts[:data_source_id] == "managed_operational_observables_replay"
    assert opts[:source_binding_id] == "replay-operational-observables"
    assert opts[:dataset] == "operational_observables_replay"
    assert opts[:replay_run_id] == "replay-run-1"
    assert opts[:from] == from_time
    assert opts[:to] == to_time

    assert_received {:command_verifier_instances, "org-1", "mission-1", verifier_opts}
    assert verifier_opts[:command_release_attempt_ids] == ["release-attempt-1"]
    assert verifier_opts[:replay_run_id] == "replay-run-1"
  end

  test "filters transport execution history rows to operational resource scopes" do
    intervals = [
      transport_execution_interval(
        "link-alpha-interval",
        "transport-alpha",
        :initialized,
        ~U[2026-06-17 12:00:00Z],
        ~U[2026-06-17 12:01:00Z],
        source_endpoint_id: "endpoint-alpha",
        ground_station_id: "dss-14",
        link_id: "link-alpha"
      ),
      transport_execution_interval(
        "link-beta-interval",
        "transport-beta",
        :timer_handled,
        ~U[2026-06-17 12:01:00Z],
        ~U[2026-06-17 12:02:00Z],
        source_endpoint_id: "endpoint-beta",
        ground_station_id: "dss-63",
        link_id: "link-beta"
      )
    ]

    for {scope_kind, scope_id, expected_interval_id} <- [
          {:source_endpoint, "endpoint-beta", "link-beta-interval"},
          {:ground_station, "dss-63", "link-beta-interval"},
          {:link, "link-beta", "link-beta-interval"}
        ] do
      result =
        source_request()
        |> Map.put(:observables, ["comms.transport.execution_state"])
        |> Map.put(:sampling, %{mode: :event_history, limit: 10})
        |> Map.put(:time_context, %{
          from: ~U[2026-06-17 12:00:00Z],
          to: ~U[2026-06-17 12:03:00Z]
        })
        |> Map.put(:scope_context, %{primary: %{kind: scope_kind, mode: :one, ids: [scope_id]}})
        |> OperationalObservables.resolve(
          transport_execution_intervals_fun: fn _organization_id, _mission_id, _opts ->
            intervals
          end,
          source_binding: source_binding()
        )

      assert %SourceResult{frames: [frame], warnings: []} = result
      assert field_values(frame, "interval_id") == [expected_interval_id]
      assert field_values(frame, "#{scope_kind}_id") == [scope_id]
    end

    result =
      source_request()
      |> Map.put(:observables, ["comms.transport.execution_state"])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{
        from: ~U[2026-06-17 12:00:00Z],
        to: ~U[2026-06-17 12:03:00Z]
      })
      |> Map.put(:scope_context, %{
        primary: %{kind: :link, mode: :many, ids: ["link-alpha", "link-beta"]}
      })
      |> OperationalObservables.resolve(
        transport_execution_intervals_fun: fn _organization_id, _mission_id, _opts ->
          intervals
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert field_values(frame, "interval_id") == ["link-alpha-interval", "link-beta-interval"]
    assert field_values(frame, "link_id") == ["link-alpha", "link-beta"]
  end

  test "resolves RF lock state from configured links and runtime snapshots" do
    result =
      source_request()
      |> Map.put(:observables, ["link.rf_lock_state"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:07:02Z],
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:rf_lock_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            ),
            transport("transport-beta", "Backup TCP",
              source_endpoint_id: "endpoint-beta",
              link_assignment_id: "link-beta"
            )
          ]
        end,
        link_rf_lock_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:rf_lock_snapshots, organization_id, mission_id, opts})

          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              lock_state: "locked",
              observed_at: ~U[2026-06-17 12:07:00Z]
            },
            %{
              transport_id: "transport-beta",
              link_assignment_id: "link-beta",
              lock_state: :unlocked,
              observed_at: ~U[2026-06-17 12:07:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :matrix, time_axis: nil} = frame
    assert result.meta.supported_capability == :link_rf_lock_state
    assert frame.meta.supported_capability == :link_rf_lock_state
    assert frame.meta.product_family == :link_rf
    assert frame.meta.state_color_policy == :lock_state
    assert frame.meta.observable_id == "link.rf_lock_state"
    assert frame.meta.returned_points == 1

    assert Enum.map(frame.meta.links, &{&1.target, &1.target_id}) == [
             {:transport, "transport-alpha"},
             {:source_endpoint, "endpoint-alpha"},
             {:ground_station, "dss-14"},
             {:link, "link-alpha"}
           ]

    assert [
             %Field{name: "observable_id", values: ["link.rf_lock_state"]},
             %Field{name: "resource_id", values: ["link-alpha"]},
             %Field{name: "label", values: ["RF lock / link-alpha"]},
             %Field{name: "scope_kind", values: [:link]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "adapter_key", values: [:rf_adapter]},
             %Field{name: "state", values: [:locked]},
             %Field{name: "normalized_state", values: [:green]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:07:00Z]]},
             %Field{name: "freshness_state", values: [:fresh]},
             %Field{name: "age_ms", values: [2_000]}
           ] = frame.fields

    assert_received {:rf_lock_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:rf_lock_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "marks configured link RF lock rows missing when runtime snapshots are absent" do
    result =
      source_request()
      |> Map.put(:observables, ["link.rf_lock_state"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:07:02Z],
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:missing_rf_lock_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            )
          ]
        end,
        link_rf_lock_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:missing_rf_lock_snapshots, organization_id, mission_id, opts})
          []
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{
             frames: [frame],
             warnings: [%ResolveWarning{code: :missing_snapshot, severity: :warning} = warning]
           } = result

    assert result.meta.degraded?
    assert warning.message == "Operational observable snapshot is missing"
    assert warning.details.supported_capability == :link_rf_lock_state
    assert warning.details.frame_ids == ["ops-request-1:link_rf_lock_state"]
    assert warning.details.observable_ids == ["link.rf_lock_state"]
    assert frame.meta.warning_codes == [:missing_snapshot]
    assert frame.meta.freshness_checked_at == ~U[2026-06-17 12:07:02Z]

    assert Enum.map(frame.meta.links, &{&1.target, &1.target_id}) == [
             {:transport, "transport-alpha"},
             {:source_endpoint, "endpoint-alpha"},
             {:ground_station, "dss-14"},
             {:link, "link-alpha"}
           ]

    assert [
             %Field{name: "observable_id", values: ["link.rf_lock_state"]},
             %Field{name: "resource_id", values: ["link-alpha"]},
             %Field{name: "label", values: ["RF lock / link-alpha"]},
             %Field{name: "scope_kind", values: [:link]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "adapter_key", values: [:tcp_socket]},
             %Field{name: "state", values: [:unknown]},
             %Field{name: "normalized_state", values: [:unknown]},
             %Field{name: "observed_at", values: [nil]},
             %Field{name: "freshness_state", values: [:missing]},
             %Field{name: "age_ms", values: [nil]}
           ] = frame.fields

    assert_received {:missing_rf_lock_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:missing_rf_lock_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "resolves frame sync state from configured links and runtime snapshots" do
    result =
      source_request()
      |> Map.put(:observables, ["link.frame_sync_state"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:09:02Z],
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:frame_sync_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            ),
            transport("transport-beta", "Backup TCP",
              source_endpoint_id: "endpoint-beta",
              link_assignment_id: "link-beta"
            )
          ]
        end,
        link_rf_frame_sync_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:frame_sync_snapshots, organization_id, mission_id, opts})

          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              frame_sync_state: "synchronized",
              observed_at: ~U[2026-06-17 12:09:00Z]
            },
            %{
              transport_id: "transport-beta",
              link_assignment_id: "link-beta",
              frame_sync_state: :lost,
              observed_at: ~U[2026-06-17 12:09:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :matrix, time_axis: nil} = frame
    assert result.meta.supported_capability == :link_rf_frame_sync_state
    assert frame.meta.supported_capability == :link_rf_frame_sync_state
    assert frame.meta.product_family == :link_rf
    assert frame.meta.state_color_policy == :frame_sync_state
    assert frame.meta.observable_id == "link.frame_sync_state"
    assert frame.meta.returned_points == 1

    assert Enum.map(frame.meta.links, &{&1.target, &1.target_id}) == [
             {:transport, "transport-alpha"},
             {:source_endpoint, "endpoint-alpha"},
             {:ground_station, "dss-14"},
             {:link, "link-alpha"}
           ]

    assert [
             %Field{name: "observable_id", values: ["link.frame_sync_state"]},
             %Field{name: "resource_id", values: ["link-alpha"]},
             %Field{name: "label", values: ["Frame sync / link-alpha"]},
             %Field{name: "scope_kind", values: [:link]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "adapter_key", values: [:rf_adapter]},
             %Field{name: "state", values: [:synchronized]},
             %Field{name: "normalized_state", values: [:green]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:09:00Z]]},
             %Field{name: "freshness_state", values: [:fresh]},
             %Field{name: "age_ms", values: [2_000]}
           ] = frame.fields

    assert_received {:frame_sync_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:frame_sync_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "marks configured frame sync rows missing when runtime snapshots are absent" do
    result =
      source_request()
      |> Map.put(:observables, ["link.frame_sync_state"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:09:02Z],
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:missing_frame_sync_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            )
          ]
        end,
        link_rf_frame_sync_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:missing_frame_sync_snapshots, organization_id, mission_id, opts})
          []
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{
             frames: [frame],
             warnings: [%ResolveWarning{code: :missing_snapshot, severity: :warning} = warning]
           } = result

    assert result.meta.degraded?
    assert warning.message == "Operational observable snapshot is missing"
    assert warning.details.supported_capability == :link_rf_frame_sync_state
    assert warning.details.frame_ids == ["ops-request-1:link_rf_frame_sync_state"]
    assert warning.details.observable_ids == ["link.frame_sync_state"]
    assert frame.meta.supported_capability == :link_rf_frame_sync_state
    assert frame.meta.product_family == :link_rf
    assert frame.meta.state_color_policy == :frame_sync_state
    assert frame.meta.observable_id == "link.frame_sync_state"
    assert frame.meta.returned_points == 1
    assert frame.meta.warning_codes == [:missing_snapshot]
    assert frame.meta.freshness_checked_at == ~U[2026-06-17 12:09:02Z]

    assert Enum.map(frame.meta.links, &{&1.target, &1.target_id}) == [
             {:transport, "transport-alpha"},
             {:source_endpoint, "endpoint-alpha"},
             {:ground_station, "dss-14"},
             {:link, "link-alpha"}
           ]

    assert [
             %Field{name: "observable_id", values: ["link.frame_sync_state"]},
             %Field{name: "resource_id", values: ["link-alpha"]},
             %Field{name: "label", values: ["Frame sync / link-alpha"]},
             %Field{name: "scope_kind", values: [:link]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "adapter_key", values: [:tcp_socket]},
             %Field{name: "state", values: [:unknown]},
             %Field{name: "normalized_state", values: [:unknown]},
             %Field{name: "observed_at", values: [nil]},
             %Field{name: "freshness_state", values: [:missing]},
             %Field{name: "age_ms", values: [nil]}
           ] = frame.fields

    assert_received {:missing_frame_sync_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:missing_frame_sync_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "resolves RF SNR metric from configured links and runtime snapshots" do
    result =
      source_request()
      |> Map.put(:observables, ["link.snr_db"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:08:02Z],
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:rf_metric_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            ),
            transport("transport-beta", "Backup TCP",
              source_endpoint_id: "endpoint-beta",
              link_assignment_id: "link-beta"
            )
          ]
        end,
        link_rf_metric_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:rf_metric_snapshots, organization_id, mission_id, opts})

          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              snr_db: 12.75,
              observed_at: ~U[2026-06-17 12:08:00Z]
            },
            %{
              transport_id: "transport-beta",
              link_assignment_id: "link-beta",
              snr_db: 7.5,
              observed_at: ~U[2026-06-17 12:08:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :matrix, time_axis: nil} = frame
    assert result.meta.supported_capability == :link_rf_metric
    assert frame.meta.supported_capability == :link_rf_metric
    assert frame.meta.product_family == :link_rf
    assert frame.meta.observable_ids == ["link.snr_db"]
    assert frame.meta.returned_points == 1

    assert Enum.map(frame.meta.links, &{&1.target, &1.target_id}) == [
             {:transport, "transport-alpha"},
             {:source_endpoint, "endpoint-alpha"},
             {:ground_station, "dss-14"},
             {:link, "link-alpha"}
           ]

    assert [
             %Field{name: "observable_id", values: ["link.snr_db"]},
             %Field{name: "resource_id", values: ["link-alpha"]},
             %Field{name: "label", values: ["RF SNR / link-alpha"]},
             %Field{name: "scope_kind", values: [:link]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "adapter_key", values: [:rf_adapter]},
             %Field{name: "value", values: [12.75]},
             %Field{name: "unit", values: ["dB"]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:08:00Z]]},
             %Field{name: "freshness_state", values: [:fresh]},
             %Field{name: "age_ms", values: [2_000]}
           ] = frame.fields

    assert_received {:rf_metric_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:rf_metric_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "resolves RF Eb/N0 metric from configured links and runtime snapshots" do
    result =
      source_request()
      |> Map.put(:observables, ["link.eb_n0_db"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:08:03Z],
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:eb_n0_metric_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            ),
            transport("transport-beta", "Backup TCP",
              source_endpoint_id: "endpoint-beta",
              link_assignment_id: "link-beta"
            )
          ]
        end,
        link_rf_metric_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:eb_n0_metric_snapshots, organization_id, mission_id, opts})

          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              eb_n0_db: 9.75,
              observed_at: ~U[2026-06-17 12:08:00Z]
            },
            %{
              transport_id: "transport-beta",
              link_assignment_id: "link-beta",
              eb_n0_db: 6.5,
              observed_at: ~U[2026-06-17 12:08:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :matrix, time_axis: nil} = frame
    assert result.meta.supported_capability == :link_rf_metric
    assert frame.meta.supported_capability == :link_rf_metric
    assert frame.meta.product_family == :link_rf
    assert frame.meta.observable_ids == ["link.eb_n0_db"]
    assert frame.meta.returned_points == 1

    assert [
             %Field{name: "observable_id", values: ["link.eb_n0_db"]},
             %Field{name: "resource_id", values: ["link-alpha"]},
             %Field{name: "label", values: ["RF Eb/N0 / link-alpha"]},
             %Field{name: "scope_kind", values: [:link]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "adapter_key", values: [:rf_adapter]},
             %Field{name: "value", values: [9.75]},
             %Field{name: "unit", values: ["dB"]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:08:00Z]]},
             %Field{name: "freshness_state", values: [:fresh]},
             %Field{name: "age_ms", values: [3_000]}
           ] = frame.fields

    assert_received {:eb_n0_metric_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:eb_n0_metric_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "resolves RF symbol-rate metric from configured links and runtime snapshots" do
    result =
      source_request()
      |> Map.put(:observables, ["link.symbol_rate_sps"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:08:04Z],
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:symbol_rate_metric_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            ),
            transport("transport-beta", "Backup TCP",
              source_endpoint_id: "endpoint-beta",
              link_assignment_id: "link-beta"
            )
          ]
        end,
        link_rf_metric_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:symbol_rate_metric_snapshots, organization_id, mission_id, opts})

          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              symbol_rate_sps: 1_024_000.0,
              observed_at: ~U[2026-06-17 12:08:00Z]
            },
            %{
              transport_id: "transport-beta",
              link_assignment_id: "link-beta",
              symbols_per_second: 512_000.0,
              observed_at: ~U[2026-06-17 12:08:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :matrix, time_axis: nil} = frame
    assert result.meta.supported_capability == :link_rf_metric
    assert frame.meta.supported_capability == :link_rf_metric
    assert frame.meta.product_family == :link_rf
    assert frame.meta.observable_ids == ["link.symbol_rate_sps"]
    assert frame.meta.returned_points == 1

    assert [
             %Field{name: "observable_id", values: ["link.symbol_rate_sps"]},
             %Field{name: "resource_id", values: ["link-alpha"]},
             %Field{name: "label", values: ["RF Symbol Rate / link-alpha"]},
             %Field{name: "scope_kind", values: [:link]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "adapter_key", values: [:rf_adapter]},
             %Field{name: "value", values: [1_024_000.0]},
             %Field{name: "unit", values: ["sym/s"]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:08:00Z]]},
             %Field{name: "freshness_state", values: [:fresh]},
             %Field{name: "age_ms", values: [4_000]}
           ] = frame.fields

    assert_received {:symbol_rate_metric_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:symbol_rate_metric_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "resolves RF Doppler metric from configured links and runtime snapshots" do
    result =
      source_request()
      |> Map.put(:observables, ["link.doppler_hz"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:08:04Z],
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:doppler_metric_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            ),
            transport("transport-beta", "Backup TCP",
              source_endpoint_id: "endpoint-beta",
              link_assignment_id: "link-beta"
            )
          ]
        end,
        link_rf_metric_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:doppler_metric_snapshots, organization_id, mission_id, opts})

          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              frequency_offset_hz: -42.5,
              observed_at: ~U[2026-06-17 12:08:00Z]
            },
            %{
              transport_id: "transport-beta",
              link_assignment_id: "link-beta",
              doppler_hz: 71.0,
              observed_at: ~U[2026-06-17 12:08:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :matrix, time_axis: nil} = frame
    assert result.meta.supported_capability == :link_rf_metric
    assert frame.meta.supported_capability == :link_rf_metric
    assert frame.meta.product_family == :link_rf
    assert frame.meta.observable_ids == ["link.doppler_hz"]
    assert frame.meta.returned_points == 1

    assert [
             %Field{name: "observable_id", values: ["link.doppler_hz"]},
             %Field{name: "resource_id", values: ["link-alpha"]},
             %Field{name: "label", values: ["RF Doppler / link-alpha"]},
             %Field{name: "scope_kind", values: [:link]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "adapter_key", values: [:rf_adapter]},
             %Field{name: "value", values: [-42.5]},
             %Field{name: "unit", values: ["Hz"]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:08:00Z]]},
             %Field{name: "freshness_state", values: [:fresh]},
             %Field{name: "age_ms", values: [4_000]}
           ] = frame.fields

    assert_received {:doppler_metric_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:doppler_metric_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "marks configured RF SNR metric rows missing when runtime snapshots are absent" do
    result =
      source_request()
      |> Map.put(:observables, ["link.snr_db"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:08:02Z],
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:missing_rf_metric_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            )
          ]
        end,
        link_rf_metric_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:missing_rf_metric_snapshots, organization_id, mission_id, opts})
          []
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{
             frames: [frame],
             warnings: [%ResolveWarning{code: :missing_snapshot, severity: :warning} = warning]
           } = result

    assert result.meta.degraded?
    assert warning.message == "Operational observable snapshot is missing"
    assert warning.details.supported_capability == :link_rf_metric
    assert warning.details.frame_ids == ["ops-request-1:link_rf_metric"]
    assert warning.details.observable_ids == ["link.snr_db"]
    assert frame.meta.supported_capability == :link_rf_metric
    assert frame.meta.product_family == :link_rf
    assert frame.meta.observable_ids == ["link.snr_db"]
    assert frame.meta.returned_points == 1
    assert frame.meta.warning_codes == [:missing_snapshot]
    assert frame.meta.freshness_checked_at == ~U[2026-06-17 12:08:02Z]

    assert Enum.map(frame.meta.links, &{&1.target, &1.target_id}) == [
             {:transport, "transport-alpha"},
             {:source_endpoint, "endpoint-alpha"},
             {:ground_station, "dss-14"},
             {:link, "link-alpha"}
           ]

    assert [
             %Field{name: "observable_id", values: ["link.snr_db"]},
             %Field{name: "resource_id", values: ["link-alpha"]},
             %Field{name: "label", values: ["RF SNR / link-alpha"]},
             %Field{name: "scope_kind", values: [:link]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "adapter_key", values: [:tcp_socket]},
             %Field{name: "value", values: [nil]},
             %Field{name: "unit", values: ["dB"]},
             %Field{name: "observed_at", values: [nil]},
             %Field{name: "freshness_state", values: [:missing]},
             %Field{name: "age_ms", values: [nil]}
           ] = frame.fields

    assert_received {:missing_rf_metric_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:missing_rf_metric_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "resolves RF SNR metric history into link-scoped wide frames" do
    result =
      source_request()
      |> Map.put(:observables, ["link.snr_db"])
      |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
      |> Map.put(:time_context, %{
        from: "2026-06-17T12:01:00Z",
        to: "2026-06-17T12:03:00Z"
      })
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:rf_metric_history_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            ),
            transport("transport-beta", "Backup TCP",
              source_endpoint_id: "endpoint-beta",
              link_assignment_id: "link-beta"
            )
          ]
        end,
        link_rf_metric_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:rf_metric_history_snapshots, organization_id, mission_id, opts})

          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              snr_db: 10.5,
              observed_at: ~U[2026-06-17 12:01:00Z]
            },
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              snr_db: 12.75,
              observed_at: ~U[2026-06-17 12:02:00Z]
            },
            %{
              transport_id: "transport-beta",
              link_assignment_id: "link-beta",
              snr_db: 7.5,
              observed_at: ~U[2026-06-17 12:02:00Z]
            },
            %{
              transport_id: "transport-alpha",
              link_assignment_id: "link-alpha",
              snr_db: 15.0,
              observed_at: ~U[2026-06-17 12:05:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :wide, time_axis: :occurred_at} = frame
    assert result.meta.supported_capability == :link_rf_metric_history
    assert frame.meta.supported_capability == :link_rf_metric_history
    assert frame.meta.product_family == :link_rf
    assert frame.meta.observable_id == "link.snr_db"
    assert frame.meta.resource_id == "link-alpha"
    assert frame.meta.unit == "dB"
    assert frame.meta.returned_points == 2

    assert [
             %Field{
               name: "time",
               values: [~U[2026-06-17 12:01:00Z], ~U[2026-06-17 12:02:00Z]],
               metadata: %{axis: :occurred_at}
             },
             %Field{
               name: "link.snr_db",
               kind: :number,
               values: [10.5, 12.75],
               metadata: %{
                 observable_id: "link.snr_db",
                 label: "RF SNR / link-alpha",
                 unit: "dB",
                 resource_id: "link-alpha",
                 scope_kind: :link,
                 transport_id: "transport-alpha",
                 source_endpoint_id: "endpoint-alpha",
                 ground_station_id: "dss-14",
                 link_id: "link-alpha",
                 adapter_key: :rf_adapter,
                 resource_link_id: "transport:transport-alpha:ops-request-1",
                 links: links
               }
             }
           ] = frame.fields

    assert [%{target: :transport, target_id: "transport-alpha"} | _rest] = links
    assert frame.meta.resource_link_id == "transport:transport-alpha:ops-request-1"

    assert_received {:rf_metric_history_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight
    assert opts[:from] == ~U[2026-06-17 12:01:00Z]
    assert opts[:to] == ~U[2026-06-17 12:03:00Z]

    assert_received {:rf_metric_history_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
    assert opts[:from] == ~U[2026-06-17 12:01:00Z]
    assert opts[:to] == ~U[2026-06-17 12:03:00Z]
  end

  test "resolves RF Eb/N0 metric history through generic RF metric samples" do
    result =
      source_request()
      |> Map.put(:observables, ["link.eb_n0_db"])
      |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
      |> Map.put(:time_context, %{
        from: "2026-06-17T12:01:00Z",
        to: "2026-06-17T12:03:00Z"
      })
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:eb_n0_history_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            ),
            transport("transport-beta", "Backup TCP",
              source_endpoint_id: "endpoint-beta",
              link_assignment_id: "link-beta"
            )
          ]
        end,
        link_rf_metric_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:eb_n0_history_snapshots, organization_id, mission_id, opts})

          [
            %{
              observable_id: "link.eb_n0_db",
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              value: 8.5,
              unit: "dB",
              observed_at: ~U[2026-06-17 12:01:00Z]
            },
            %{
              observable_id: "link.eb_n0_db",
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              value: 9.25,
              unit: "dB",
              observed_at: ~U[2026-06-17 12:02:00Z]
            },
            %{
              observable_id: "link.eb_n0_db",
              transport_id: "transport-beta",
              link_assignment_id: "link-beta",
              value: 6.5,
              unit: "dB",
              observed_at: ~U[2026-06-17 12:02:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :wide, time_axis: :occurred_at} = frame
    assert result.meta.supported_capability == :link_rf_metric_history
    assert frame.meta.supported_capability == :link_rf_metric_history
    assert frame.meta.product_family == :link_rf
    assert frame.meta.observable_id == "link.eb_n0_db"
    assert frame.meta.resource_id == "link-alpha"
    assert frame.meta.unit == "dB"
    assert frame.meta.returned_points == 2

    assert [
             %Field{
               name: "time",
               values: [~U[2026-06-17 12:01:00Z], ~U[2026-06-17 12:02:00Z]],
               metadata: %{axis: :occurred_at}
             },
             %Field{
               name: "link.eb_n0_db",
               kind: :number,
               values: [8.5, 9.25],
               metadata: %{
                 observable_id: "link.eb_n0_db",
                 label: "RF Eb/N0 / link-alpha",
                 unit: "dB",
                 resource_id: "link-alpha",
                 scope_kind: :link,
                 transport_id: "transport-alpha",
                 source_endpoint_id: "endpoint-alpha",
                 ground_station_id: "dss-14",
                 link_id: "link-alpha",
                 adapter_key: :rf_adapter,
                 resource_link_id: "transport:transport-alpha:ops-request-1",
                 links: links
               }
             }
           ] = frame.fields

    assert [%{target: :transport, target_id: "transport-alpha"} | _rest] = links
    assert frame.meta.resource_link_id == "transport:transport-alpha:ops-request-1"

    assert_received {:eb_n0_history_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight
    assert opts[:from] == ~U[2026-06-17 12:01:00Z]
    assert opts[:to] == ~U[2026-06-17 12:03:00Z]

    assert_received {:eb_n0_history_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
    assert opts[:from] == ~U[2026-06-17 12:01:00Z]
    assert opts[:to] == ~U[2026-06-17 12:03:00Z]
  end

  test "resolves RF symbol-rate metric history through generic RF metric samples" do
    result =
      source_request()
      |> Map.put(:observables, ["link.symbol_rate_sps"])
      |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
      |> Map.put(:time_context, %{
        from: "2026-06-17T12:01:00Z",
        to: "2026-06-17T12:03:00Z"
      })
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:symbol_rate_history_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            ),
            transport("transport-beta", "Backup TCP",
              source_endpoint_id: "endpoint-beta",
              link_assignment_id: "link-beta"
            )
          ]
        end,
        link_rf_metric_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:symbol_rate_history_snapshots, organization_id, mission_id, opts})

          [
            %{
              observable_id: "link.symbol_rate_sps",
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              symbol_rate_sps: 1_024_000.0,
              observed_at: ~U[2026-06-17 12:01:00Z]
            },
            %{
              observable_id: "link.symbol_rate_sps",
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              symbols_per_second: 2_048_000.0,
              observed_at: ~U[2026-06-17 12:02:00Z]
            },
            %{
              observable_id: "link.symbol_rate_sps",
              transport_id: "transport-beta",
              link_assignment_id: "link-beta",
              value: 512_000.0,
              unit: "sym/s",
              observed_at: ~U[2026-06-17 12:02:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :wide, time_axis: :occurred_at} = frame
    assert result.meta.supported_capability == :link_rf_metric_history
    assert frame.meta.supported_capability == :link_rf_metric_history
    assert frame.meta.product_family == :link_rf
    assert frame.meta.observable_id == "link.symbol_rate_sps"
    assert frame.meta.resource_id == "link-alpha"
    assert frame.meta.unit == "sym/s"
    assert frame.meta.returned_points == 2

    assert [
             %Field{
               name: "time",
               values: [~U[2026-06-17 12:01:00Z], ~U[2026-06-17 12:02:00Z]],
               metadata: %{axis: :occurred_at}
             },
             %Field{
               name: "link.symbol_rate_sps",
               kind: :number,
               values: [1_024_000.0, 2_048_000.0],
               metadata: %{
                 observable_id: "link.symbol_rate_sps",
                 label: "RF Symbol Rate / link-alpha",
                 unit: "sym/s",
                 resource_id: "link-alpha",
                 scope_kind: :link,
                 transport_id: "transport-alpha",
                 source_endpoint_id: "endpoint-alpha",
                 ground_station_id: "dss-14",
                 link_id: "link-alpha",
                 adapter_key: :rf_adapter,
                 resource_link_id: "transport:transport-alpha:ops-request-1",
                 links: links
               }
             }
           ] = frame.fields

    assert [%{target: :transport, target_id: "transport-alpha"} | _rest] = links
    assert frame.meta.resource_link_id == "transport:transport-alpha:ops-request-1"

    assert_received {:symbol_rate_history_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight
    assert opts[:from] == ~U[2026-06-17 12:01:00Z]
    assert opts[:to] == ~U[2026-06-17 12:03:00Z]

    assert_received {:symbol_rate_history_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
    assert opts[:from] == ~U[2026-06-17 12:01:00Z]
    assert opts[:to] == ~U[2026-06-17 12:03:00Z]
  end

  test "resolves RF Doppler metric history through generic RF metric samples" do
    result =
      source_request()
      |> Map.put(:observables, ["link.doppler_hz"])
      |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
      |> Map.put(:time_context, %{
        from: "2026-06-17T12:01:00Z",
        to: "2026-06-17T12:03:00Z"
      })
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:doppler_history_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            ),
            transport("transport-beta", "Backup TCP",
              source_endpoint_id: "endpoint-beta",
              link_assignment_id: "link-beta"
            )
          ]
        end,
        link_rf_metric_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:doppler_history_snapshots, organization_id, mission_id, opts})

          [
            %{
              observable_id: "link.doppler_hz",
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              frequency_offset_hz: -42.5,
              observed_at: ~U[2026-06-17 12:01:00Z]
            },
            %{
              observable_id: "link.doppler_hz",
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              carrier_frequency_offset_hz: -38.25,
              observed_at: ~U[2026-06-17 12:02:00Z]
            },
            %{
              observable_id: "link.doppler_hz",
              transport_id: "transport-beta",
              link_assignment_id: "link-beta",
              doppler_hz: 71.0,
              observed_at: ~U[2026-06-17 12:02:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :wide, time_axis: :occurred_at} = frame
    assert result.meta.supported_capability == :link_rf_metric_history
    assert frame.meta.supported_capability == :link_rf_metric_history
    assert frame.meta.product_family == :link_rf
    assert frame.meta.observable_id == "link.doppler_hz"
    assert frame.meta.resource_id == "link-alpha"
    assert frame.meta.unit == "Hz"
    assert frame.meta.returned_points == 2

    assert [
             %Field{
               name: "time",
               values: [~U[2026-06-17 12:01:00Z], ~U[2026-06-17 12:02:00Z]],
               metadata: %{axis: :occurred_at}
             },
             %Field{
               name: "link.doppler_hz",
               kind: :number,
               values: [-42.5, -38.25],
               metadata: %{
                 observable_id: "link.doppler_hz",
                 label: "RF Doppler / link-alpha",
                 unit: "Hz",
                 resource_id: "link-alpha",
                 scope_kind: :link,
                 transport_id: "transport-alpha",
                 source_endpoint_id: "endpoint-alpha",
                 ground_station_id: "dss-14",
                 link_id: "link-alpha",
                 adapter_key: :rf_adapter,
                 resource_link_id: "transport:transport-alpha:ops-request-1",
                 links: links
               }
             }
           ] = frame.fields

    assert [%{target: :transport, target_id: "transport-alpha"} | _rest] = links
    assert frame.meta.resource_link_id == "transport:transport-alpha:ops-request-1"

    assert_received {:doppler_history_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight
    assert opts[:from] == ~U[2026-06-17 12:01:00Z]
    assert opts[:to] == ~U[2026-06-17 12:03:00Z]

    assert_received {:doppler_history_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
    assert opts[:from] == ~U[2026-06-17 12:01:00Z]
    assert opts[:to] == ~U[2026-06-17 12:03:00Z]
  end

  test "resolves empty RF SNR metric history as a chartable zero-point frame" do
    result =
      source_request()
      |> Map.put(:observables, ["link.snr_db"])
      |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
      |> Map.put(:time_context, %{
        from: ~U[2026-06-17 12:01:00Z],
        to: ~U[2026-06-17 12:03:00Z]
      })
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:empty_rf_metric_history_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            )
          ]
        end,
        link_rf_metric_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:empty_rf_metric_history_snapshots, organization_id, mission_id, opts})
          []
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :wide, time_axis: :occurred_at} = frame
    refute result.meta.degraded?
    assert result.meta.supported_capability == :link_rf_metric_history
    assert frame.meta.supported_capability == :link_rf_metric_history
    assert frame.meta.product_family == :link_rf
    assert frame.meta.observable_id == "link.snr_db"
    assert frame.meta.resource_id == "link-alpha"
    assert frame.meta.scope_kind == :link
    assert frame.meta.transport_id == "transport-alpha"
    assert frame.meta.source_endpoint_id == "endpoint-alpha"
    assert frame.meta.ground_station_id == "dss-14"
    assert frame.meta.link_id == "link-alpha"
    assert frame.meta.unit == "dB"
    assert frame.meta.returned_points == 0
    assert frame.meta.warning_codes == []

    assert Enum.map(frame.meta.links, &{&1.target, &1.target_id}) == [
             {:transport, "transport-alpha"},
             {:source_endpoint, "endpoint-alpha"},
             {:ground_station, "dss-14"},
             {:link, "link-alpha"}
           ]

    assert [
             %Field{name: "time", values: []},
             %Field{
               name: "link.snr_db",
               values: [],
               metadata: %{
                 observable_id: "link.snr_db",
                 label: "RF SNR / link-alpha",
                 unit: "dB",
                 resource_id: "link-alpha",
                 scope_kind: :link,
                 transport_id: "transport-alpha",
                 source_endpoint_id: "endpoint-alpha",
                 ground_station_id: "dss-14",
                 link_id: "link-alpha",
                 adapter_key: :tcp_socket
               }
             }
           ] = frame.fields

    assert_received {:empty_rf_metric_history_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:empty_rf_metric_history_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "resolves RF lock event history from timestamped snapshots" do
    result =
      source_request()
      |> Map.put(:observables, ["link.rf_lock_state"])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{
        from: ~U[2026-06-17 12:01:00Z],
        to: ~U[2026-06-17 12:03:00Z]
      })
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        transports_fun: fn _organization_id, _mission_id, _opts ->
          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            ),
            transport("transport-beta", "Backup TCP",
              source_endpoint_id: "endpoint-beta",
              link_assignment_id: "link-beta"
            )
          ]
        end,
        link_rf_lock_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              transport_id: "transport-alpha",
              link_assignment_id: "link-alpha",
              lock_state: :acquiring,
              observed_at: ~U[2026-06-17 12:01:00Z]
            },
            %{
              transport_id: "transport-alpha",
              link_assignment_id: "link-alpha",
              lock_state: :locked,
              observed_at: ~U[2026-06-17 12:02:00Z]
            },
            %{
              transport_id: "transport-beta",
              link_assignment_id: "link-beta",
              lock_state: :unlocked,
              observed_at: ~U[2026-06-17 12:02:30Z]
            },
            %{
              transport_id: "transport-alpha",
              link_assignment_id: "link-alpha",
              lock_state: :degraded,
              observed_at: ~U[2026-06-17 12:05:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result

    assert %Frame{source: :operational_observables, shape: :events, time_axis: :occurred_at} =
             frame

    assert result.meta.supported_capability == :link_rf_lock_state_history
    assert frame.meta.supported_capability == :link_rf_lock_state_history
    assert frame.meta.product_family == :link_rf
    assert frame.meta.returned_points == 2

    assert [
             %Field{name: "time", values: [~U[2026-06-17 12:01:00Z], ~U[2026-06-17 12:02:00Z]]},
             %Field{name: "observable_id", values: ["link.rf_lock_state", "link.rf_lock_state"]},
             %Field{name: "resource_id", values: ["link-alpha", "link-alpha"]},
             %Field{name: "lane_id", values: ["link-alpha", "link-alpha"]},
             %Field{name: "label", values: ["RF lock / link-alpha", "RF lock / link-alpha"]},
             %Field{name: "scope_kind", values: [:link, :link]},
             %Field{name: "transport_id", values: ["transport-alpha", "transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha", "endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14", "dss-14"]},
             %Field{name: "link_id", values: ["link-alpha", "link-alpha"]},
             %Field{name: "adapter_key", values: [:tcp_socket, :tcp_socket]},
             %Field{name: "state", values: [:acquiring, :locked]},
             %Field{name: "normalized_state", values: [:blue, :green]}
           ] = frame.fields
  end

  test "resolves frame sync event history from timestamped snapshots" do
    result =
      source_request()
      |> Map.put(:observables, ["link.frame_sync_state"])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{
        from: ~U[2026-06-17 12:01:00Z],
        to: ~U[2026-06-17 12:03:00Z]
      })
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        transports_fun: fn _organization_id, _mission_id, _opts ->
          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            ),
            transport("transport-beta", "Backup TCP",
              source_endpoint_id: "endpoint-beta",
              link_assignment_id: "link-beta"
            )
          ]
        end,
        link_rf_frame_sync_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              transport_id: "transport-alpha",
              link_assignment_id: "link-alpha",
              frame_sync_state: :acquiring,
              observed_at: ~U[2026-06-17 12:01:00Z]
            },
            %{
              transport_id: "transport-alpha",
              link_assignment_id: "link-alpha",
              frame_sync_state: :synchronized,
              observed_at: ~U[2026-06-17 12:02:00Z]
            },
            %{
              transport_id: "transport-beta",
              link_assignment_id: "link-beta",
              frame_sync_state: :lost,
              observed_at: ~U[2026-06-17 12:02:30Z]
            },
            %{
              transport_id: "transport-alpha",
              link_assignment_id: "link-alpha",
              frame_sync_state: :lost,
              observed_at: ~U[2026-06-17 12:05:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result

    assert %Frame{source: :operational_observables, shape: :events, time_axis: :occurred_at} =
             frame

    assert result.meta.supported_capability == :link_rf_frame_sync_state_history
    assert frame.meta.supported_capability == :link_rf_frame_sync_state_history
    assert frame.meta.product_family == :link_rf
    assert frame.meta.state_color_policy == :frame_sync_state
    assert frame.meta.returned_points == 2

    assert [
             %Field{name: "time", values: [~U[2026-06-17 12:01:00Z], ~U[2026-06-17 12:02:00Z]]},
             %Field{
               name: "observable_id",
               values: ["link.frame_sync_state", "link.frame_sync_state"]
             },
             %Field{name: "resource_id", values: ["link-alpha", "link-alpha"]},
             %Field{name: "lane_id", values: ["link-alpha", "link-alpha"]},
             %Field{
               name: "label",
               values: ["Frame sync / link-alpha", "Frame sync / link-alpha"]
             },
             %Field{name: "scope_kind", values: [:link, :link]},
             %Field{name: "transport_id", values: ["transport-alpha", "transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha", "endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14", "dss-14"]},
             %Field{name: "link_id", values: ["link-alpha", "link-alpha"]},
             %Field{name: "adapter_key", values: [:tcp_socket, :tcp_socket]},
             %Field{name: "state", values: [:acquiring, :synchronized]},
             %Field{name: "normalized_state", values: [:blue, :green]}
           ] = frame.fields
  end

  test "resolves mixed operational state event history into product frames" do
    result =
      source_request()
      |> Map.put(:observables, [
        "contacts.phase",
        "comms.transport.connection_state",
        "link.rf_lock_state",
        "link.frame_sync_state"
      ])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{
        from: ~U[2026-06-17 12:00:00Z],
        to: ~U[2026-06-17 12:03:00Z]
      })
      |> OperationalObservables.resolve(
        scheduled_contacts_fun: fn _organization_id, _mission_id, _opts ->
          [scheduled_contact("contact-1", :scheduled)]
        end,
        realized_contacts_fun: fn _organization_id, _mission_id, _opts ->
          [realized_contact("contact-1-run", :active, scheduled_contact_id: "contact-1")]
        end,
        transports_fun: fn _organization_id, _mission_id, _opts ->
          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14"
            )
          ]
        end,
        source_endpoints_fun: fn _organization_id, _mission_id, _opts -> [] end,
        connection_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              adapter_key: :tcp_socket,
              connection_state: :connected,
              observed_at: ~U[2026-06-17 12:02:00Z]
            }
          ]
        end,
        link_rf_lock_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              transport_id: "transport-alpha",
              lock_state: :locked,
              observed_at: ~U[2026-06-17 12:02:30Z]
            }
          ]
        end,
        link_rf_frame_sync_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              transport_id: "transport-alpha",
              frame_sync_state: :synchronized,
              observed_at: ~U[2026-06-17 12:02:45Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{
             frames: [contact_frame, connection_frame, rf_lock_frame, frame_sync_frame],
             warnings: []
           } = result

    assert result.meta.supported_capability == :operational_state_history
    assert result.meta.returned_frame_count == 4

    assert contact_frame.shape == :events
    assert contact_frame.meta.supported_capability == :contacts_phase_history
    assert contact_frame.meta.returned_points == 2

    assert [
             %Field{name: "time", values: [~U[2026-06-17 12:00:00Z], ~U[2026-06-17 12:00:01Z]]},
             %Field{name: "observable_id", values: ["contacts.phase", "contacts.phase"]} | _rest
           ] = contact_frame.fields

    assert connection_frame.shape == :events
    assert connection_frame.meta.supported_capability == :connection_state_history
    assert connection_frame.meta.returned_points == 1

    assert [
             %Field{name: "time", values: [~U[2026-06-17 12:02:00Z]]},
             %Field{name: "observable_id", values: ["comms.transport.connection_state"]},
             %Field{name: "resource_id", values: ["transport-alpha"]} | _rest
           ] = connection_frame.fields

    assert rf_lock_frame.shape == :events
    assert rf_lock_frame.meta.supported_capability == :link_rf_lock_state_history
    assert rf_lock_frame.meta.returned_points == 1

    assert [
             %Field{name: "time", values: [~U[2026-06-17 12:02:30Z]]},
             %Field{name: "observable_id", values: ["link.rf_lock_state"]},
             %Field{name: "resource_id", values: ["transport-alpha"]} | _rest
           ] = rf_lock_frame.fields

    assert frame_sync_frame.shape == :events
    assert frame_sync_frame.meta.supported_capability == :link_rf_frame_sync_state_history
    assert frame_sync_frame.meta.returned_points == 1

    assert [
             %Field{name: "time", values: [~U[2026-06-17 12:02:45Z]]},
             %Field{name: "observable_id", values: ["link.frame_sync_state"]},
             %Field{name: "resource_id", values: ["transport-alpha"]} | _rest
           ] = frame_sync_frame.fields
  end

  test "preserves replay context in connection and RF state history reader options" do
    from_time = ~U[2026-06-17 12:00:00Z]
    to_time = ~U[2026-06-17 12:03:00Z]

    result =
      source_request()
      |> Map.put(:observables, [
        "comms.transport.connection_state",
        "link.rf_lock_state",
        "link.frame_sync_state"
      ])
      |> Map.put(:sampling, %{mode: :event_history, limit: 10})
      |> Map.put(:time_context, %{
        mode: :replay_run,
        from: from_time,
        to: to_time,
        replay_run_id: "replay-run-1"
      })
      |> Map.put(:data_context, %{
        realm: :replay,
        replay_run_id: "replay-run-1",
        source_contexts: %{
          operational_observables: %{
            data_source_id: "managed_operational_observables_replay",
            source_binding_id: "replay-operational-observables",
            dataset: "operational_observables_replay"
          }
        }
      })
      |> OperationalObservables.resolve(
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:replay_state_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            )
          ]
        end,
        source_endpoints_fun: fn organization_id, mission_id, opts ->
          send(self(), {:replay_state_source_endpoints, organization_id, mission_id, opts})
          []
        end,
        connection_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:replay_connection_snapshots, organization_id, mission_id, opts})

          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              adapter_key: :tcp_socket,
              connection_state: :connected,
              observed_at: ~U[2026-06-17 12:02:00Z]
            }
          ]
        end,
        link_rf_lock_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:replay_rf_lock_snapshots, organization_id, mission_id, opts})

          [
            %{
              transport_id: "transport-alpha",
              link_assignment_id: "link-alpha",
              lock_state: :locked,
              observed_at: ~U[2026-06-17 12:02:30Z]
            }
          ]
        end,
        link_rf_frame_sync_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:replay_frame_sync_snapshots, organization_id, mission_id, opts})

          [
            %{
              transport_id: "transport-alpha",
              link_assignment_id: "link-alpha",
              frame_sync_state: :synchronized,
              observed_at: ~U[2026-06-17 12:02:45Z]
            }
          ]
        end,
        source_binding: replay_source_binding()
      )

    assert %SourceResult{
             frames: [connection_frame, rf_lock_frame, frame_sync_frame],
             warnings: []
           } = result

    assert result.meta.supported_capability == :operational_state_history

    for frame <- [connection_frame, rf_lock_frame, frame_sync_frame] do
      assert frame.meta.realm == :replay
      assert frame.meta.data_source_id == "managed_operational_observables_replay"
      assert frame.meta.source_binding_id == "replay-operational-observables"
      assert frame.meta.dataset == "operational_observables_replay"
      assert frame.meta.replay_run_id == "replay-run-1"
    end

    assert connection_frame.meta.supported_capability == :connection_state_history
    assert rf_lock_frame.meta.supported_capability == :link_rf_lock_state_history
    assert frame_sync_frame.meta.supported_capability == :link_rf_frame_sync_state_history

    for message <- [
          :replay_state_transports,
          :replay_state_source_endpoints,
          :replay_connection_snapshots,
          :replay_rf_lock_snapshots,
          :replay_frame_sync_snapshots
        ] do
      assert_received {^message, "org-1", "mission-1", opts}
      assert_replay_operational_observable_opts(opts, from_time, to_time)
    end
  end

  test "resolves transport bit rate from configured transports and metric snapshots" do
    transports_fun = fn organization_id, mission_id, opts ->
      send(self(), {:bitrate_transports, organization_id, mission_id, opts})

      [
        transport("transport-alpha", "Lab TCP",
          source_endpoint_id: "endpoint-alpha",
          ground_station_id: "dss-14"
        ),
        transport("transport-beta", "Backup TCP", source_endpoint_id: "endpoint-beta")
      ]
    end

    transport_metric_snapshots_fun = fn organization_id, mission_id, opts ->
      send(self(), {:transport_metric_snapshots, organization_id, mission_id, opts})

      [
        %{
          transport_id: "transport-alpha",
          source_endpoint_id: "endpoint-alpha",
          adapter_key: :tcp_socket,
          downlink_bitrate: 12_500.5,
          observed_at: ~U[2026-06-17 12:04:00Z]
        }
      ]
    end

    result =
      source_request()
      |> Map.put(:observables, ["comms.transport.downlink_bitrate"])
      |> Map.put(:sampling, %{mode: :latest})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:04:02Z],
        transports_fun: transports_fun,
        transport_metric_snapshots_fun: transport_metric_snapshots_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{
             frames: [frame],
             warnings: [%ResolveWarning{code: :missing_snapshot, severity: :warning} = warning]
           } = result

    assert %Frame{source: :operational_observables, shape: :matrix, time_axis: nil} = frame
    assert result.meta.supported_capability == :transport_bitrate
    assert result.meta.degraded?
    assert warning.details.supported_capability == :transport_bitrate
    assert warning.details.frame_ids == ["ops-request-1:transport_bitrate"]
    assert warning.details.observable_ids == ["comms.transport.downlink_bitrate"]
    assert frame.meta.supported_capability == :transport_bitrate
    assert frame.meta.observable_id == "comms.transport.downlink_bitrate"
    assert frame.meta.unit == "bit/s"
    assert frame.meta.returned_points == 2
    assert frame.meta.warning_codes == [:missing_snapshot]

    assert Enum.map(frame.meta.links, &{&1.target, &1.target_id}) == [
             {:transport, "transport-alpha"},
             {:source_endpoint, "endpoint-alpha"},
             {:ground_station, "dss-14"},
             {:transport, "transport-beta"},
             {:source_endpoint, "endpoint-beta"}
           ]

    assert [
             %Field{
               name: "observable_id",
               values: [
                 "comms.transport.downlink_bitrate",
                 "comms.transport.downlink_bitrate"
               ]
             },
             %Field{name: "resource_id", values: ["transport-alpha", "transport-beta"]},
             %Field{name: "label", values: ["Lab TCP", "Backup TCP"]},
             %Field{name: "scope_kind", values: [:transport, :transport]},
             %Field{name: "transport_id", values: ["transport-alpha", "transport-beta"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha", "endpoint-beta"]},
             %Field{name: "ground_station_id", values: ["dss-14", nil]},
             %Field{name: "link_id", values: [nil, nil]},
             %Field{name: "adapter_key", values: [:tcp_socket, :tcp_socket]},
             %Field{name: "value", values: [12_500.5, nil]},
             %Field{name: "unit", values: ["bit/s", "bit/s"]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:04:00Z], nil]},
             %Field{name: "freshness_state", values: [:fresh, :missing]},
             %Field{name: "age_ms", values: [2_000, nil]}
           ] = frame.fields

    assert_received {:bitrate_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:transport_metric_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "resolves uplink transport bit rate as the transport bitrate family" do
    result =
      source_request()
      |> Map.put(:observables, ["comms.transport.uplink_bitrate"])
      |> Map.put(:sampling, %{mode: :latest})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:04:02Z],
        transports_fun: fn _organization_id, _mission_id, _opts ->
          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            )
          ]
        end,
        transport_metric_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              transport_id: "transport-alpha",
              link_assignment_id: "link-alpha",
              uplink_bitrate: 4_800.0,
              observed_at: ~U[2026-06-17 12:04:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert result.meta.supported_capability == :transport_bitrate
    assert frame.meta.supported_capability == :transport_bitrate
    assert frame.meta.observable_id == "comms.transport.uplink_bitrate"
    assert frame.meta.observable_ids == ["comms.transport.uplink_bitrate"]

    assert [
             %Field{name: "observable_id", values: ["comms.transport.uplink_bitrate"]},
             %Field{name: "resource_id", values: ["transport-alpha"]},
             %Field{name: "label", values: ["Lab TCP"]},
             %Field{name: "scope_kind", values: [:transport]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "adapter_key", values: [:tcp_socket]},
             %Field{name: "value", values: [4_800.0]},
             %Field{name: "unit", values: ["bit/s"]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:04:00Z]]},
             %Field{name: "freshness_state", values: [:fresh]},
             %Field{name: "age_ms", values: [2_000]}
           ] = frame.fields
  end

  test "filters transport bit rate rows to link scope" do
    result =
      source_request()
      |> Map.put(:observables, ["comms.transport.downlink_bitrate"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{primary: %{kind: :link, mode: :one, ids: ["link-alpha"]}})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:04:02Z],
        transports_fun: fn _organization_id, _mission_id, _opts ->
          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            ),
            transport("transport-beta", "Backup TCP",
              source_endpoint_id: "endpoint-beta",
              link_assignment_id: "link-beta"
            )
          ]
        end,
        transport_metric_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              transport_id: "transport-alpha",
              link_assignment_id: "link-alpha",
              downlink_bitrate: 12_500.5,
              observed_at: ~U[2026-06-17 12:04:00Z]
            },
            %{
              transport_id: "transport-beta",
              link_assignment_id: "link-beta",
              downlink_bitrate: 9_000.0,
              observed_at: ~U[2026-06-17 12:04:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{
             frames: [frame],
             warnings: []
           } = result

    assert [
             %Field{name: "observable_id", values: ["comms.transport.downlink_bitrate"]},
             %Field{name: "resource_id", values: ["transport-alpha"]},
             %Field{name: "label", values: ["Lab TCP"]},
             %Field{name: "scope_kind", values: [:transport]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "adapter_key", values: [:tcp_socket]},
             %Field{name: "value", values: [12_500.5]} | _rest
           ] = frame.fields
  end

  test "resolves transport bit rate history into one wide frame per transport" do
    result =
      source_request()
      |> Map.put(:observables, ["comms.transport.downlink_bitrate"])
      |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
      |> Map.put(:time_context, %{
        from: ~U[2026-06-17 12:01:00Z],
        to: ~U[2026-06-17 12:03:00Z]
      })
      |> OperationalObservables.resolve(
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:bitrate_history_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14"
            ),
            transport("transport-beta", "Backup TCP", source_endpoint_id: "endpoint-beta")
          ]
        end,
        transport_metric_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:bitrate_history_snapshots, organization_id, mission_id, opts})

          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              adapter_key: :tcp_socket,
              downlink_bitrate: 12_500.5,
              observed_at: ~U[2026-06-17 12:01:00Z]
            },
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              adapter_key: :tcp_socket,
              downlink_bitrate: 13_000.0,
              observed_at: ~U[2026-06-17 12:02:00Z]
            },
            %{
              transport_id: "transport-beta",
              source_endpoint_id: "endpoint-beta",
              adapter_key: :tcp_socket,
              downlink_bitrate: 9_000.0,
              observed_at: ~U[2026-06-17 12:02:30Z]
            },
            %{
              transport_id: "transport-alpha",
              downlink_bitrate: 14_000.0,
              observed_at: ~U[2026-06-17 12:05:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [alpha_frame, beta_frame], warnings: []} = result
    assert result.meta.supported_capability == :transport_bitrate_history
    assert result.meta.returned_frame_count == 2

    assert alpha_frame.meta.supported_capability == :transport_bitrate_history
    assert alpha_frame.meta.product_family == :transport_bitrate
    assert alpha_frame.meta.observable_id == "comms.transport.downlink_bitrate"
    assert alpha_frame.meta.resource_id == "transport-alpha"
    assert alpha_frame.meta.unit == "bit/s"
    assert alpha_frame.meta.returned_points == 2

    assert [
             %Field{
               name: "time",
               values: [~U[2026-06-17 12:01:00Z], ~U[2026-06-17 12:02:00Z]]
             },
             %Field{
               name: "comms.transport.downlink_bitrate",
               values: [12_500.5, 13_000.0],
               metadata: %{label: "Lab TCP", resource_id: "transport-alpha", unit: "bit/s"}
             }
           ] = alpha_frame.fields

    assert beta_frame.meta.resource_id == "transport-beta"
    assert beta_frame.meta.returned_points == 1

    assert [
             %Field{name: "time", values: [~U[2026-06-17 12:02:30Z]]},
             %Field{name: "comms.transport.downlink_bitrate", values: [9_000.0]}
           ] = beta_frame.fields

    assert_received {:bitrate_history_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:bitrate_history_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "keeps downlink and uplink transport bit rate history in separate series" do
    result =
      source_request()
      |> Map.put(:observables, [
        "comms.transport.downlink_bitrate",
        "comms.transport.uplink_bitrate"
      ])
      |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
      |> Map.put(:time_context, %{
        from: ~U[2026-06-17 12:01:00Z],
        to: ~U[2026-06-17 12:03:00Z]
      })
      |> OperationalObservables.resolve(
        transports_fun: fn _organization_id, _mission_id, _opts ->
          [transport("transport-alpha", "Lab TCP", source_endpoint_id: "endpoint-alpha")]
        end,
        transport_metric_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              downlink_bitrate: 12_500.5,
              uplink_bitrate: 4_800.0,
              observed_at: ~U[2026-06-17 12:02:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [downlink_frame, uplink_frame], warnings: []} = result
    assert result.meta.supported_capability == :transport_bitrate_history
    assert result.meta.returned_frame_count == 2

    assert downlink_frame.meta.observable_id == "comms.transport.downlink_bitrate"
    assert downlink_frame.meta.product_family == :transport_bitrate

    assert [
             %Field{name: "time", values: [~U[2026-06-17 12:02:00Z]]},
             %Field{name: "comms.transport.downlink_bitrate", values: [12_500.5]}
           ] = downlink_frame.fields

    assert uplink_frame.meta.observable_id == "comms.transport.uplink_bitrate"
    assert uplink_frame.meta.product_family == :transport_bitrate

    assert [
             %Field{name: "time", values: [~U[2026-06-17 12:02:00Z]]},
             %Field{name: "comms.transport.uplink_bitrate", values: [4_800.0]}
           ] = uplink_frame.fields
  end

  test "resolves empty transport bitrate history as a chartable zero-point frame" do
    result =
      source_request()
      |> Map.put(:observables, ["comms.transport.downlink_bitrate"])
      |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
      |> Map.put(:time_context, %{
        from: ~U[2026-06-17 12:01:00Z],
        to: ~U[2026-06-17 12:03:00Z]
      })
      |> Map.put(:scope_context, %{
        primary: %{kind: :transport, mode: :one, ids: ["transport-alpha"]}
      })
      |> OperationalObservables.resolve(
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:empty_bitrate_history_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            ),
            transport("transport-beta", "Backup TCP", source_endpoint_id: "endpoint-beta")
          ]
        end,
        transport_metric_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:empty_bitrate_history_snapshots, organization_id, mission_id, opts})
          []
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :wide, time_axis: :occurred_at} = frame
    refute result.meta.degraded?
    assert result.meta.supported_capability == :transport_bitrate_history
    assert frame.meta.supported_capability == :transport_bitrate_history
    assert frame.meta.product_family == :transport_bitrate
    assert frame.meta.observable_id == "comms.transport.downlink_bitrate"
    assert frame.meta.resource_id == "transport-alpha"
    assert frame.meta.scope_kind == :transport
    assert frame.meta.transport_id == "transport-alpha"
    assert frame.meta.source_endpoint_id == "endpoint-alpha"
    assert frame.meta.ground_station_id == "dss-14"
    assert frame.meta.link_id == "link-alpha"
    assert frame.meta.unit == "bit/s"
    assert frame.meta.returned_points == 0
    assert frame.meta.warning_codes == []

    assert Enum.map(frame.meta.links, &{&1.target, &1.target_id}) == [
             {:transport, "transport-alpha"},
             {:source_endpoint, "endpoint-alpha"},
             {:ground_station, "dss-14"},
             {:link, "link-alpha"}
           ]

    assert [
             %Field{name: "time", values: []},
             %Field{
               name: "comms.transport.downlink_bitrate",
               values: [],
               metadata: %{
                 observable_id: "comms.transport.downlink_bitrate",
                 label: "Lab TCP",
                 unit: "bit/s",
                 resource_id: "transport-alpha",
                 scope_kind: :transport,
                 transport_id: "transport-alpha",
                 source_endpoint_id: "endpoint-alpha",
                 ground_station_id: "dss-14",
                 link_id: "link-alpha",
                 adapter_key: :tcp_socket
               }
             }
           ] = frame.fields

    assert_received {:empty_bitrate_history_transports, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight

    assert_received {:empty_bitrate_history_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "resolves command queue depth latest operational observable into a matrix frame" do
    command_queue_entries_fun = fn organization_id, mission_id, opts ->
      send(self(), {:command_queue_entries, organization_id, mission_id, opts})

      [
        command_queue_entry("queue-1", "endpoint-alpha", :pending),
        command_queue_entry("queue-2", "endpoint-alpha", :release_pending),
        command_queue_entry("queue-3", "endpoint-beta", :pending)
      ]
    end

    result =
      source_request()
      |> Map.put(:observables, ["commanding.queue_depth"])
      |> Map.put(:sampling, %{mode: :latest})
      |> OperationalObservables.resolve(
        command_queue_entries_fun: command_queue_entries_fun,
        freshness_now: ~U[2026-06-17 12:05:02Z],
        read_time: ~U[2026-06-17 12:05:00Z],
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :matrix, time_axis: nil} = frame
    assert result.meta.supported_capability == :command_queue_depth
    assert frame.meta.supported_capability == :command_queue_depth
    assert frame.meta.product_family == :commanding
    assert frame.meta.observable_id == "commanding.queue_depth"
    assert frame.meta.unit == "commands"
    assert frame.meta.returned_points == 1
    assert frame.meta.command_queue_entry_ids == ["queue-1", "queue-3"]

    assert evidence_identities(frame) == [
             {:command_queue_entry, "queue-1"},
             {:command_queue_entry, "queue-3"}
           ]

    assert [
             %Field{name: "observable_id", values: ["commanding.queue_depth"]},
             %Field{name: "resource_id", values: ["mission-1"]},
             %Field{name: "label", values: ["Pending commands"]},
             %Field{name: "scope_kind", values: [:mission]},
             %Field{name: "source_endpoint_id", values: [nil]},
             %Field{name: "value", values: [2]},
             %Field{name: "unit", values: ["commands"]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:05:00Z]]},
             %Field{name: "freshness_state", values: [:fresh]},
             %Field{name: "age_ms", values: [2_000]}
           ] = frame.fields

    assert_received {:command_queue_entries, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "preserves replay command queue row identity and evidence refs" do
    command_queue_entries_fun = fn organization_id, mission_id, opts ->
      send(self(), {:replay_command_queue_entries, organization_id, mission_id, opts})

      [
        command_queue_entry("replay-queue-1", "endpoint-alpha", :pending),
        command_queue_entry("replay-queue-2", "endpoint-alpha", :released)
      ]
    end

    result =
      source_request()
      |> Map.put(:observables, ["commanding.queue_depth"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:time_context, %{
        mode: :replay_run,
        from: ~U[2026-06-17 12:00:00Z],
        to: ~U[2026-06-17 12:10:00Z],
        replay_run_id: "replay-run-1"
      })
      |> Map.put(:data_context, %{
        realm: :replay,
        replay_run_id: "replay-run-1",
        source_contexts: %{
          operational_observables: %{
            data_source_id: "managed_operational_observables_replay",
            source_binding_id: "replay-operational-observables",
            dataset: "operational_observables_replay"
          }
        }
      })
      |> OperationalObservables.resolve(
        command_queue_entries_fun: command_queue_entries_fun,
        freshness_now: ~U[2026-06-17 12:05:02Z],
        read_time: ~U[2026-06-17 12:05:00Z],
        source_binding: replay_source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert frame.meta.realm == :replay
    assert frame.meta.data_source_id == "managed_operational_observables_replay"
    assert frame.meta.source_binding_id == "replay-operational-observables"
    assert frame.meta.dataset == "operational_observables_replay"
    assert frame.meta.replay_run_id == "replay-run-1"
    assert frame.meta.command_queue_entry_ids == ["replay-queue-1"]
    assert evidence_identities(frame) == [{:command_queue_entry, "replay-queue-1"}]

    assert [%{kind: :command_queue_entry, id: "replay-queue-1"} = evidence_ref] =
             frame.meta.evidence_refs

    assert evidence_ref.source == :operational_observables
    assert evidence_ref.confidence == :direct
    assert evidence_ref.observed_at == ~U[2026-06-17 12:00:00Z]

    assert_received {:replay_command_queue_entries, "org-1", "mission-1", opts}
    assert opts[:realm] == :replay
    assert opts[:data_source_id] == "managed_operational_observables_replay"
    assert opts[:source_binding_id] == "replay-operational-observables"
    assert opts[:dataset] == "operational_observables_replay"
    assert opts[:replay_run_id] == "replay-run-1"
  end

  test "resolves an empty command queue as a fresh zero aggregate" do
    result =
      source_request()
      |> Map.put(:observables, ["commanding.queue_depth"])
      |> Map.put(:sampling, %{mode: :latest})
      |> OperationalObservables.resolve(
        command_queue_entries_fun: fn organization_id, mission_id, opts ->
          send(self(), {:empty_command_queue_entries, organization_id, mission_id, opts})
          []
        end,
        freshness_now: ~U[2026-06-17 12:05:02Z],
        read_time: ~U[2026-06-17 12:05:00Z],
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    refute result.meta.degraded?
    assert frame.meta.supported_capability == :command_queue_depth
    assert frame.meta.command_queue_entry_ids == []
    assert frame.meta.evidence_refs == []
    assert frame.meta.warning_codes == []
    assert frame.meta.freshness_checked_at == ~U[2026-06-17 12:05:02Z]

    assert [
             %Field{name: "observable_id", values: ["commanding.queue_depth"]},
             %Field{name: "resource_id", values: ["mission-1"]},
             %Field{name: "label", values: ["Pending commands"]},
             %Field{name: "scope_kind", values: [:mission]},
             %Field{name: "source_endpoint_id", values: [nil]},
             %Field{name: "value", values: [0]},
             %Field{name: "unit", values: ["commands"]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:05:00Z]]},
             %Field{name: "freshness_state", values: [:fresh]},
             %Field{name: "age_ms", values: [2_000]}
           ] = frame.fields

    assert_received {:empty_command_queue_entries, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "marks non-ingress latest operational rows stale when freshness policy expires" do
    result =
      source_request()
      |> Map.put(:observables, ["commanding.queue_depth"])
      |> Map.put(:sampling, %{mode: :latest})
      |> OperationalObservables.resolve(
        command_queue_entries_fun: fn _organization_id, _mission_id, _opts -> [] end,
        freshness_now: ~U[2026-06-17 12:05:02Z],
        freshness_policy: %{stale_after_ms: 1_000},
        read_time: ~U[2026-06-17 12:05:00Z],
        source_binding: source_binding()
      )

    assert %SourceResult{
             frames: [frame],
             warnings: [%ResolveWarning{code: :stale_data, severity: :warning} = warning]
           } = result

    assert result.meta.degraded?
    assert warning.details.supported_capability == :command_queue_depth
    assert warning.details.frame_ids == ["ops-request-1:command_queue_depth"]
    assert warning.details.observable_ids == ["commanding.queue_depth"]
    assert frame.meta.warning_codes == [:stale_data]
    assert frame.meta.freshness_policy == %{stale_after_ms: 1_000}
    assert frame.meta.freshness_checked_at == ~U[2026-06-17 12:05:02Z]

    assert [
             %Field{name: "observable_id", values: ["commanding.queue_depth"]},
             %Field{name: "resource_id", values: ["mission-1"]},
             %Field{name: "label", values: ["Pending commands"]},
             %Field{name: "scope_kind", values: [:mission]},
             %Field{name: "source_endpoint_id", values: [nil]},
             %Field{name: "value", values: [0]},
             %Field{name: "unit", values: ["commands"]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:05:00Z]]},
             %Field{name: "freshness_state", values: [:stale]},
             %Field{name: "age_ms", values: [2_000]}
           ] = frame.fields
  end

  test "resolves ingress processing latency latest operational observable into a matrix frame" do
    runtime_metric_snapshots_fun = fn organization_id, mission_id, opts ->
      send(self(), {:runtime_metric_snapshots, organization_id, mission_id, opts})

      [
        %{
          observable_id: "ingress.processing_latency_ms",
          mission_id: "mission-1",
          source_endpoint_id: "endpoint-alpha",
          spacecraft_id: "spacecraft-alpha",
          transport_id: "transport-alpha",
          ground_station_id: "dss-14",
          link_id: "link-alpha",
          adapter_key: :tcp_socket,
          value: 4.5,
          unit: "ms",
          observed_at: ~U[2026-06-17 12:06:00Z],
          error?: false
        },
        %{
          observable_id: "ingress.processing_latency_ms",
          mission_id: "mission-2",
          source_endpoint_id: "endpoint-beta",
          value: 9.0,
          observed_at: ~U[2026-06-17 12:07:00Z]
        }
      ]
    end

    result =
      source_request()
      |> Map.put(:observables, ["ingress.processing_latency_ms"])
      |> Map.put(:sampling, %{mode: :latest})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:06:02Z],
        freshness_policy: %{stale_after_ms: 5_000},
        runtime_metric_snapshots_fun: runtime_metric_snapshots_fun,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert %Frame{source: :operational_observables, shape: :matrix, time_axis: nil} = frame
    assert result.meta.supported_capability == :ingress_processing_latency
    assert frame.meta.supported_capability == :ingress_processing_latency
    assert frame.meta.product_family == :runtime_ingress
    assert frame.meta.observable_id == "ingress.processing_latency_ms"
    assert frame.meta.unit == "ms"
    assert frame.meta.returned_points == 1
    assert frame.meta.freshness_policy == %{stale_after_ms: 5_000}
    assert frame.meta.freshness_checked_at == ~U[2026-06-17 12:06:02Z]
    assert frame.meta.warning_codes == []

    assert [
             %DataLink{target: :transport, target_id: "transport-alpha"},
             %DataLink{target: :source_endpoint, target_id: "endpoint-alpha"},
             %DataLink{target: :ground_station, target_id: "dss-14"},
             %DataLink{target: :link, target_id: "link-alpha"}
           ] = frame.meta.links

    assert [
             %Field{name: "observable_id", values: ["ingress.processing_latency_ms"]},
             %Field{name: "resource_id", values: ["endpoint-alpha"]},
             %Field{name: "label", values: ["Ingress latency / endpoint-alpha"]},
             %Field{name: "scope_kind", values: [:source_endpoint]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: ["link-alpha"]},
             %Field{name: "contact_id", values: [nil]},
             %Field{name: "adapter_key", values: [:tcp_socket]},
             %Field{name: "spacecraft_id", values: ["spacecraft-alpha"]},
             %Field{name: "value", values: [4.5]},
             %Field{name: "unit", values: ["ms"]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:06:00Z]]},
             %Field{name: "freshness_state", values: [:fresh]},
             %Field{name: "age_ms", values: [2_000]},
             %Field{name: "error", values: [false]}
           ] = frame.fields

    assert_received {:runtime_metric_snapshots, "org-1", "mission-1", opts}
    assert opts[:dataset] == "operational_observables"
  end

  test "filters ingress processing latency latest rows to multi-spacecraft scope" do
    result =
      source_request()
      |> Map.put(:observables, ["ingress.processing_latency_ms"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{
        primary: %{kind: :spacecraft, mode: :many, ids: ["spacecraft-alpha", "spacecraft-beta"]}
      })
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:06:02Z],
        freshness_policy: %{stale_after_ms: 5_000},
        runtime_metric_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission-1",
              source_endpoint_id: "endpoint-alpha",
              spacecraft_id: "spacecraft-alpha",
              value: 4.5,
              observed_at: ~U[2026-06-17 12:06:00Z]
            },
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission-1",
              source_endpoint_id: "endpoint-beta",
              spacecraft_id: "spacecraft-beta",
              value: 5.5,
              observed_at: ~U[2026-06-17 12:06:01Z]
            },
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission-1",
              source_endpoint_id: "endpoint-gamma",
              spacecraft_id: "spacecraft-gamma",
              value: 6.5,
              observed_at: ~U[2026-06-17 12:06:01Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert frame.meta.returned_points == 2

    assert [
             %DataLink{target: :source_endpoint, target_id: "endpoint-alpha"},
             %DataLink{target: :source_endpoint, target_id: "endpoint-beta"}
           ] = Enum.filter(frame.meta.links, &(&1.target == :source_endpoint))

    assert [
             %Field{
               name: "observable_id",
               values: ["ingress.processing_latency_ms", "ingress.processing_latency_ms"]
             },
             %Field{name: "resource_id", values: ["endpoint-alpha", "endpoint-beta"]},
             %Field{
               name: "label",
               values: ["Ingress latency / endpoint-alpha", "Ingress latency / endpoint-beta"]
             },
             %Field{name: "scope_kind", values: [:source_endpoint, :source_endpoint]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha", "endpoint-beta"]},
             %Field{name: "transport_id", values: [nil, nil]},
             %Field{name: "ground_station_id", values: [nil, nil]},
             %Field{name: "link_id", values: [nil, nil]},
             %Field{name: "contact_id", values: [nil, nil]},
             %Field{name: "adapter_key", values: [nil, nil]},
             %Field{name: "spacecraft_id", values: ["spacecraft-alpha", "spacecraft-beta"]},
             %Field{name: "value", values: [4.5, 5.5]} | _rest
           ] = frame.fields
  end

  test "filters ingress processing latency latest rows to contact scope" do
    result =
      source_request()
      |> Map.put(:observables, ["ingress.processing_latency_ms"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{
        primary: %{kind: :contact, mode: :one, ids: ["contact-alpha"]}
      })
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:06:02Z],
        freshness_policy: %{stale_after_ms: 5_000},
        runtime_metric_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission-1",
              source_endpoint_id: "endpoint-alpha",
              contact_id: "contact-alpha",
              value: 4.5,
              observed_at: ~U[2026-06-17 12:06:00Z]
            },
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission-1",
              source_endpoint_id: "endpoint-beta",
              contact_id: "contact-beta",
              value: 5.5,
              observed_at: ~U[2026-06-17 12:06:01Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert frame.meta.returned_points == 1

    assert [
             %DataLink{target: :source_endpoint, target_id: "endpoint-alpha"},
             %DataLink{target: :contact, target_id: "contact-alpha"}
           ] = Enum.filter(frame.meta.links, &(&1.target in [:source_endpoint, :contact]))

    assert [
             %Field{name: "observable_id", values: ["ingress.processing_latency_ms"]},
             %Field{name: "resource_id", values: ["endpoint-alpha"]},
             %Field{name: "label", values: ["Ingress latency / endpoint-alpha"]},
             %Field{name: "scope_kind", values: [:source_endpoint]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "transport_id", values: [nil]},
             %Field{name: "ground_station_id", values: [nil]},
             %Field{name: "link_id", values: [nil]},
             %Field{name: "contact_id", values: ["contact-alpha"]},
             %Field{name: "adapter_key", values: [nil]},
             %Field{name: "spacecraft_id", values: [nil]},
             %Field{name: "value", values: [4.5]} | _rest
           ] = frame.fields
  end

  test "marks ingress processing latency stale when the runtime sample exceeds freshness policy" do
    result =
      source_request()
      |> Map.put(:observables, ["ingress.processing_latency_ms"])
      |> Map.put(:sampling, %{mode: :latest})
      |> OperationalObservables.resolve(
        freshness_now: ~U[2026-06-17 12:06:02Z],
        freshness_policy: %{stale_after_ms: 1_000},
        runtime_metric_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission-1",
              source_endpoint_id: "endpoint-alpha",
              value: 4.5,
              observed_at: ~U[2026-06-17 12:06:00Z]
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{
             frames: [frame],
             warnings: [%ResolveWarning{code: :stale_data, severity: :warning} = warning]
           } = result

    assert result.meta.degraded?
    assert warning.details.supported_capability == :ingress_processing_latency
    assert warning.details.frame_ids == ["ops-request-1:ingress_processing_latency"]
    assert warning.details.observable_ids == ["ingress.processing_latency_ms"]
    assert frame.meta.warning_codes == [:stale_data]

    assert [
             %Field{name: "observable_id", values: ["ingress.processing_latency_ms"]},
             %Field{name: "resource_id", values: ["endpoint-alpha"]},
             %Field{name: "label", values: ["Ingress latency / endpoint-alpha"]},
             %Field{name: "scope_kind", values: [:source_endpoint]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "transport_id", values: [nil]},
             %Field{name: "ground_station_id", values: [nil]},
             %Field{name: "link_id", values: [nil]},
             %Field{name: "contact_id", values: [nil]},
             %Field{name: "adapter_key", values: [nil]},
             %Field{name: "spacecraft_id", values: [nil]},
             %Field{name: "value", values: [4.5]},
             %Field{name: "unit", values: ["ms"]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:06:00Z]]},
             %Field{name: "freshness_state", values: [:stale]},
             %Field{name: "age_ms", values: [2_000]},
             %Field{name: "error", values: [false]}
           ] = frame.fields
  end

  test "overlays live runtime-health ingress latency over an older durable sample" do
    parent = self()

    durable_snapshots_fun = fn organization_id, mission_id, opts ->
      send(parent, {:durable_ingress_latency, organization_id, mission_id, opts})

      [
        %{
          observable_id: "ingress.processing_latency_ms",
          mission_id: "mission-1",
          source_endpoint_id: "endpoint-alpha",
          spacecraft_id: "spacecraft-alpha",
          value: 12.0,
          unit: "ms",
          observed_at: ~U[2026-06-17 12:00:00Z]
        }
      ]
    end

    runtime_snapshots_fun = fn organization_id, mission_id, opts ->
      send(parent, {:runtime_ingress_latency, organization_id, mission_id, opts})

      [
        %{
          observable_id: "ingress.processing_latency_ms",
          mission_id: "mission-1",
          source_endpoint_id: "endpoint-alpha",
          spacecraft_id: "spacecraft-alpha",
          value: 4.5,
          unit: "ms",
          observed_at: ~U[2026-06-17 12:06:00Z]
        }
      ]
    end

    result =
      source_request()
      |> Map.put(:observables, ["ingress.processing_latency_ms"])
      |> Map.put(:sampling, %{mode: :latest})
      |> OperationalObservables.resolve(
        durable_ingress_processing_latency_snapshots_fun: durable_snapshots_fun,
        runtime_health_ingress_processing_latency_snapshots_fun: runtime_snapshots_fun,
        freshness_now: ~U[2026-06-17 12:06:02Z],
        freshness_policy: %{stale_after_ms: 5_000},
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert frame.meta.returned_points == 1

    assert [
             %Field{name: "observable_id", values: ["ingress.processing_latency_ms"]},
             %Field{name: "resource_id", values: ["endpoint-alpha"]},
             %Field{name: "label", values: ["Ingress latency / endpoint-alpha"]},
             %Field{name: "scope_kind", values: [:source_endpoint]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "transport_id", values: [nil]},
             %Field{name: "ground_station_id", values: [nil]},
             %Field{name: "link_id", values: [nil]},
             %Field{name: "contact_id", values: [nil]},
             %Field{name: "adapter_key", values: [nil]},
             %Field{name: "spacecraft_id", values: ["spacecraft-alpha"]},
             %Field{name: "value", values: [4.5]},
             %Field{name: "unit", values: ["ms"]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:06:00Z]]},
             %Field{name: "freshness_state", values: [:fresh]},
             %Field{name: "age_ms", values: [2_000]},
             %Field{name: "error", values: [false]}
           ] = frame.fields

    assert_received {:durable_ingress_latency, "org-1", "mission-1", durable_opts}
    assert durable_opts[:realm] == :flight
    assert durable_opts[:dataset] == "operational_observables"

    assert_received {:runtime_ingress_latency, "org-1", "mission-1", runtime_opts}
    assert runtime_opts[:realm] == :flight
    assert runtime_opts[:dataset] == "operational_observables"
  end

  test "keeps newer durable ingress latency when runtime-health sample is older" do
    parent = self()

    durable_snapshots_fun = fn organization_id, mission_id, opts ->
      send(parent, {:durable_ingress_latency, organization_id, mission_id, opts})

      [
        %{
          observable_id: "ingress.processing_latency_ms",
          mission_id: "mission-1",
          source_endpoint_id: "endpoint-alpha",
          spacecraft_id: "spacecraft-alpha",
          value: 8.0,
          unit: "ms",
          observed_at: ~U[2026-06-17 12:06:00Z]
        }
      ]
    end

    runtime_snapshots_fun = fn organization_id, mission_id, opts ->
      send(parent, {:runtime_ingress_latency, organization_id, mission_id, opts})

      [
        %{
          observable_id: "ingress.processing_latency_ms",
          mission_id: "mission-1",
          source_endpoint_id: "endpoint-alpha",
          spacecraft_id: "spacecraft-alpha",
          value: 99.0,
          unit: "ms",
          observed_at: ~U[2026-06-17 12:00:00Z]
        }
      ]
    end

    result =
      source_request()
      |> Map.put(:observables, ["ingress.processing_latency_ms"])
      |> Map.put(:sampling, %{mode: :latest})
      |> OperationalObservables.resolve(
        durable_ingress_processing_latency_snapshots_fun: durable_snapshots_fun,
        runtime_health_ingress_processing_latency_snapshots_fun: runtime_snapshots_fun,
        freshness_now: ~U[2026-06-17 12:06:02Z],
        freshness_policy: %{stale_after_ms: 5_000},
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert frame.meta.returned_points == 1
    assert frame.meta.warning_codes == []

    assert [
             %Field{name: "observable_id", values: ["ingress.processing_latency_ms"]},
             %Field{name: "resource_id", values: ["endpoint-alpha"]},
             %Field{name: "label", values: ["Ingress latency / endpoint-alpha"]},
             %Field{name: "scope_kind", values: [:source_endpoint]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "transport_id", values: [nil]},
             %Field{name: "ground_station_id", values: [nil]},
             %Field{name: "link_id", values: [nil]},
             %Field{name: "contact_id", values: [nil]},
             %Field{name: "adapter_key", values: [nil]},
             %Field{name: "spacecraft_id", values: ["spacecraft-alpha"]},
             %Field{name: "value", values: [8.0]},
             %Field{name: "unit", values: ["ms"]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:06:00Z]]},
             %Field{name: "freshness_state", values: [:fresh]},
             %Field{name: "age_ms", values: [2_000]},
             %Field{name: "error", values: [false]}
           ] = frame.fields

    assert_received {:durable_ingress_latency, "org-1", "mission-1", durable_opts}
    assert durable_opts[:realm] == :flight
    assert durable_opts[:dataset] == "operational_observables"

    assert_received {:runtime_ingress_latency, "org-1", "mission-1", runtime_opts}
    assert runtime_opts[:realm] == :flight
    assert runtime_opts[:dataset] == "operational_observables"
  end

  test "returns no ingress latency rows when durable and runtime-health samples are absent" do
    parent = self()

    empty_durable_snapshots_fun = fn organization_id, mission_id, opts ->
      send(parent, {:durable_ingress_latency, organization_id, mission_id, opts})
      []
    end

    empty_runtime_snapshots_fun = fn organization_id, mission_id, opts ->
      send(parent, {:runtime_ingress_latency, organization_id, mission_id, opts})
      []
    end

    result =
      source_request()
      |> Map.put(:observables, ["ingress.processing_latency_ms"])
      |> Map.put(:sampling, %{mode: :latest})
      |> OperationalObservables.resolve(
        durable_ingress_processing_latency_snapshots_fun: empty_durable_snapshots_fun,
        runtime_health_ingress_processing_latency_snapshots_fun: empty_runtime_snapshots_fun,
        freshness_now: ~U[2026-06-17 12:06:02Z],
        freshness_policy: %{stale_after_ms: 5_000},
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    refute result.meta.degraded?
    assert frame.meta.returned_points == 0
    assert frame.meta.warning_codes == []

    assert [
             %Field{name: "observable_id", values: []},
             %Field{name: "resource_id", values: []},
             %Field{name: "label", values: []},
             %Field{name: "scope_kind", values: []},
             %Field{name: "source_endpoint_id", values: []},
             %Field{name: "transport_id", values: []},
             %Field{name: "ground_station_id", values: []},
             %Field{name: "link_id", values: []},
             %Field{name: "contact_id", values: []},
             %Field{name: "adapter_key", values: []},
             %Field{name: "spacecraft_id", values: []},
             %Field{name: "value", values: []},
             %Field{name: "unit", values: []},
             %Field{name: "observed_at", values: []},
             %Field{name: "freshness_state", values: []},
             %Field{name: "age_ms", values: []},
             %Field{name: "error", values: []}
           ] = frame.fields

    assert_received {:durable_ingress_latency, "org-1", "mission-1", durable_opts}
    assert durable_opts[:realm] == :flight
    assert durable_opts[:dataset] == "operational_observables"

    assert_received {:runtime_ingress_latency, "org-1", "mission-1", runtime_opts}
    assert runtime_opts[:realm] == :flight
    assert runtime_opts[:dataset] == "operational_observables"
  end

  test "does not overlay process-local runtime-health ingress latency on replay reads" do
    parent = self()

    durable_snapshots_fun = fn organization_id, mission_id, opts ->
      send(parent, {:durable_ingress_latency, organization_id, mission_id, opts})

      [
        %{
          observable_id: "ingress.processing_latency_ms",
          mission_id: "mission-1",
          source_endpoint_id: "endpoint-alpha",
          spacecraft_id: "spacecraft-alpha",
          value: 8.0,
          unit: "ms",
          observed_at: ~U[2026-06-17 12:06:00Z],
          replay_run_id: "replay-run-1"
        }
      ]
    end

    runtime_snapshots_fun = fn organization_id, mission_id, opts ->
      send(parent, {:runtime_ingress_latency, organization_id, mission_id, opts})
      []
    end

    result =
      source_request()
      |> Map.put(:observables, ["ingress.processing_latency_ms"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:time_context, %{mode: :replay_run, replay_run_id: "replay-run-1"})
      |> Map.put(:data_context, %{realm: :replay, replay_run_id: "replay-run-1"})
      |> OperationalObservables.resolve(
        durable_ingress_processing_latency_snapshots_fun: durable_snapshots_fun,
        runtime_health_ingress_processing_latency_snapshots_fun: runtime_snapshots_fun,
        freshness_now: ~U[2026-06-17 12:06:02Z],
        freshness_policy: %{stale_after_ms: 5_000},
        source_binding: replay_source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert frame.meta.realm == :replay
    assert frame.meta.replay_run_id == "replay-run-1"
    assert frame.meta.returned_points == 1

    assert [
             %Field{name: "observable_id", values: ["ingress.processing_latency_ms"]},
             %Field{name: "resource_id", values: ["endpoint-alpha"]},
             %Field{name: "label", values: ["Ingress latency / endpoint-alpha"]},
             %Field{name: "scope_kind", values: [:source_endpoint]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "transport_id", values: [nil]},
             %Field{name: "ground_station_id", values: [nil]},
             %Field{name: "link_id", values: [nil]},
             %Field{name: "contact_id", values: [nil]},
             %Field{name: "adapter_key", values: [nil]},
             %Field{name: "spacecraft_id", values: ["spacecraft-alpha"]},
             %Field{name: "value", values: [8.0]} | _rest
           ] = frame.fields

    assert_received {:durable_ingress_latency, "org-1", "mission-1", durable_opts}
    assert durable_opts[:realm] == :replay
    assert durable_opts[:dataset] == "operational_observables_replay"
    assert durable_opts[:replay_run_id] == "replay-run-1"

    refute_received {:runtime_ingress_latency, _, _, _}
  end

  test "resolves replay-scoped ingress processing latency history into a wide frame" do
    result =
      source_request()
      |> Map.put(:observables, ["ingress.processing_latency_ms"])
      |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
      |> Map.put(:scope_context, %{
        primary: %{kind: :source_endpoint, mode: :one, ids: ["endpoint-alpha"]}
      })
      |> Map.put(:time_context, %{
        mode: :replay_run,
        replay_run_id: "replay-run-1",
        from: ~U[2026-06-17 12:00:00Z],
        to: ~U[2026-06-17 12:03:00Z]
      })
      |> Map.put(:data_context, %{realm: :replay, replay_run_id: "replay-run-1"})
      |> OperationalObservables.resolve(
        ingress_processing_latency_history_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:ingress_latency_history_snapshots, organization_id, mission_id, opts})

          [
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission-1",
              source_endpoint_id: "endpoint-alpha",
              spacecraft_id: "spacecraft-alpha",
              transport_id: "transport-alpha",
              ground_station_id: "dss-14",
              link_id: "link-alpha",
              adapter_key: :tcp_socket,
              value: 4.5,
              unit: "ms",
              observed_at: ~U[2026-06-17 12:01:00Z],
              replay_run_id: "replay-run-1"
            },
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission-1",
              source_endpoint_id: "endpoint-alpha",
              spacecraft_id: "spacecraft-alpha",
              transport_id: "transport-alpha",
              ground_station_id: "dss-14",
              link_id: "link-alpha",
              adapter_key: :tcp_socket,
              value: 5.25,
              unit: "ms",
              observed_at: ~U[2026-06-17 12:02:00Z],
              replay_run_id: "replay-run-1"
            },
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission-1",
              source_endpoint_id: "endpoint-beta",
              value: 9.0,
              observed_at: ~U[2026-06-17 12:02:00Z],
              replay_run_id: "replay-run-1"
            },
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission-1",
              source_endpoint_id: "endpoint-alpha",
              value: 99.0,
              observed_at: ~U[2026-06-17 12:02:30Z],
              replay_run_id: "other-replay-run"
            },
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission-1",
              source_endpoint_id: "endpoint-alpha",
              value: 3.0,
              observed_at: ~U[2026-06-17 11:59:00Z],
              replay_run_id: "replay-run-1"
            }
          ]
        end,
        source_binding: replay_source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert result.meta.supported_capability == :ingress_processing_latency_history
    assert result.meta.returned_frame_count == 1
    assert %Frame{source: :operational_observables, shape: :wide, time_axis: :occurred_at} = frame
    assert frame.meta.supported_capability == :ingress_processing_latency_history
    assert frame.meta.product_family == :runtime_ingress
    assert frame.meta.observable_id == "ingress.processing_latency_ms"
    assert frame.meta.resource_id == "endpoint-alpha"
    assert frame.meta.scope_kind == :source_endpoint
    assert frame.meta.source_endpoint_id == "endpoint-alpha"
    assert frame.meta.transport_id == "transport-alpha"
    assert frame.meta.ground_station_id == "dss-14"
    assert frame.meta.link_id == "link-alpha"
    assert frame.meta.adapter_key == :tcp_socket
    assert frame.meta.unit == "ms"
    assert frame.meta.realm == :replay
    assert frame.meta.replay_run_id == "replay-run-1"
    assert frame.meta.returned_points == 2

    assert Enum.map(frame.meta.links, &{&1.target, &1.target_id}) == [
             {:transport, "transport-alpha"},
             {:source_endpoint, "endpoint-alpha"},
             {:ground_station, "dss-14"},
             {:link, "link-alpha"}
           ]

    resource_link_id = frame.meta.resource_link_id
    links = frame.meta.links

    assert [
             %Field{
               name: "time",
               values: [~U[2026-06-17 12:01:00Z], ~U[2026-06-17 12:02:00Z]]
             },
             %Field{
               name: "ingress.processing_latency_ms",
               values: [4.5, 5.25],
               metadata: %{
                 observable_id: "ingress.processing_latency_ms",
                 label: "Ingress latency / endpoint-alpha",
                 unit: "ms",
                 resource_id: "endpoint-alpha",
                 scope_kind: :source_endpoint,
                 transport_id: "transport-alpha",
                 source_endpoint_id: "endpoint-alpha",
                 ground_station_id: "dss-14",
                 link_id: "link-alpha",
                 adapter_key: :tcp_socket,
                 resource_link_id: ^resource_link_id,
                 links: ^links
               }
             }
           ] = frame.fields

    assert_received {:ingress_latency_history_snapshots, "org-1", "mission-1", opts}
    assert opts[:realm] == :replay
    assert opts[:dataset] == "operational_observables_replay"
    assert opts[:replay_run_id] == "replay-run-1"
    assert opts[:from] == ~U[2026-06-17 12:00:00Z]
    assert opts[:to] == ~U[2026-06-17 12:03:00Z]
  end

  test "filters ingress processing latency history rows to contact scope" do
    result =
      source_request()
      |> Map.put(:observables, ["ingress.processing_latency_ms"])
      |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
      |> Map.put(:scope_context, %{
        primary: %{kind: :contact, mode: :one, ids: ["contact-alpha"]}
      })
      |> Map.put(:time_context, %{
        from: ~U[2026-06-17 12:00:00Z],
        to: ~U[2026-06-17 12:03:00Z]
      })
      |> OperationalObservables.resolve(
        ingress_processing_latency_history_snapshots_fun: fn _organization_id,
                                                             _mission_id,
                                                             _opts ->
          [
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission-1",
              source_endpoint_id: "endpoint-alpha",
              contact_id: "contact-alpha",
              value: 4.5,
              observed_at: ~U[2026-06-17 12:01:00Z],
              source_event_id:
                "operational_event:operational_observable_snapshot:contact-ingress-1"
            },
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission-1",
              source_endpoint_id: "endpoint-beta",
              contact_id: "contact-beta",
              value: 5.5,
              observed_at: ~U[2026-06-17 12:02:00Z],
              source_event_id:
                "operational_event:operational_observable_snapshot:contact-ingress-2"
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert frame.meta.returned_points == 1
    assert frame.meta.resource_id == "endpoint-alpha"
    assert frame.meta.contact_id == "contact-alpha"

    assert frame.meta.links
           |> Enum.filter(&(&1.target in [:source_endpoint, :contact]))
           |> Enum.map(&{&1.target, &1.target_id}) == [
             {:source_endpoint, "endpoint-alpha"},
             {:contact, "contact-alpha"}
           ]

    assert %DataLink{
             target: :operational_event,
             target_id: "operational_event:operational_observable_snapshot:contact-ingress-1"
           } = Enum.find(frame.meta.links, &(&1.target == :operational_event))

    resource_link_id = frame.meta.resource_link_id
    field_links = Enum.filter(frame.meta.links, &(&1.target in [:source_endpoint, :contact]))

    assert [
             %Field{name: "time", values: [~U[2026-06-17 12:01:00Z]]},
             %Field{
               name: "ingress.processing_latency_ms",
               values: [4.5],
               metadata: %{
                 observable_id: "ingress.processing_latency_ms",
                 label: "Ingress latency / endpoint-alpha",
                 unit: "ms",
                 resource_id: "endpoint-alpha",
                 scope_kind: :source_endpoint,
                 source_endpoint_id: "endpoint-alpha",
                 contact_id: "contact-alpha",
                 resource_link_id: ^resource_link_id,
                 links: ^field_links
               }
             }
           ] = frame.fields
  end

  test "resolves empty ingress processing latency history as a chartable zero-point frame" do
    result =
      source_request()
      |> Map.put(:observables, ["ingress.processing_latency_ms"])
      |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
      |> Map.put(:scope_context, %{
        primary: %{kind: :source_endpoint, mode: :one, ids: ["endpoint-alpha"]}
      })
      |> Map.put(:time_context, %{
        from: ~U[2026-06-17 12:00:00Z],
        to: ~U[2026-06-17 12:03:00Z]
      })
      |> OperationalObservables.resolve(
        ingress_processing_latency_history_snapshots_fun: fn organization_id, mission_id, opts ->
          send(
            self(),
            {:empty_ingress_latency_history_snapshots, organization_id, mission_id, opts}
          )

          []
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    refute result.meta.degraded?
    assert result.meta.supported_capability == :ingress_processing_latency_history
    assert frame.meta.supported_capability == :ingress_processing_latency_history
    assert frame.meta.product_family == :runtime_ingress
    assert frame.meta.observable_id == "ingress.processing_latency_ms"
    assert frame.meta.resource_id == "endpoint-alpha"
    assert frame.meta.scope_kind == :source_endpoint
    assert frame.meta.source_endpoint_id == "endpoint-alpha"
    assert frame.meta.unit == "ms"
    assert frame.meta.returned_points == 0
    assert frame.meta.warning_codes == []

    assert Enum.map(frame.meta.links, &{&1.target, &1.target_id}) == [
             {:source_endpoint, "endpoint-alpha"}
           ]

    resource_link_id = frame.meta.resource_link_id
    links = frame.meta.links

    assert [
             %Field{name: "time", values: []},
             %Field{
               name: "ingress.processing_latency_ms",
               values: [],
               metadata: %{
                 observable_id: "ingress.processing_latency_ms",
                 label: "Ingress latency / endpoint-alpha",
                 unit: "ms",
                 resource_id: "endpoint-alpha",
                 scope_kind: :source_endpoint,
                 source_endpoint_id: "endpoint-alpha",
                 resource_link_id: ^resource_link_id,
                 links: ^links
               }
             }
           ] = frame.fields

    assert_received {:empty_ingress_latency_history_snapshots, "org-1", "mission-1", opts}
    assert opts[:realm] == :flight
    assert opts[:dataset] == "operational_observables"
  end

  test "resolves mixed operational metric history through product-specific wide frames" do
    result =
      source_request()
      |> Map.put(:observables, [
        "link.snr_db",
        "comms.transport.downlink_bitrate",
        "ingress.processing_latency_ms"
      ])
      |> Map.put(:sampling, %{mode: :raw_series, limit: 10})
      |> Map.put(:time_context, %{
        from: ~U[2026-06-17 12:00:00Z],
        to: ~U[2026-06-17 12:03:00Z]
      })
      |> OperationalObservables.resolve(
        transports_fun: fn organization_id, mission_id, opts ->
          send(self(), {:mixed_metric_history_transports, organization_id, mission_id, opts})

          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha"
            )
          ]
        end,
        link_rf_metric_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:mixed_rf_metric_history_snapshots, organization_id, mission_id, opts})

          [
            %{
              observable_id: "link.snr_db",
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :rf_adapter,
              value: 11.5,
              unit: "dB",
              observed_at: ~U[2026-06-17 12:01:00Z],
              source_event_id: "operational_event:operational_observable_snapshot:rf-snr-1"
            }
          ]
        end,
        transport_metric_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:mixed_bitrate_history_snapshots, organization_id, mission_id, opts})

          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14",
              link_assignment_id: "link-alpha",
              adapter_key: :tcp_socket,
              downlink_bitrate: 12_500.5,
              observed_at: ~U[2026-06-17 12:01:30Z],
              source_event_id:
                "operational_event:operational_observable_snapshot:downlink-bitrate-1"
            }
          ]
        end,
        ingress_processing_latency_history_snapshots_fun: fn organization_id, mission_id, opts ->
          send(self(), {:mixed_ingress_history_snapshots, organization_id, mission_id, opts})

          [
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission-1",
              source_endpoint_id: "endpoint-alpha",
              spacecraft_id: "spacecraft-alpha",
              transport_id: "transport-alpha",
              ground_station_id: "dss-14",
              link_id: "link-alpha",
              adapter_key: :tcp_socket,
              value: 4.5,
              unit: "ms",
              observed_at: ~U[2026-06-17 12:02:00Z],
              source_event_id: "operational_event:operational_observable_snapshot:ingress-1"
            }
          ]
        end,
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [rf_frame, bitrate_frame, ingress_frame], warnings: []} =
             result

    assert result.meta.supported_capability == :operational_metric_history
    assert result.meta.returned_frame_count == 3

    assert Enum.map(result.frames, & &1.meta.supported_capability) == [
             :link_rf_metric_history,
             :transport_bitrate_history,
             :ingress_processing_latency_history
           ]

    assert Enum.map(result.frames, & &1.meta.product_family) == [
             :link_rf,
             :transport_bitrate,
             :runtime_ingress
           ]

    assert rf_frame.meta.observable_id == "link.snr_db"
    assert rf_frame.meta.resource_id == "link-alpha"
    assert rf_frame.meta.returned_points == 1
    assert [%Field{name: "time", values: [~U[2026-06-17 12:01:00Z]]}, rf_value] = rf_frame.fields
    assert rf_value.name == "link.snr_db"
    assert rf_value.values == [11.5]
    assert rf_value.metadata.resource_id == "link-alpha"

    assert operational_event_link_ids(rf_frame) == [
             "operational_event:operational_observable_snapshot:rf-snr-1"
           ]

    assert operational_event_evidence_ids(rf_frame) == [
             "operational_event:operational_observable_snapshot:rf-snr-1"
           ]

    assert bitrate_frame.meta.observable_id == "comms.transport.downlink_bitrate"
    assert bitrate_frame.meta.resource_id == "transport-alpha"
    assert bitrate_frame.meta.returned_points == 1

    assert [
             %Field{name: "time", values: [~U[2026-06-17 12:01:30Z]]},
             bitrate_value
           ] = bitrate_frame.fields

    assert bitrate_value.name == "comms.transport.downlink_bitrate"
    assert bitrate_value.values == [12_500.5]
    assert bitrate_value.metadata.resource_id == "transport-alpha"

    assert operational_event_link_ids(bitrate_frame) == [
             "operational_event:operational_observable_snapshot:downlink-bitrate-1"
           ]

    assert operational_event_evidence_ids(bitrate_frame) == [
             "operational_event:operational_observable_snapshot:downlink-bitrate-1"
           ]

    assert ingress_frame.meta.observable_id == "ingress.processing_latency_ms"
    assert ingress_frame.meta.resource_id == "endpoint-alpha"
    assert ingress_frame.meta.returned_points == 1

    assert [
             %Field{name: "time", values: [~U[2026-06-17 12:02:00Z]]},
             ingress_value
           ] = ingress_frame.fields

    assert ingress_value.name == "ingress.processing_latency_ms"
    assert ingress_value.values == [4.5]
    assert ingress_value.metadata.resource_id == "endpoint-alpha"

    assert operational_event_link_ids(ingress_frame) == [
             "operational_event:operational_observable_snapshot:ingress-1"
           ]

    assert operational_event_evidence_ids(ingress_frame) == [
             "operational_event:operational_observable_snapshot:ingress-1"
           ]

    assert_received {:mixed_metric_history_transports, "org-1", "mission-1", transport_opts}
    assert transport_opts[:realm] == :flight
    assert transport_opts[:dataset] == "operational_observables"

    assert_received {:mixed_rf_metric_history_snapshots, "org-1", "mission-1", rf_opts}
    assert rf_opts[:from] == ~U[2026-06-17 12:00:00Z]
    assert rf_opts[:to] == ~U[2026-06-17 12:03:00Z]

    assert_received {:mixed_bitrate_history_snapshots, "org-1", "mission-1", bitrate_opts}
    assert bitrate_opts[:from] == ~U[2026-06-17 12:00:00Z]
    assert bitrate_opts[:to] == ~U[2026-06-17 12:03:00Z]

    assert_received {:mixed_ingress_history_snapshots, "org-1", "mission-1", ingress_opts}
    assert ingress_opts[:from] == ~U[2026-06-17 12:00:00Z]
    assert ingress_opts[:to] == ~U[2026-06-17 12:03:00Z]
  end

  test "filters command queue depth to source endpoint scope" do
    result =
      source_request()
      |> Map.put(:observables, ["commanding.queue_depth"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{
        primary: %{kind: :source_endpoint, mode: :one, ids: ["endpoint-alpha"]}
      })
      |> OperationalObservables.resolve(
        command_queue_entries_fun: fn _organization_id, _mission_id, _opts ->
          [
            command_queue_entry("queue-1", "endpoint-alpha", :pending),
            command_queue_entry("queue-2", "endpoint-beta", :pending)
          ]
        end,
        read_time: ~U[2026-06-17 12:05:00Z],
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert [%DataLink{target: :source_endpoint, target_id: "endpoint-alpha"}] = frame.meta.links

    assert [
             %Field{name: "observable_id", values: ["commanding.queue_depth"]},
             %Field{name: "resource_id", values: ["endpoint-alpha"]},
             %Field{name: "label", values: ["source endpoint / endpoint-alpha"]},
             %Field{name: "scope_kind", values: [:source_endpoint]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "value", values: [1]} | _rest
           ] = frame.fields
  end

  test "filters command queue depth to multi-spacecraft scope without mislabeling the first spacecraft" do
    scope_ids = ["spacecraft-alpha", "spacecraft-beta"]
    resource_id = Enum.join(scope_ids, ",")

    result =
      source_request()
      |> Map.put(:observables, ["commanding.queue_depth"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{
        primary: %{kind: :spacecraft, mode: :many, ids: scope_ids}
      })
      |> OperationalObservables.resolve(
        command_queue_entries_fun: fn _organization_id, _mission_id, _opts ->
          [
            command_queue_entry("queue-alpha", "endpoint-alpha", :pending)
            |> Map.put(:metadata, %{"spacecraft_id" => "spacecraft-alpha"}),
            command_queue_entry("queue-beta", "endpoint-beta", :pending)
            |> Map.put(:metadata, %{"spacecraft_id" => "spacecraft-beta"}),
            command_queue_entry("queue-gamma", "endpoint-gamma", :pending)
            |> Map.put(:metadata, %{"spacecraft_id" => "spacecraft-gamma"}),
            command_queue_entry("queue-released", "endpoint-alpha", :released)
            |> Map.put(:metadata, %{"spacecraft_id" => "spacecraft-alpha"})
          ]
        end,
        read_time: ~U[2026-06-17 12:05:00Z],
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    assert frame.meta.links == []

    assert [
             %Field{name: "observable_id", values: ["commanding.queue_depth"]},
             %Field{name: "resource_id", values: [^resource_id]},
             %Field{name: "label", values: ["spacecraft / " <> ^resource_id]},
             %Field{name: "scope_kind", values: [:spacecraft]},
             %Field{name: "source_endpoint_id", values: [nil]},
             %Field{name: "value", values: [2]} | _rest
           ] = frame.fields
  end

  test "resolves empty source endpoint command queue as a fresh zero with resource link" do
    result =
      source_request()
      |> Map.put(:observables, ["commanding.queue_depth"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{
        primary: %{kind: :source_endpoint, mode: :one, ids: ["endpoint-alpha"]}
      })
      |> OperationalObservables.resolve(
        command_queue_entries_fun: fn _organization_id, _mission_id, _opts ->
          [
            command_queue_entry("queue-1", "endpoint-beta", :pending),
            command_queue_entry("queue-2", "endpoint-alpha", :released)
          ]
        end,
        freshness_now: ~U[2026-06-17 12:05:02Z],
        read_time: ~U[2026-06-17 12:05:00Z],
        source_binding: source_binding()
      )

    assert %SourceResult{frames: [frame], warnings: []} = result
    refute result.meta.degraded?
    assert [%DataLink{target: :source_endpoint, target_id: "endpoint-alpha"}] = frame.meta.links
    assert frame.meta.warning_codes == []
    assert frame.meta.freshness_checked_at == ~U[2026-06-17 12:05:02Z]

    assert [
             %Field{name: "observable_id", values: ["commanding.queue_depth"]},
             %Field{name: "resource_id", values: ["endpoint-alpha"]},
             %Field{name: "label", values: ["source endpoint / endpoint-alpha"]},
             %Field{name: "scope_kind", values: [:source_endpoint]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "value", values: [0]},
             %Field{name: "unit", values: ["commands"]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:05:00Z]]},
             %Field{name: "freshness_state", values: [:fresh]},
             %Field{name: "age_ms", values: [2_000]}
           ] = frame.fields
  end

  test "marks source endpoint command queue rows stale without dropping resource link" do
    result =
      source_request()
      |> Map.put(:observables, ["commanding.queue_depth"])
      |> Map.put(:sampling, %{mode: :latest})
      |> Map.put(:scope_context, %{
        primary: %{kind: :source_endpoint, mode: :one, ids: ["endpoint-alpha"]}
      })
      |> OperationalObservables.resolve(
        command_queue_entries_fun: fn _organization_id, _mission_id, _opts ->
          [
            command_queue_entry("queue-1", "endpoint-alpha", :pending),
            command_queue_entry("queue-2", "endpoint-beta", :pending)
          ]
        end,
        freshness_now: ~U[2026-06-17 12:05:02Z],
        freshness_policy: %{stale_after_ms: 1_000},
        read_time: ~U[2026-06-17 12:05:00Z],
        source_binding: source_binding()
      )

    assert %SourceResult{
             frames: [frame],
             warnings: [%ResolveWarning{code: :stale_data, severity: :warning} = warning]
           } = result

    assert result.meta.degraded?
    assert warning.details.supported_capability == :command_queue_depth
    assert warning.details.observable_ids == ["commanding.queue_depth"]
    assert [%DataLink{target: :source_endpoint, target_id: "endpoint-alpha"}] = frame.meta.links
    assert frame.meta.warning_codes == [:stale_data]
    assert frame.meta.freshness_policy == %{stale_after_ms: 1_000}
    assert frame.meta.freshness_checked_at == ~U[2026-06-17 12:05:02Z]

    assert [
             %Field{name: "observable_id", values: ["commanding.queue_depth"]},
             %Field{name: "resource_id", values: ["endpoint-alpha"]},
             %Field{name: "label", values: ["source endpoint / endpoint-alpha"]},
             %Field{name: "scope_kind", values: [:source_endpoint]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "value", values: [1]},
             %Field{name: "unit", values: ["commands"]},
             %Field{name: "observed_at", values: [~U[2026-06-17 12:05:00Z]]},
             %Field{name: "freshness_state", values: [:stale]},
             %Field{name: "age_ms", values: [2_000]}
           ] = frame.fields
  end

  test "resolves mixed latest operational observables into product frames" do
    result =
      source_request()
      |> Map.put(:observables, [
        "contacts.phase",
        "comms.transport.connection_state",
        "link.snr_db",
        "comms.transport.downlink_bitrate",
        "commanding.queue_depth",
        "ingress.processing_latency_ms"
      ])
      |> Map.put(:sampling, %{mode: :latest})
      |> OperationalObservables.resolve(
        scheduled_contacts_fun: fn _organization_id, _mission_id, _opts ->
          [scheduled_contact("contact-1", :scheduled)]
        end,
        realized_contacts_fun: fn _organization_id, _mission_id, _opts -> [] end,
        transports_fun: fn _organization_id, _mission_id, _opts ->
          [
            transport("transport-alpha", "Lab TCP",
              source_endpoint_id: "endpoint-alpha",
              ground_station_id: "dss-14"
            )
          ]
        end,
        source_endpoints_fun: fn _organization_id, _mission_id, _opts -> [] end,
        connection_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              adapter_key: :tcp_socket,
              connection_state: :connected,
              observed_at: ~U[2026-06-17 12:03:00Z]
            }
          ]
        end,
        link_rf_metric_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              adapter_key: :rf_adapter,
              snr_db: 12.75,
              observed_at: ~U[2026-06-17 12:08:00Z]
            }
          ]
        end,
        transport_metric_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              transport_id: "transport-alpha",
              source_endpoint_id: "endpoint-alpha",
              adapter_key: :tcp_socket,
              downlink_bitrate: 12_500.5,
              observed_at: ~U[2026-06-17 12:04:00Z]
            }
          ]
        end,
        command_queue_entries_fun: fn _organization_id, _mission_id, _opts ->
          [
            command_queue_entry("queue-1", "endpoint-alpha", :pending),
            command_queue_entry("queue-2", "endpoint-beta", :pending)
          ]
        end,
        runtime_metric_snapshots_fun: fn _organization_id, _mission_id, _opts ->
          [
            %{
              observable_id: "ingress.processing_latency_ms",
              mission_id: "mission-1",
              source_endpoint_id: "endpoint-alpha",
              spacecraft_id: "spacecraft-alpha",
              value: 4.5,
              observed_at: ~U[2026-06-17 12:06:00Z],
              error?: false
            }
          ]
        end,
        read_time: ~U[2026-06-17 12:05:00Z],
        source_binding: source_binding()
      )

    assert %SourceResult{
             frames: [
               contact_frame,
               connection_frame,
               rf_metric_frame,
               bitrate_frame,
               queue_depth_frame,
               ingress_latency_frame
             ],
             warnings: []
           } = result

    assert result.meta.supported_capability == :operational_latest
    assert result.meta.returned_frame_count == 6

    assert contact_frame.meta.supported_capability == :contacts_phase
    assert contact_frame.meta.observable_id == "contacts.phase"
    assert contact_frame.meta.returned_points == 1

    assert [
             %Field{name: "observable_id", values: ["contacts.phase"]},
             %Field{name: "contact_id", values: ["contact-1"]} | _rest
           ] = contact_frame.fields

    assert connection_frame.meta.supported_capability == :connection_state
    assert connection_frame.meta.observable_ids == ["comms.transport.connection_state"]
    assert connection_frame.meta.returned_points == 1

    assert [
             %Field{name: "observable_id", values: ["comms.transport.connection_state"]},
             %Field{name: "resource_id", values: ["transport-alpha"]} | _rest
           ] = connection_frame.fields

    assert rf_metric_frame.meta.supported_capability == :link_rf_metric
    assert rf_metric_frame.meta.product_family == :link_rf
    assert rf_metric_frame.meta.observable_ids == ["link.snr_db"]
    assert rf_metric_frame.meta.returned_points == 1

    assert [
             %Field{name: "observable_id", values: ["link.snr_db"]},
             %Field{name: "resource_id", values: ["transport-alpha"]},
             %Field{name: "label", values: ["RF SNR / Lab TCP"]},
             %Field{name: "scope_kind", values: [:link]},
             %Field{name: "transport_id", values: ["transport-alpha"]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "ground_station_id", values: ["dss-14"]},
             %Field{name: "link_id", values: [nil]},
             %Field{name: "adapter_key", values: [:rf_adapter]},
             %Field{name: "value", values: [12.75]},
             %Field{name: "unit", values: ["dB"]} | _rest
           ] = rf_metric_frame.fields

    assert bitrate_frame.meta.supported_capability == :transport_bitrate
    assert bitrate_frame.meta.observable_id == "comms.transport.downlink_bitrate"
    assert bitrate_frame.meta.observable_ids == ["comms.transport.downlink_bitrate"]
    assert bitrate_frame.meta.returned_points == 1

    assert [
             %Field{name: "observable_id", values: ["comms.transport.downlink_bitrate"]},
             %Field{name: "resource_id", values: ["transport-alpha"]} | _rest
           ] = bitrate_frame.fields

    assert queue_depth_frame.meta.supported_capability == :command_queue_depth
    assert queue_depth_frame.meta.product_family == :commanding
    assert queue_depth_frame.meta.observable_id == "commanding.queue_depth"
    assert queue_depth_frame.meta.observable_ids == ["commanding.queue_depth"]
    assert queue_depth_frame.meta.returned_points == 1

    assert [
             %Field{name: "observable_id", values: ["commanding.queue_depth"]},
             %Field{name: "resource_id", values: ["mission-1"]},
             %Field{name: "label", values: ["Pending commands"]},
             %Field{name: "scope_kind", values: [:mission]},
             %Field{name: "source_endpoint_id", values: [nil]},
             %Field{name: "value", values: [2]} | _rest
           ] = queue_depth_frame.fields

    assert ingress_latency_frame.meta.supported_capability == :ingress_processing_latency
    assert ingress_latency_frame.meta.product_family == :runtime_ingress
    assert ingress_latency_frame.meta.observable_id == "ingress.processing_latency_ms"
    assert ingress_latency_frame.meta.observable_ids == ["ingress.processing_latency_ms"]
    assert ingress_latency_frame.meta.returned_points == 1

    assert [
             %Field{name: "observable_id", values: ["ingress.processing_latency_ms"]},
             %Field{name: "resource_id", values: ["endpoint-alpha"]},
             %Field{name: "label", values: ["Ingress latency / endpoint-alpha"]},
             %Field{name: "scope_kind", values: [:source_endpoint]},
             %Field{name: "source_endpoint_id", values: ["endpoint-alpha"]},
             %Field{name: "transport_id", values: [nil]},
             %Field{name: "ground_station_id", values: [nil]},
             %Field{name: "link_id", values: [nil]},
             %Field{name: "contact_id", values: [nil]},
             %Field{name: "adapter_key", values: [nil]},
             %Field{name: "spacecraft_id", values: ["spacecraft-alpha"]},
             %Field{name: "value", values: [4.5]} | _rest
           ] = ingress_latency_frame.fields
  end

  defp source_request do
    %PlannedSourceRequest{
      request_id: "ops-request-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      logical_source: :operational_observables,
      observables: [],
      data_context: %{realm: :flight},
      sampling: %{mode: :constellation_health}
    }
  end

  defp assert_replay_operational_observable_opts(opts, from_time, to_time) do
    assert opts[:realm] == :replay
    assert opts[:data_source_id] == "managed_operational_observables_replay"
    assert opts[:source_binding_id] == "replay-operational-observables"
    assert opts[:dataset] == "operational_observables_replay"
    assert opts[:replay_run_id] == "replay-run-1"
    assert opts[:from] == from_time
    assert opts[:to] == to_time
  end

  defp source_binding do
    %ResolvedSourceBinding{
      binding: %DataBinding{
        binding_id: "flight-operational-observables",
        realm: :flight,
        logical_source: :operational_observables,
        data_source_id: "managed_operational_observables",
        dataset: "operational_observables"
      },
      data_source: %DataSource{
        data_source_id: "managed_operational_observables",
        adapter: OperationalObservables
      },
      realm: :flight,
      dataset: "operational_observables"
    }
  end

  defp replay_source_binding do
    %ResolvedSourceBinding{
      binding: %DataBinding{
        binding_id: "replay-operational-observables",
        realm: :replay,
        logical_source: :operational_observables,
        data_source_id: "managed_operational_observables_replay",
        dataset: "operational_observables_replay"
      },
      data_source: %DataSource{
        data_source_id: "managed_operational_observables_replay",
        adapter: OperationalObservables
      },
      realm: :replay,
      dataset: "operational_observables_replay"
    }
  end

  defp managed_runtime_event(event_id, source_record_kind, kind, occurred_at, opts) do
    runtime_fact_id = Keyword.fetch!(opts, :runtime_fact_id)

    capability_instance_id =
      Keyword.get(opts, :capability_instance_id, "managed-capability-alpha")

    OperationalEvent.new(%{
      event_id: event_id,
      organization_id: "org-1",
      mission_id: "mission-1",
      occurred_at: occurred_at,
      recorded_at: occurred_at,
      effective_at: occurred_at,
      category: :runtime,
      kind: kind,
      severity: :info,
      actor: %{kind: :replay, id: "replay-run-1"},
      subject: %{kind: :capability_instance, id: capability_instance_id},
      scope: %{
        replay_run_id: "replay-run-1",
        capability_instance_id: capability_instance_id,
        partition_affinity: :spacecraft,
        partition_value: "spacecraft-alpha"
      },
      causality: %{
        replay_run_id: "replay-run-1",
        correlation_id: capability_instance_id,
        source_record_kind: source_record_kind,
        source_record_id: runtime_fact_id
      },
      payload:
        %{
          replay_run_id: "replay-run-1",
          capability_instance_id: capability_instance_id,
          family_key: :packet_counter,
          activation_id: "activation-alpha",
          binding_set_id: "binding-set-alpha",
          binding_set_version: 1,
          partition_affinity: :spacecraft,
          partition_value: "spacecraft-alpha",
          packet_id: "packet-alpha",
          evidence_id: "evidence-alpha"
        }
        |> Map.merge(
          Map.take(Map.new(opts), [
            :timer_key,
            :action_kind,
            :event_kind,
            :emitted_record_kinds,
            :emitted_record_count,
            :action_request_count,
            :state_snapshot,
            :record_metadata,
            :request_document
          ])
        ),
      current: %{}
    })
  end

  defp transport_runtime_event(event_id, source_record_kind, kind, occurred_at, opts) do
    runtime_fact_id = Keyword.fetch!(opts, :runtime_fact_id)

    capability_instance_id =
      Keyword.get(opts, :capability_instance_id, "transport-alpha")

    OperationalEvent.new(%{
      event_id: event_id,
      organization_id: "org-1",
      mission_id: "mission-1",
      occurred_at: occurred_at,
      recorded_at: occurred_at,
      effective_at: occurred_at,
      category: :comms,
      kind: kind,
      severity: :info,
      actor: %{kind: :replay, id: "replay-run-1"},
      subject: %{kind: :transport, id: capability_instance_id},
      scope: %{
        replay_run_id: "replay-run-1",
        contact_id: "replay-contact-alpha",
        realized_contact_id: "replay-contact-alpha",
        path_id: "replay-uplink-path",
        capability_instance_id: capability_instance_id,
        source_endpoint_ref: Keyword.get(opts, :source_endpoint_ref),
        partition_affinity: :source_endpoint,
        partition_value: "endpoint-alpha"
      },
      causality: %{
        replay_run_id: "replay-run-1",
        correlation_id: capability_instance_id,
        source_record_kind: source_record_kind,
        source_record_id: runtime_fact_id
      },
      payload:
        %{
          replay_run_id: "replay-run-1",
          contact_id: "replay-contact-alpha",
          realized_contact_id: "replay-contact-alpha",
          path_id: "replay-uplink-path",
          capability_instance_id: capability_instance_id,
          source_endpoint_ref: Keyword.get(opts, :source_endpoint_ref),
          family_key: :uplink_gateway,
          activation_id: "transport-activation-alpha",
          binding_set_id: "transport-binding-set-alpha",
          binding_set_version: 1,
          partition_affinity: :source_endpoint,
          partition_value: "endpoint-alpha"
        }
        |> Map.merge(
          Map.take(Map.new(opts), [
            :timer_key,
            :action_kind,
            :command_release_attempt_id,
            :command_request_id,
            :command_name,
            :signal_phase,
            :event_kind,
            :emitted_record_kinds,
            :emitted_record_count,
            :action_request_count,
            :state_snapshot,
            :record_metadata,
            :request_document,
            :action_metadata,
            :timer_metadata
          ])
        ),
      current: %{}
    })
  end

  defp spacecraft(spacecraft_id) do
    %Spacecraft{
      organization_id: "org-1",
      mission_id: "mission-1",
      spacecraft_id: spacecraft_id,
      display_name: spacecraft_id
    }
  end

  defp scheduled_contact(scheduled_contact_id, lifecycle_state, opts \\ []) do
    %ScheduledContact{
      organization_id: "org-1",
      mission_id: "mission-1",
      scheduled_contact_id: scheduled_contact_id,
      realized_contact_id: Keyword.get(opts, :realized_contact_id),
      lifecycle_state: lifecycle_state,
      source_endpoint_refs: Keyword.get(opts, :source_endpoint_refs, ["source-endpoint-alpha"]),
      starts_at: Keyword.get(opts, :starts_at, ~U[2026-06-17 12:00:00Z])
    }
  end

  defp realized_contact(realized_contact_id, lifecycle_state, opts \\ []) do
    %RealizedContact{
      organization_id: "org-1",
      mission_id: "mission-1",
      realized_contact_id: realized_contact_id,
      scheduled_contact_id: Keyword.get(opts, :scheduled_contact_id),
      lifecycle_state: lifecycle_state,
      source_endpoint_refs: Keyword.get(opts, :source_endpoint_refs, ["source-endpoint-alpha"]),
      realized_at: ~U[2026-06-17 12:00:01Z]
    }
  end

  defp transport(transport_id, display_name, opts) do
    Transport.new(%{
      transport_id: transport_id,
      organization_id: "org-1",
      mission_id: "mission-1",
      display_name: display_name,
      transport_kind: :tcp_socket,
      direction_capability: :bidirectional,
      adapter_key: :tcp_socket,
      configuration: %{},
      metadata: Map.new(opts, fn {key, value} -> {Atom.to_string(key), value} end)
    })
  end

  defp source_endpoint(source_endpoint_id, display_name, opts \\ []) do
    SourceEndpoint.new(%{
      source_endpoint_id: source_endpoint_id,
      organization_id: "org-1",
      mission_id: "mission-1",
      display_name: display_name,
      spacecraft_id: Keyword.get(opts, :spacecraft_id),
      metadata: Map.new(opts, fn {key, value} -> {Atom.to_string(key), value} end)
    })
  end

  defp command_queue_entry(entry_id, source_endpoint_ref, lifecycle_state) do
    CommandQueueEntry.new(%{
      command_queue_entry_id: entry_id,
      organization_id: "org-1",
      mission_id: "mission-1",
      command_request_id: "command-request-#{entry_id}",
      source_endpoint_ref: source_endpoint_ref,
      queue_lane_key: source_endpoint_ref,
      lifecycle_state: lifecycle_state,
      enqueued_at: ~U[2026-06-17 12:00:00Z]
    })
  end

  defp transport_execution_interval(
         interval_id,
         transport_id,
         event_kind,
         starts_at,
         ends_at,
         opts \\ []
       ) do
    %EffectiveInterval{
      interval_id: interval_id,
      organization_id: "org-1",
      mission_id: "mission-1",
      kind: :transport_execution,
      subject_kind: :transport,
      subject_id: transport_id,
      starts_at: starts_at,
      ends_at: ends_at,
      source_event_id: Keyword.get(opts, :source_event_id, "event-#{interval_id}"),
      payload: %{
        "capability_instance_id" => transport_id,
        "transport_record_id" => Keyword.get(opts, :transport_record_id, "record-#{interval_id}"),
        "source_endpoint_id" => Keyword.get(opts, :source_endpoint_id, "endpoint-alpha"),
        "ground_station_id" => Keyword.get(opts, :ground_station_id, "dss-14"),
        "link_assignment_id" => Keyword.get(opts, :link_id, "link-alpha"),
        "contact_id" => Keyword.get(opts, :contact_id, "contact-alpha"),
        "path_id" => Keyword.get(opts, :path_id, "uplink-alpha"),
        "event_kind" => Atom.to_string(event_kind)
      }
    }
  end

  defp operational_event_link_ids(frame) do
    frame.meta
    |> Map.get(:links, [])
    |> Enum.filter(&(&1.target == :operational_event))
    |> Enum.map(& &1.target_id)
  end

  defp evidence_identities(frame) do
    frame.meta
    |> Map.get(:evidence_refs, [])
    |> Enum.map(&{&1.kind, &1.id})
  end

  defp operational_event_evidence_ids(frame) do
    frame.meta
    |> Map.get(:evidence_refs, [])
    |> Enum.filter(&(&1.kind == :operational_event))
    |> Enum.map(& &1.id)
  end

  defp field_values(frame, field_name) do
    frame.fields
    |> Enum.find(&(&1.name == field_name))
    |> case do
      %Field{values: values} -> values
      nil -> []
    end
  end

  defp event(spacecraft_id, normalized_state) do
    %Event{
      limit_event_id: "limit-#{spacecraft_id}-#{normalized_state}",
      mission_id: "mission-1",
      spacecraft_id: spacecraft_id,
      point_id: "HK.counter",
      point_name: "HK.counter",
      source_sample_type: :telemetry_sample,
      sample_id: "sample-#{spacecraft_id}",
      limit_definition_id: "limit-def-1",
      limit_definition_version: 3,
      limit_set_name: "ops",
      evaluated_value: 1,
      limit_state: normalized_state,
      normalized_state: normalized_state,
      violation: normalized_state in [:red, :yellow],
      generation_time: ~U[2026-06-17 12:00:00Z],
      receipt_time: ~U[2026-06-17 12:00:01Z],
      provenance: %{}
    }
  end
end
