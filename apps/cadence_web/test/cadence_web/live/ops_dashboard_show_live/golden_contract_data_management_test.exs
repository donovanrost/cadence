defmodule CadenceWeb.OpsDashboardShowLive.GoldenContractDataManagementTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    Document,
    Engine,
    Frame,
    PlacementFrames,
    RenderItem
  }

  alias Cadence.Management.DataSources

  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage.ObservationIdentityState
  alias CadenceWeb.OpsDashboardShowLive.WidgetPresentation

  @fixture_dir Path.expand("../../../../../cadence/test/fixtures/dashboards", __DIR__)

  test "golden data-management fixture carries revision view into presenter lifecycle" do
    document = load_fixture!("data_management_value_tile.v1.json")
    parent = self()

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    request =
      document
      |> resolve_request(%{"placement_revision_counter" => %{width_px: 320, height_px: 128}})
      |> Map.put(:data_context, %{realm: :flight, view: :all_revisions})

    plan = Engine.plan(request, source_registry_opts(validate_dashboard_contract?: true))

    assert plan.dashboard_warnings == []

    assert [
             %{
               logical_source: :telemetry,
               observables: ["tlm.hk.revision_counter"],
               sampling_mode: :latest,
               products: [],
               overlays: [],
               target_points: 320,
               time_axis: "generation_time",
               data_source_id: "managed_questdb_primary",
               source_binding_id: "default_flight_telemetry"
             }
           ] = Enum.map(plan.planned_source_requests, &request_summary/1)

    result =
      Engine.resolve(
        request,
        source_registry_opts(
          validate_dashboard_contract?: true,
          source_opts: data_management_source_opts(parent)
        )
      )

    assert_received {:golden_identity_states, ["identity-golden-revision"], lookup_opts}
    assert lookup_opts[:organization_id] == "org_dashboards"
    assert lookup_opts[:mission_id] == "mission_dashboards"
    assert lookup_opts[:realm] == :flight
    assert lookup_opts[:data_source_id] == "managed_questdb_primary"

    assert result.plan_metadata.degraded?
    assert result.plan_metadata.executed_source_request_count == 1
    assert result.plan_metadata.returned_frame_count == 1

    assert result.dashboard_warnings
           |> Enum.map(& &1.code)
           |> Enum.sort() == [
             :advisory_backfill,
             :all_revisions_view,
             :corrected_range,
             :mixed_revisions
           ]

    assert %{
             "placement_revision_counter" =>
               %PlacementFrames{
                 primary: [
                   %Frame{
                     source: :telemetry,
                     shape: :scalar,
                     meta: %{
                       data_view: :all_revisions,
                       warning_codes: warning_codes,
                       revision_state: revision_state,
                       telemetry_revision_dependency: dependency
                     }
                   } = frame
                 ],
                 warnings: placement_warnings
               } = placement_frames
           } = result.frames_by_placement

    assert Enum.sort(warning_codes) == [
             :advisory_backfill,
             :all_revisions_view,
             :corrected_range,
             :mixed_revisions
           ]

    assert revision_state.identity_count == 1
    assert revision_state.superseded_count == 1
    assert revision_state.advisory_count == 1
    assert revision_state.has_superseded?
    assert revision_state.has_advisory?
    assert dependency.observation_identity_ids == ["identity-golden-revision"]

    assert Enum.map(placement_warnings, & &1.code) |> Enum.sort() == [
             :advisory_backfill,
             :all_revisions_view,
             :corrected_range,
             :mixed_revisions
           ]

    assert field_values(frame, "tlm.hk.revision_counter") == [7]

    [render_item] = RenderItem.from_document(document)
    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert %{
             kind: :point,
             engine_backed?: true,
             unresolved?: false,
             lifecycle_state: :partial,
             lifecycle: %{
               state: :partial,
               severity: :warning,
               warning_codes: lifecycle_warnings
             },
             data_management: %{
               data_view: "all_revisions",
               warning_codes: data_management_warning_codes,
               badges: badges
             },
             sample: %{
               sample_id: "sample-golden-revision",
               engineering_value: 7
             }
           } = data

    assert Enum.sort(lifecycle_warnings) == [
             :advisory_backfill,
             :all_revisions_view,
             :corrected_range,
             :mixed_revisions
           ]

    assert Enum.sort(data_management_warning_codes) == [
             "advisory_backfill",
             "all_revisions_view",
             "corrected_range",
             "mixed_revisions"
           ]

    assert Enum.map(badges, &{&1.kind, &1.value, &1.code}) == [
             {:data_view, "all_revisions", "all_revisions_view"},
             {:revision_state, "corrected", "corrected_range"},
             {:revision_state, "backfill", "advisory_backfill"}
           ]
  end

  defp load_fixture!(name) do
    @fixture_dir
    |> Path.join(name)
    |> File.read!()
    |> Jason.decode!()
    |> Document.from_map()
  end

  defp resolve_request(%Document{} = document, placement_sizes) do
    %DashboardResolveRequest{
      organization_id: document.organization_id,
      mission_id: document.mission_id,
      dashboard_id: document.dashboard_id,
      document: document,
      scope_context: %{primary: %{kind: "spacecraft", mode: "one", ids: ["sc_001"]}},
      interaction_context: %{placement_sizes: placement_sizes}
    }
  end

  defp source_registry_opts(opts) do
    Keyword.merge(
      [
        data_sources: [
          DataSources.default_managed_data_source(),
          DataSources.default_limits_data_source()
        ],
        data_bindings: [
          DataSources.default_flight_telemetry_binding(),
          DataSources.default_flight_limits_binding()
        ]
      ],
      opts
    )
  end

  defp data_management_source_opts(parent) do
    %{
      telemetry: [
        latest_fun: &revision_telemetry_sample/4,
        identity_states_fun: fn identity_ids, lookup_opts ->
          send(parent, {:golden_identity_states, identity_ids, lookup_opts})

          [
            identity_state("identity-golden-revision",
              observable_id: "tlm.hk.revision_counter",
              point_id: "tlm.hk.revision_counter",
              superseded_count: 1,
              advisory_count: 1
            )
          ]
        end,
        watermark_fun: &best_effort_watermark/4
      ]
    }
  end

  defp revision_telemetry_sample(_organization_id, mission_id, point_id, _opts) do
    %Sample{
      sample_id: "sample-golden-revision",
      mission_id: mission_id,
      spacecraft_id: "sc_001",
      point_id: point_id,
      point_name: point_id,
      packet_definition_id: "packet-def-1",
      packet_definition_version: 1,
      packet_id: "packet-1",
      evidence_id: "evidence-golden-revision",
      raw_value: 7,
      engineering_value: 7,
      quality_state: :good,
      generation_time: ~U[2026-06-17 12:00:00Z],
      receipt_time: ~U[2026-06-17 12:00:01Z],
      provenance: storage_provenance("identity-golden-revision")
    }
  end

  defp best_effort_watermark(_organization_id, _mission_id, _point_id, _opts) do
    {:ok,
     %{
       complete_through: ~U[2026-06-17 12:00:01Z],
       latest_receipt_time: ~U[2026-06-17 12:00:01Z],
       retention_starts_at: ~U[2026-06-15 00:00:00Z],
       sample_count: 1,
       confidence: :best_effort
     }}
  end

  defp storage_provenance(observation_identity_id) do
    %{
      "storage" => %{
        "observation_identity_id" => observation_identity_id,
        "observation_id" => "observation-#{observation_identity_id}",
        "validity_state" => "canonical"
      }
    }
  end

  defp identity_state(observation_identity_id, overrides) do
    attrs =
      [
        observation_identity_id: observation_identity_id,
        organization_id: "org_dashboards",
        mission_id: "mission_dashboards",
        realm: :flight,
        data_source_id: "managed_questdb_primary",
        binding_id: "default_flight_telemetry",
        observable_id: "tlm.hk.revision_counter",
        point_id: "tlm.hk.revision_counter",
        spacecraft_id: "sc_001",
        canonical_observation_id: "observation-#{observation_identity_id}",
        canonical_sample_id: "sample-#{observation_identity_id}",
        canonical_revision: 1,
        latest_observation_id: "observation-#{observation_identity_id}",
        latest_sample_id: "sample-#{observation_identity_id}",
        latest_revision: 2,
        validity_state: :canonical,
        canonical_count: 1,
        duplicate_count: 0,
        conflict_count: 0,
        superseded_count: 0,
        advisory_count: 0,
        first_seen_at: ~U[2026-06-17 12:00:00Z],
        last_seen_at: ~U[2026-06-17 12:00:00Z],
        payload: %{}
      ]
      |> Keyword.merge(overrides)

    struct!(ObservationIdentityState, attrs)
  end

  defp request_summary(request) do
    %{
      logical_source: request.logical_source,
      observables: request.observables,
      sampling_mode: request.sampling.mode,
      products: Map.get(request.sampling, :products, []),
      overlays: request.overlays,
      target_points: Map.get(request.sampling, :target_points),
      time_axis: request.time_context.axis,
      data_source_id: request.metadata.capability_provenance.data_source_id,
      source_binding_id: request.metadata.capability_provenance.binding_id
    }
  end

  defp field_values(%Frame{fields: fields}, name) do
    fields
    |> Enum.find(&(&1.name == name))
    |> then(&(&1 && &1.values))
  end
end
