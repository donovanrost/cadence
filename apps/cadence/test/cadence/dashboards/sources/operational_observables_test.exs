defmodule Cadence.Dashboards.Sources.OperationalObservablesTest do
  use Cadence.UnitCase, async: true

  import Cadence.Dashboards.Sources.OperationalObservablesFixtures

  alias Cadence.Dashboards.{Field, Frame, SourceResult}
  alias Cadence.Dashboards.Sources.OperationalObservables

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
end
