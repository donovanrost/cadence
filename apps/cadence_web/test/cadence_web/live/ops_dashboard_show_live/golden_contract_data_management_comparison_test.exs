defmodule CadenceWeb.OpsDashboardShowLive.GoldenContractDataManagementComparisonTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DataSources,
    Document,
    Engine,
    Frame,
    PlacementFrames,
    RenderItem
  }

  alias Cadence.Telemetry.Sample
  alias Cadence.Telemetry.Storage.ObservationIdentityState
  alias CadenceWeb.OpsDashboardShowLive.RenderPageModel

  @fixture_dir Path.expand("../../../../../cadence/test/fixtures/dashboards", __DIR__)

  test "golden data-management fixture carries data-view comparison into render model" do
    document = load_fixture!("data_management_value_tile.v1.json")
    parent = self()

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    primary_request =
      document
      |> resolve_request(%{"placement_revision_counter" => %{width_px: 320, height_px: 128}})
      |> Map.put(:data_context, %{realm: :flight, view: :all_revisions})

    compare_request = %{
      primary_request
      | data_context: %{realm: :flight, view: :canonical}
    }

    primary_result =
      Engine.resolve(
        primary_request,
        source_registry_opts(
          validate_dashboard_contract?: true,
          source_opts: data_management_source_opts(parent)
        )
      )

    compare_result =
      Engine.resolve(
        compare_request,
        source_registry_opts(
          validate_dashboard_contract?: true,
          source_opts: comparison_source_opts()
        )
      )

    assert_received {:golden_identity_states, ["identity-golden-revision"], _lookup_opts}

    assert primary_result.plan_metadata.degraded?
    refute compare_result.plan_metadata.degraded?
    assert compare_result.dashboard_warnings == []

    assert %{
             "placement_revision_counter" => %PlacementFrames{primary: [%Frame{} = primary_frame]}
           } = primary_result.frames_by_placement

    assert %{
             "placement_revision_counter" => %PlacementFrames{primary: [%Frame{} = compare_frame]}
           } = compare_result.frames_by_placement

    assert primary_frame.meta.data_view == :all_revisions
    assert compare_frame.meta.data_view == :canonical
    assert field_values(primary_frame, "tlm.hk.revision_counter") == [7]
    assert field_values(compare_frame, "tlm.hk.revision_counter") == [5]

    model =
      document
      |> comparison_render_assigns(primary_result, compare_result)
      |> RenderPageModel.build()

    assert [widget_item] = model.widget_items
    assert widget_item.item.placement_id == "placement_revision_counter"
    assert widget_item.props.data.sample.sample_id == "sample-golden-revision"
    assert widget_item.props.data.sample.engineering_value == 7
    assert widget_item.props.compare_data.sample.sample_id == "sample-golden-canonical"
    assert widget_item.props.compare_data.sample.engineering_value == 5

    assert %{
             state: "increased",
             label: "Canonical +2",
             title: "All revisions compared with Canonical: +2 from 5",
             primary_view: "all_revisions",
             compare_view: "canonical",
             primary_count: 1,
             compare_count: 1,
             delta: "+2",
             primary_sample_id: "sample-golden-revision",
             compare_sample_id: "sample-golden-canonical",
             primary_data_link: primary_link,
             compare_data_link: compare_link
           } = widget_item.props.comparison_summary

    assert primary_link.target == :telemetry_sample
    assert primary_link.target_id == "sample-golden-revision"
    assert compare_link.target == :telemetry_sample
    assert compare_link.target_id == "sample-golden-canonical"

    assert model.root_attrs["data-dashboard-comparison-widgets"] == 1
    assert model.root_attrs["data-dashboard-comparison-deltas"] == 1
    assert model.root_attrs["data-dashboard-comparison-missing"] == 0
    assert model.root_attrs["data-dashboard-comparison-states"] == "increased"

    assert model.root_attrs["data-dashboard-comparison-delta-placements"] ==
             "placement_revision_counter"

    assert model.comparison_rollup.visible?
    assert model.comparison_rollup.delta_count == 1
    assert model.comparison_rollup.missing_count == 0

    assert [
             %{
               key: "deltas",
               placement_ids: "placement_revision_counter",
               items: [
                 %{
                   placement_id: "placement_revision_counter",
                   title: "Revision Counter",
                   state: "increased",
                   label: "Canonical +2",
                   delta: "+2",
                   primary_sample_id: "sample-golden-revision",
                   compare_sample_id: "sample-golden-canonical"
                 }
               ]
             }
           ] = model.comparison_rollup.groups

    assert model.comparison_preset["schema"] == "dashboard_comparison_investigation_preset.v1"
    assert model.comparison_preset["dashboard_id"] == "dashboard_data_management_value_tile"
    assert model.comparison_preset["mission_id"] == "mission_dashboards"

    assert model.comparison_preset["runtime_query"] == %{
             "compare_data_view" => "canonical",
             "data_source_id" => "managed_questdb_primary",
             "data_view" => "all_revisions",
             "source_binding_id" => "default_flight_telemetry",
             "spacecraft_id" => "sc_001"
           }

    assert model.comparison_preset["comparison"] == %{
             "primary_data_view" => "all_revisions",
             "compare_data_view" => "canonical",
             "widget_count" => 1,
             "delta_count" => 1,
             "unchanged_count" => 0,
             "coverage_count" => 0,
             "missing_count" => 0,
             "handled_count" => 0,
             "open_count" => 1,
             "unhandled_count" => 1,
             "states" => "increased"
           }

    assert [
             %{
               "key" => "deltas",
               "placement_ids" => ["placement_revision_counter"],
               "items" => [
                 %{
                   "placement_id" => "placement_revision_counter",
                   "state" => "increased",
                   "label" => "Canonical +2",
                   "delta" => "+2",
                   "primary_sample_id" => "sample-golden-revision",
                   "compare_sample_id" => "sample-golden-canonical",
                   "primary_data_link" => %{
                     "target" => "telemetry_sample",
                     "target_id" => "sample-golden-revision"
                   },
                   "compare_data_link" => %{
                     "target" => "telemetry_sample",
                     "target_id" => "sample-golden-canonical"
                   }
                 }
               ]
             }
           ] = model.comparison_preset["groups"]
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

  defp comparison_render_assigns(%Document{} = document, primary_result, compare_result) do
    %{
      current_scope: %{organization_id: document.organization_id},
      current_mission: %{mission_id: document.mission_id},
      dashboard_document: document,
      dashboard_data_realms: ["flight"],
      dashboard_data_bindings: [
        DataSources.default_flight_telemetry_binding()
      ],
      dashboard_render_items: RenderItem.from_document(document),
      dashboard_engine_result: primary_result,
      dashboard_compare_engine_result: compare_result,
      dashboard_engine_frames_by_placement: primary_result.frames_by_placement,
      dashboard_compare_engine_frames_by_placement: compare_result.frames_by_placement,
      dashboard_selected_data_ref: nil,
      dashboard_selection_query: nil,
      dashboard_evidence_query: nil,
      dashboard_compare_data_view: "canonical",
      dashboard_time_mode: "live",
      dashboard_time_from: nil,
      dashboard_time_to: nil,
      dashboard_replay_run_id: nil,
      dashboard_time_context: %{"mode" => "live", "axis" => "generation_time"},
      dashboard_data_realm: "flight",
      dashboard_data_view: "all_revisions",
      dashboard_data_source_id: "managed_questdb_primary",
      dashboard_source_binding_id: "default_flight_telemetry",
      dashboard_limit_mode: "observed",
      dashboard_limit_mode_fallback: nil,
      dashboard_selection_state: "none",
      dashboard_time_validation: "ok",
      dashboard_runtime_resolved?: true,
      dashboard_runtime_coordinator: nil,
      dashboard_runtime_decisions: [],
      dashboard_last_runtime_invalidation: nil,
      dashboard_document_mode: "published",
      dashboard_lifecycle_status: nil,
      dashboard_summary: nil,
      dashboard_versions: [],
      dashboard_lifecycle_events: [],
      dashboard_investigation_presets: [],
      dashboard_publish_validation: nil,
      dashboard_comparison_decision_events: [],
      panel: nil,
      context_scope_kind: "spacecraft",
      context_scope_id: "sc_001",
      context_spacecraft_id: "sc_001",
      points: [],
      points_by_id: %{},
      operational_observables: [],
      selected_point_id: nil,
      selected_point_ids: [],
      widget_data: %{},
      backfills: %{},
      widget_error: nil,
      widget_form: nil,
      historical_workflow_request_form: nil,
      spacecraft: [],
      context_query: ""
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

  defp comparison_source_opts do
    %{
      telemetry: [
        latest_fun: &comparison_telemetry_sample/4,
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

  defp comparison_telemetry_sample(_organization_id, mission_id, point_id, _opts) do
    %Sample{
      sample_id: "sample-golden-canonical",
      mission_id: mission_id,
      spacecraft_id: "sc_001",
      point_id: point_id,
      point_name: point_id,
      packet_definition_id: "packet-def-1",
      packet_definition_version: 1,
      packet_id: "packet-1",
      evidence_id: "evidence-golden-canonical",
      raw_value: 5,
      engineering_value: 5,
      quality_state: :good,
      generation_time: ~U[2026-06-17 12:00:00Z],
      receipt_time: ~U[2026-06-17 12:00:01Z],
      provenance: %{}
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

  defp field_values(%Frame{fields: fields}, name) do
    fields
    |> Enum.find(&(&1.name == name))
    |> then(&(&1 && &1.values))
  end
end
