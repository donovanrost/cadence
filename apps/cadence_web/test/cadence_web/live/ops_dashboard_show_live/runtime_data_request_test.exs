defmodule CadenceWeb.OpsDashboardShowLive.RuntimeDataRequestTest do
  use ExUnit.Case, async: true

  alias Cadence.Dashboards.{
    DashboardResolveRequest,
    DataContext,
    Document,
    LimitContext,
    ScopeContext,
    TimeContext
  }

  alias CadenceWeb.OpsDashboardShowLive.RuntimeDataRequest

  test "builds from LiveView assigns" do
    request =
      RuntimeDataRequest.from_assigns(
        assigns(%{
          dashboard_document_mode: :published,
          dashboard_scope_context: %{"primary" => %{"kind" => "mission", "ids" => ["mission-1"]}},
          dashboard_time_context: %{"mode" => "archive"},
          dashboard_data_context: %{"realm" => "flight"},
          dashboard_limit_context: %{"semantics_mode" => "observed"}
        }),
        :context_change
      )

    assert %RuntimeDataRequest{} = request
    assert request.organization_id == "org-1"
    assert request.mission_id == "mission-1"
    assert request.dashboard_id == "dashboard-1"
    assert request.document_mode == :published
    assert request.resolve_mode == :context_change
    assert request.scope_context == %{"primary" => %{"kind" => "mission", "ids" => ["mission-1"]}}
    assert request.time_context == %{"mode" => "archive"}
    assert request.data_context == %{"realm" => "flight"}
    assert request.limit_context == %{"semantics_mode" => "observed"}
  end

  test "projects to the core dashboard engine request" do
    engine_request =
      RuntimeDataRequest.new(%{
        organization_id: "org-1",
        mission_id: "mission-1",
        dashboard_id: "dashboard-1",
        document: document(),
        document_mode: "draft-preview",
        resolve_mode: "live-tick",
        scope_context: %{
          "primary" => %{"kind" => "spacecraft", "mode" => "one", "ids" => ["sc-1"]}
        },
        time_context: %{"mode" => "live", "axis" => "generation_time"},
        data_context: %{"realm" => "flight"},
        limit_context: %{"semantics_mode" => "observed"}
      })
      |> RuntimeDataRequest.to_engine_request()

    assert %DashboardResolveRequest{} = engine_request
    assert engine_request.organization_id == "org-1"
    assert engine_request.document_mode == :draft_preview
    assert engine_request.resolve_mode == :live_tick
    assert %ScopeContext{} = engine_request.scope_context
    assert %TimeContext{} = engine_request.time_context
    assert %DataContext{} = engine_request.data_context
    assert %LimitContext{} = engine_request.limit_context
  end

  test "constructs only known request fields" do
    request =
      RuntimeDataRequest.new(%{
        "organization_id" => "org-1",
        "unknown" => "ignored",
        mission_id: "mission-1"
      })

    assert %RuntimeDataRequest{} = request
    assert request.organization_id == "org-1"
    assert request.mission_id == "mission-1"
    refute Map.has_key?(request, :unknown)
  end

  defp assigns(overrides) do
    Map.merge(
      %{
        current_scope: %{organization_id: "org-1"},
        current_mission: %{mission_id: "mission-1"},
        dashboard_document: document(),
        dashboard_document_mode: :draft,
        dashboard_scope_context: %{},
        dashboard_time_context: %{},
        dashboard_data_context: %{},
        dashboard_limit_context: %{}
      },
      overrides
    )
  end

  defp document do
    %Document{
      dashboard_id: "dashboard-1",
      organization_id: "org-1",
      mission_id: "mission-1",
      name: "Ops dashboard",
      placements: []
    }
  end
end
