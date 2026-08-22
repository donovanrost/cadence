defmodule CadenceWeb.OpsDashboardShowLive.RuntimeQueryScopeTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{Document, ScopeContext}

  alias Cadence.DataSources.DataBinding
  alias CadenceWeb.OpsDashboardShowLive.RuntimeContext
  alias CadenceWeb.OpsDashboardShowLive.RuntimeQuery

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

  test "validates explicit mission scope before legacy spacecraft fallback" do
    valid_context =
      RuntimeQuery.runtime_context_from_params(
        %{"scope_kind" => "mission", "scope_id" => "mission-1"},
        scope(),
        mission(),
        [%{spacecraft_id: "sc-1"}],
        ["flight"],
        [data_binding()],
        document()
      )

    assert valid_context.scope_kind == "mission"
    assert valid_context.scope_id == "mission-1"
    assert ScopeContext.primary_ids(valid_context.scope_context) == ["mission-1"]

    invalid_context =
      RuntimeQuery.runtime_context_from_params(
        %{
          "scope_kind" => "mission",
          "scope_id" => "other-mission",
          "spacecraft_id" => "sc-1"
        },
        scope(),
        mission(),
        [%{spacecraft_id: "sc-1"}],
        ["flight"],
        [data_binding()],
        document()
      )

    assert invalid_context.scope_kind == "spacecraft"
    assert invalid_context.scope_id == nil
    assert invalid_context.scope_ids == []
    assert ScopeContext.primary_ids(invalid_context.scope_context) == []
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
