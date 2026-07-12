defmodule CadenceWeb.OpsDashboardShowLive.RuntimeQueryReplayTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{DataBinding, Document, ScopeContext}
  alias CadenceWeb.OpsDashboardShowLive.RuntimeContext
  alias CadenceWeb.OpsDashboardShowLive.RuntimeQuery

  test "builds replay runtime context with contact scope and source binding context" do
    replay_binding =
      data_binding(%{
        binding_id: "replay-binding",
        data_source_id: "questdb-replay",
        dataset: "replay-run",
        realm: :replay
      })

    context =
      RuntimeQuery.runtime_context_from_params(
        %{
          "scope_kind" => "contact",
          "scope_id" => "contact-1",
          "time_mode" => "replay_run",
          "replay_run_id" => "replay-run-1",
          "source_binding_id" => "replay-binding"
        },
        scope(),
        mission(),
        [%{spacecraft_id: "sc-1"}],
        ["flight", "replay"],
        [data_binding(), replay_binding],
        document(),
        valid_contact?: fn _scope, _mission, contact_id -> contact_id == "contact-1" end
      )

    assert %RuntimeContext{} = context
    assert context.scope_kind == "contact"
    assert context.scope_id == "contact-1"
    assert ScopeContext.primary_ids(context.scope_context) == ["contact-1"]
    assert context.spacecraft_id == nil
    assert context.time_mode == "replay_run"
    assert context.replay_run_id == "replay-run-1"

    assert context.time_context == %{
             "mode" => "replay_run",
             "axis" => "generation_time",
             "replay_run_id" => "replay-run-1"
           }

    assert context.realm == "replay"
    assert context.data_source_id == "questdb-replay"
    assert context.source_binding_id == "replay-binding"
    assert context.data_context["replay_run_id"] == "replay-run-1"

    assert get_in(context.data_context, [
             "source_contexts",
             "telemetry",
             "source_binding_id"
           ]) == "replay-binding"
  end

  test "preserves document default source contexts for non-telemetry replay sources" do
    document = %Document{
      defaults: %{
        "data" => %{
          "realm" => "replay",
          "source_mode" => "specific",
          "source_contexts" => %{
            "events" => %{"source_binding_id" => "replay-events"},
            "operational_observables" => %{
              "source_binding_id" => "replay-operational-observables"
            }
          }
        }
      }
    }

    context =
      RuntimeQuery.runtime_context_from_params(
        %{"time_mode" => "replay_run", "replay_run_id" => "replay-run-1"},
        scope(),
        mission(),
        [%{spacecraft_id: "sc-1"}],
        ["flight", "replay"],
        [data_binding()],
        document
      )

    assert context.realm == "replay"
    assert context.time_mode == "replay_run"
    assert context.replay_run_id == "replay-run-1"
    assert context.data_context["source_mode"] == "specific"

    assert get_in(context.data_context, [
             "source_contexts",
             "events",
             "source_binding_id"
           ]) == "replay-events"

    assert get_in(context.data_context, [
             "source_contexts",
             "operational_observables",
             "source_binding_id"
           ]) == "replay-operational-observables"
  end

  defp scope do
    %{organization_id: "org-1"}
  end

  defp mission do
    %{mission_id: "mission-1"}
  end

  defp document do
    %Document{
      defaults: %{
        "data" => %{
          "realm" => "flight",
          "source_mode" => "specific",
          "source_contexts" => %{
            "telemetry" => %{
              "source_binding_id" => "flight-binding"
            }
          },
          "view" => "canonical"
        }
      }
    }
  end

  defp data_binding(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        binding_id: "flight-binding",
        data_source_id: "questdb-flight",
        dataset: "flight",
        realm: :flight,
        logical_source: :telemetry,
        priority: 0,
        status: :active
      })

    struct!(DataBinding, attrs)
  end
end
