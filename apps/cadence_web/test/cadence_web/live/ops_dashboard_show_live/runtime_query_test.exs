defmodule CadenceWeb.OpsDashboardShowLive.RuntimeQueryTest do
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

  test "falls back to default scope when contact scope is not valid" do
    context =
      RuntimeQuery.runtime_context_from_params(
        %{"scope_kind" => "contact", "scope_id" => "missing-contact"},
        scope(),
        mission(),
        [%{spacecraft_id: "sc-1"}],
        ["flight"],
        [data_binding()],
        document(),
        valid_contact?: fn _scope, _mission, _contact_id -> false end
      )

    assert %RuntimeContext{} = context
    assert context.scope_kind == "spacecraft"
    assert context.scope_id == nil
    assert ScopeContext.primary_ids(context.scope_context) == []
  end

  test "accepts source endpoint scope as a first-class runtime context" do
    context =
      RuntimeQuery.runtime_context_from_params(
        %{"scope_kind" => "source_endpoint", "scope_id" => "endpoint-alpha"},
        scope(),
        mission(),
        [%{spacecraft_id: "sc-1"}],
        ["flight"],
        [data_binding()],
        document()
      )

    assert %RuntimeContext{} = context
    assert context.scope_kind == "source_endpoint"
    assert context.scope_id == "endpoint-alpha"
    assert ScopeContext.primary_ids(context.scope_context) == ["endpoint-alpha"]
    assert ScopeContext.scope_id(context.scope_context, :source_endpoint) == "endpoint-alpha"
  end

  test "falls back to default scope when operational resource scope is not valid" do
    context =
      RuntimeQuery.runtime_context_from_params(
        %{"scope_kind" => "source_endpoint", "scope_id" => "missing-endpoint"},
        scope(),
        mission(),
        [%{spacecraft_id: "sc-1"}],
        ["flight"],
        [data_binding()],
        document(),
        valid_operational_resource_scope?: fn _scope, _mission, scope_kind, scope_id ->
          scope_kind == "source_endpoint" and scope_id == "endpoint-alpha"
        end
      )

    assert %RuntimeContext{} = context
    assert context.scope_kind == "spacecraft"
    assert context.scope_id == nil
    assert ScopeContext.primary_ids(context.scope_context) == []
  end

  test "accepts durable multi-select scope ids from URL params" do
    context =
      RuntimeQuery.runtime_context_from_params(
        %{
          "scope_kind" => "source_endpoint",
          "scope_ids" => "endpoint-alpha, endpoint-beta"
        },
        scope(),
        mission(),
        [%{spacecraft_id: "sc-1"}],
        ["flight"],
        [data_binding()],
        document()
      )

    assert %RuntimeContext{} = context
    assert context.scope_kind == "source_endpoint"
    assert context.scope_id == "endpoint-alpha"
    assert context.scope_ids == ["endpoint-alpha", "endpoint-beta"]
    assert ScopeContext.primary_ids(context.scope_context) == ["endpoint-alpha", "endpoint-beta"]
    assert context.scope_context.primary.mode == "many"
  end

  test "requires every operational resource scope id to pass caller validation" do
    context =
      RuntimeQuery.runtime_context_from_params(
        %{
          "scope_kind" => "transport",
          "scope_ids" => "transport-alpha,transport-missing"
        },
        scope(),
        mission(),
        [%{spacecraft_id: "sc-1"}],
        ["flight"],
        [data_binding()],
        document(),
        valid_operational_resource_scope?: fn _scope, _mission, scope_kind, scope_id ->
          scope_kind == "transport" and scope_id == "transport-alpha"
        end
      )

    assert %RuntimeContext{} = context
    assert context.scope_kind == "spacecraft"
    assert context.scope_id == nil
    assert context.scope_ids == []
    assert ScopeContext.primary_ids(context.scope_context) == []
  end

  test "uses document scope defaults when URL does not provide scope" do
    document = %Document{
      defaults: %{
        "scope" => %{
          "primary" => %{"kind" => "spacecraft", "mode" => "many", "ids" => ["sc-1", "sc-2"]}
        }
      }
    }

    context =
      RuntimeQuery.runtime_context_from_params(
        %{},
        scope(),
        mission(),
        [%{spacecraft_id: "sc-1"}, %{spacecraft_id: "sc-2"}],
        ["flight"],
        [data_binding()],
        document
      )

    assert context.scope_kind == "spacecraft"
    assert context.scope_id == "sc-1"
    assert context.scope_ids == ["sc-1", "sc-2"]
    assert context.spacecraft_id == nil
    assert ScopeContext.primary_ids(context.scope_context) == ["sc-1", "sc-2"]
  end

  test "URL scope takes precedence over document scope defaults" do
    document = %Document{
      defaults: %{
        "scope" => %{
          "primary" => %{"kind" => "spacecraft", "mode" => "many", "ids" => ["sc-1", "sc-2"]}
        }
      }
    }

    context =
      RuntimeQuery.runtime_context_from_params(
        %{"scope_kind" => "source_endpoint", "scope_id" => "endpoint-alpha"},
        scope(),
        mission(),
        [%{spacecraft_id: "sc-1"}, %{spacecraft_id: "sc-2"}],
        ["flight"],
        [data_binding()],
        document
      )

    assert context.scope_kind == "source_endpoint"
    assert context.scope_id == "endpoint-alpha"
    assert ScopeContext.primary_ids(context.scope_context) == ["endpoint-alpha"]
  end

  test "normalizes runtime query to selected active source binding" do
    slow_binding =
      data_binding(%{
        binding_id: "rehearsal-slow",
        data_source_id: "questdb-rehearsal",
        realm: :rehearsal,
        priority: 10
      })

    fast_binding =
      data_binding(%{
        binding_id: "rehearsal-fast",
        data_source_id: "questdb-rehearsal",
        realm: :rehearsal,
        priority: 1
      })

    assert RuntimeQuery.normalize_runtime_query(
             %{
               "realm" => "rehearsal",
               "data_source_id" => "questdb-rehearsal",
               "data_view" => "all_revisions",
               "compare_data_view" => "canonical"
             },
             ["flight", "rehearsal"],
             [data_binding(), slow_binding, fast_binding],
             document()
           ) == %{
             "time_mode" => nil,
             "time_axis" => nil,
             "from" => nil,
             "to" => nil,
             "replay_run_id" => nil,
             "realm" => "rehearsal",
             "data_view" => "all_revisions",
             "compare_data_view" => "canonical",
             "data_source_id" => "questdb-rehearsal",
             "source_binding_id" => "rehearsal-fast",
             "limit_mode" => nil
           }
  end

  test "normalizes data-view comparison only when it differs from the active view" do
    assert %{compare_data_view: "all_revisions"} =
             RuntimeQuery.runtime_context_from_params(
               %{"data_view" => "canonical", "compare_data_view" => "all_revisions"},
               scope(),
               mission(),
               [%{spacecraft_id: "sc-1"}],
               ["flight"],
               [data_binding()],
               document()
             )

    assert %{compare_data_view: nil} =
             RuntimeQuery.runtime_context_from_params(
               %{"data_view" => "canonical", "compare_data_view" => "canonical"},
               scope(),
               mission(),
               [%{spacecraft_id: "sc-1"}],
               ["flight"],
               [data_binding()],
               document()
             )

    assert %{compare_data_view: nil} =
             RuntimeQuery.runtime_context_from_params(
               %{"data_view" => "canonical", "compare_data_view" => "unsupported"},
               scope(),
               mission(),
               [%{spacecraft_id: "sc-1"}],
               ["flight"],
               [data_binding()],
               document()
             )
  end

  test "accepts supported limit semantics modes into runtime context" do
    for limit_mode <- ["observed", "current", "recomputed", "compare"] do
      assert %{limit_mode: ^limit_mode, limit_context: %{"semantics_mode" => ^limit_mode}} =
               RuntimeQuery.runtime_context_from_params(
                 %{"limit_mode" => limit_mode},
                 scope(),
                 mission(),
                 [%{spacecraft_id: "sc-1"}],
                 ["flight"],
                 [data_binding()],
                 document()
               )
    end
  end

  test "records unsupported limit mode fallback metadata without changing engine semantics" do
    context =
      RuntimeQuery.runtime_context_from_params(
        %{"limit_mode" => "projected"},
        scope(),
        mission(),
        [%{spacecraft_id: "sc-1"}],
        ["flight"],
        [data_binding()],
        document()
      )

    assert %{limit_mode: "observed", limit_context: %{"semantics_mode" => "observed"}} =
             context

    assert context.limit_mode_fallback == %{
             "requested_mode" => "projected",
             "applied_mode" => "observed",
             "reason" => "unsupported_limit_semantics_mode",
             "supported_modes" => ["observed", "current", "recomputed", "compare"]
           }
  end

  test "normalizes non-default supported limit semantics mode" do
    assert %{"limit_mode" => "recomputed"} =
             RuntimeQuery.normalize_runtime_query(
               %{"limit_mode" => "recomputed"},
               ["flight"],
               [data_binding()],
               document()
             )

    assert %{"limit_mode" => nil} =
             RuntimeQuery.normalize_runtime_query(
               %{"limit_mode" => "observed"},
               ["flight"],
               [data_binding()],
               document()
             )
  end

  test "normalizes primary source binding override against document defaults" do
    assert RuntimeQuery.normalize_runtime_query(
             %{"source_binding_id" => "primary"},
             ["flight"],
             [data_binding()],
             document()
           ) == %{
             "time_mode" => nil,
             "time_axis" => nil,
             "from" => nil,
             "to" => nil,
             "replay_run_id" => nil,
             "realm" => nil,
             "data_view" => nil,
             "compare_data_view" => nil,
             "data_source_id" => nil,
             "source_binding_id" => "primary",
             "limit_mode" => nil
           }
  end

  test "stringifies document data defaults for runtime default comparison" do
    assert RuntimeQuery.document_data_defaults(%Document{
             defaults: %{
               data: %{
                 realm: "rehearsal",
                 source_mode: "specific",
                 source_contexts: %{
                   telemetry: %{source_binding_id: "rehearsal-binding"}
                 }
               }
             }
           }) == %{
             "realm" => "rehearsal",
             "source_mode" => "specific",
             "source_contexts" => %{
               "telemetry" => %{"source_binding_id" => "rehearsal-binding"}
             }
           }
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
