defmodule CadenceWeb.ObservabilityTest do
  use ExUnit.Case, async: true

  test "attaches full HTTP request tracing at the Bandit boundary" do
    assert handler_attached?(
             [:bandit, :request, :start],
             &OpentelemetryBandit.handle_request/4
           )
  end

  test "attaches Phoenix routing and LiveView tracing" do
    assert handler_attached?(
             [:phoenix, :router_dispatch, :start],
             &OpentelemetryPhoenix.handle_router_dispatch_start/4
           )

    assert handler_attached?(
             [:phoenix, :live_view, :mount, :start],
             &OpentelemetryPhoenix.handle_liveview_event/4
           )
  end

  defp handler_attached?(event_name, handler_function) do
    event_name
    |> :telemetry.list_handlers()
    |> Enum.any?(&(&1.function == handler_function))
  end
end
