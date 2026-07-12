defmodule CadenceWeb.OpsDashboardShowLive.GoldenContractOperationalStaleWarningTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DataSources,
    Document,
    Engine,
    Frame,
    PlacementFrames,
    RenderItem,
    ResolveWarning
  }

  alias CadenceWeb.OpsDashboardShowLive.WidgetPresentation

  @fixture_dir Path.expand("../../../../../cadence/test/fixtures/dashboards", __DIR__)
  @optional_link_context_paths [
    logical_source: [:logical_source],
    observable_id: [:observable_id],
    scope_kind: [:scope, :primary, :kind],
    time_mode: [:time, :mode],
    time_axis: [:time, :axis],
    realm: [:data, :realm],
    data_source_id: [:data, :data_source_id],
    source_binding_id: [:data, :source_binding_id]
  ]

  test "golden stale operational fixture carries warning through presenter lifecycle" do
    document = load_fixture!("stale_operational_warning.v1.json")

    assert %Dashboards.ValidationResult{valid?: true, errors: []} =
             Dashboards.validate_document(document)

    result =
      Engine.resolve(
        resolve_request(document, %{"placement_command_queue" => %{width_px: 320}}),
        operational_source_registry_opts(
          source_opts: stale_operational_source_opts(),
          freshness_now: ~U[2026-06-17 12:05:02Z],
          validate_dashboard_contract?: true
        )
      )

    assert result.plan_metadata.degraded?

    assert [%ResolveWarning{code: :stale_data, severity: :warning, scope: :dashboard} = warning] =
             result.dashboard_warnings

    assert warning.details.supported_capability == :command_queue_depth
    assert warning.details.observable_ids == ["commanding.queue_depth"]
    assert Enum.map(warning.details.actions, & &1.target) == [:source_health, :source_inventory]
    assert link_targets(warning) == [:telemetry_point]

    assert %{
             "placement_command_queue" =>
               %PlacementFrames{
                 primary: [
                   %Frame{
                     source: :operational_observables,
                     shape: :matrix,
                     meta: %{
                       supported_capability: :command_queue_depth,
                       warning_codes: [:stale_data],
                       freshness_policy: %{stale_after_ms: 1_000},
                       freshness_checked_at: ~U[2026-06-17 12:05:02Z]
                     }
                   } = frame
                 ],
                 warnings: [
                   %ResolveWarning{
                     code: :stale_data,
                     severity: :warning,
                     scope: :placement,
                     placement_id: "placement_command_queue"
                   }
                 ]
               } = placement_frames
           } = result.frames_by_placement

    assert field_values(frame, "observable_id") == ["commanding.queue_depth"]
    assert field_values(frame, "value") == [0]
    assert field_values(frame, "freshness_state") == [:stale]
    assert field_values(frame, "age_ms") == [2_000]

    assert_link_runtime_context(link_by_target(warning, :telemetry_point),
      logical_source: "operational_observables",
      observable_id: "commanding.queue_depth",
      scope_kind: "spacecraft",
      scope_id: "sc_001",
      time_mode: "live",
      time_axis: "generation_time",
      realm: "flight",
      data_source_id: "managed_operational_observables",
      source_binding_id: "default_flight_operational_observables"
    )

    [render_item] = RenderItem.from_document(document)
    data = WidgetPresentation.data(nil, placement_frames, render_item.widget)

    assert data.lifecycle_state == :stale
    assert data.lifecycle.state == :stale
    assert data.lifecycle.warning_codes == [:stale_data]
    assert data.sample.engineering_value == 0
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

  defp operational_source_registry_opts(opts) do
    Keyword.merge(
      [
        source_health_events?: false,
        source_watermark_events?: false,
        data_sources: [
          DataSources.default_operational_observables_data_source()
        ],
        data_bindings: [
          DataSources.default_flight_operational_observables_binding()
        ]
      ],
      opts
    )
  end

  defp stale_operational_source_opts do
    %{
      operational_observables: [
        command_queue_entries_fun: fn _organization_id, _mission_id, _opts -> [] end,
        read_time: ~U[2026-06-17 12:05:00Z]
      ]
    }
  end

  defp field_values(%Frame{fields: fields}, name) do
    fields
    |> Enum.find(&(&1.name == name))
    |> then(&(&1 && &1.values))
  end

  defp link_targets(%ResolveWarning{links: links}) do
    Enum.map(links, & &1.target)
  end

  defp link_by_target(%ResolveWarning{links: links}, target) do
    Enum.find(links, &(&1.target == target))
  end

  defp assert_link_runtime_context(link, opts) do
    refute is_nil(link)

    assert_context_texts(link, [
      {[:organization_id], "org_dashboards"},
      {[:mission_id], "mission_dashboards"}
    ])

    assert_context_texts(link, optional_context_texts(opts))

    assert context_value(link.context, [:scope, :primary, :ids]) == [
             Keyword.fetch!(opts, :scope_id)
           ]
  end

  defp optional_context_texts(opts) do
    for {key, path} <- @optional_link_context_paths,
        expected = Keyword.get(opts, key),
        not is_nil(expected),
        do: {path, expected}
  end

  defp assert_context_texts(link, expected_values) do
    Enum.each(expected_values, fn {path, expected} ->
      assert context_text(context_value(link.context, path)) == expected
    end)
  end

  defp context_value(context, path) when is_map(context) and is_list(path) do
    Enum.reduce(path, context, fn key, acc ->
      case acc do
        %{} -> Map.get(acc, key, Map.get(acc, Atom.to_string(key)))
        _other -> nil
      end
    end)
  end

  defp context_text(nil), do: nil
  defp context_text(value) when is_atom(value), do: Atom.to_string(value)
  defp context_text(value) when is_binary(value), do: value
end
