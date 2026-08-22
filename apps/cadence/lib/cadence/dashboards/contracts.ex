defmodule Cadence.Dashboards.Contracts do
  @moduledoc "Public validation boundary for dashboard documents and runtime contracts."

  alias Cadence.DataSources.SourceCapabilities

  alias Cadence.Dashboards.{
    DashboardContract,
    DashboardResolveRequest,
    DashboardResolveResult,
    Document,
    PlannedSourceRequest,
    PublishReadiness,
    SourceFacts,
    SourceResult
  }

  def validate_document(%Document{} = document), do: Document.validate(document)

  def validate_publish_readiness(organization_id, mission_id, %Document{} = document, opts \\ []) do
    PublishReadiness.validate(organization_id, mission_id, document, opts)
  end

  def validate_request(%DashboardResolveRequest{} = request),
    do: DashboardContract.validate_request(request)

  def validate_plan_result(%DashboardResolveResult{} = result),
    do: DashboardContract.validate_plan_result(result)

  def validate_resolve_result(%DashboardResolveResult{} = result),
    do: DashboardContract.validate_resolve_result(result)

  def validate_source_capabilities(%SourceCapabilities{} = capabilities),
    do: DashboardContract.validate_source_capabilities(capabilities)

  def validate_source_facts(%SourceFacts{} = facts),
    do: DashboardContract.validate_source_facts(facts)

  def validate_source_result(%SourceResult{} = result),
    do: DashboardContract.validate_source_result(result)

  def validate_planned_source_request(%PlannedSourceRequest{} = request),
    do: DashboardContract.validate_planned_source_request(request)
end
