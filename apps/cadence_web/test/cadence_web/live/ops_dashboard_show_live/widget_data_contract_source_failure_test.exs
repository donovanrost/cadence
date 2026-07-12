defmodule CadenceWeb.OpsDashboardShowLive.WidgetDataContractSourceFailureTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{PlacementFrames, RenderWidget, ResolveWarning}
  alias CadenceWeb.OpsDashboardShowLive.WidgetPresentation

  test "time series source failures retain point-shaped widget contract" do
    for {warning_code, lifecycle_state} <- [
          unsupported_source_capability: :unsupported,
          source_unavailable: :error,
          source_execution_failed: :error
        ] do
      data =
        WidgetPresentation.data(
          nil,
          source_failure_frames(warning_code),
          render_widget(:time_series)
        )

      assert %{
               kind: :point,
               sample: nil,
               limit_event: nil,
               links: [],
               lifecycle_state: ^lifecycle_state,
               stale?: false,
               unresolved?: false,
               engine_backed?: true,
               source_status: %{warning_codes: [^warning_code]}
             } = data

      assert %{state: ^lifecycle_state, severity: :error, warning_codes: [^warning_code]} =
               data.lifecycle
    end
  end

  test "context-bound widgets preserve source failure lifecycle without primary frames" do
    data =
      WidgetPresentation.data(
        nil,
        source_failure_frames(:unsupported_widget_frame_contract),
        %RenderWidget{
          type: :time_series,
          binding: %{source: :operational_observables, mode: :context}
        }
      )

    assert %{
             kind: :point,
             sample: nil,
             lifecycle_state: :unsupported,
             unresolved?: false,
             engine_backed?: true,
             source_status: %{
               state: :no_data,
               data_state: :no_data,
               warning_codes: [:unsupported_widget_frame_contract]
             }
           } = data

    assert %{state: :unsupported, severity: :error} = data.lifecycle
  end

  test "context-bound value tiles preserve retention gap lifecycle without primary frames" do
    data =
      WidgetPresentation.data(
        nil,
        source_failure_frames(:retention_gap, severity: :warning),
        %RenderWidget{
          type: :value_tile,
          binding: %{source: :telemetry, mode: :context}
        }
      )

    assert %{
             kind: :point,
             sample: nil,
             lifecycle_state: :retention_gap,
             unresolved?: false,
             engine_backed?: true,
             source_status: %{
               state: :retention_gap,
               severity: :error,
               warning_codes: [:retention_gap]
             }
           } = data

    assert %{state: :retention_gap, severity: :error, warning_codes: [:retention_gap]} =
             data.lifecycle
  end

  defp source_failure_frames(warning_code, opts \\ []) do
    %PlacementFrames{
      warnings: [
        %ResolveWarning{
          code: warning_code,
          severity: Keyword.get(opts, :severity, :error),
          message: Atom.to_string(warning_code)
        }
      ]
    }
  end

  defp render_widget(widget_type) do
    %RenderWidget{
      type: widget_type,
      binding: %{source: :telemetry, mode: :fixed}
    }
  end
end
