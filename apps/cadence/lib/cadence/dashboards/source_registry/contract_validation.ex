defmodule Cadence.Dashboards.SourceRegistry.ContractValidation do
  @moduledoc """
  Normalizes source contracts and optionally enforces strict dashboard validation.
  """

  alias Cadence.Dashboards.{
    DashboardContract,
    PlannedSourceRequest,
    SourceCapabilities,
    SourceFacts,
    SourceResult
  }

  @spec planned_request!(PlannedSourceRequest.t(), keyword()) :: PlannedSourceRequest.t()
  def planned_request!(%PlannedSourceRequest{} = request, opts) when is_list(opts) do
    request = PlannedSourceRequest.normalize(request)

    if strict?(opts) do
      request
      |> DashboardContract.validate_planned_source_request()
      |> raise_violations!(:planned_source_request)
    end

    request
  end

  @spec capabilities!(term(), keyword()) :: term()
  def capabilities!(%SourceCapabilities{} = capabilities, opts) when is_list(opts) do
    capabilities = SourceCapabilities.normalize(capabilities)

    if strict?(opts) do
      capabilities
      |> DashboardContract.validate_source_capabilities()
      |> raise_violations!(:source_capabilities)
    end

    capabilities
  end

  def capabilities!(other, opts) when is_list(opts) do
    if strict?(opts) do
      other
      |> DashboardContract.validate_source_capabilities()
      |> raise_violations!(:source_capabilities)
    end

    other
  end

  @spec facts!(SourceFacts.t(), keyword()) :: SourceFacts.t()
  def facts!(%SourceFacts{} = facts, opts) when is_list(opts) do
    facts = SourceFacts.normalize(facts)

    if strict?(opts) do
      facts
      |> DashboardContract.validate_source_facts()
      |> raise_violations!(:source_facts)
    end

    facts
  end

  @spec result!(SourceResult.t(), keyword()) :: SourceResult.t()
  def result!(%SourceResult{} = result, opts) when is_list(opts) do
    result = SourceResult.normalize(result)

    if strict?(opts) do
      result
      |> DashboardContract.validate_source_result()
      |> raise_violations!(:source_result)
    end

    result
  end

  defp strict?(opts),
    do: Keyword.get(opts, :validate_dashboard_contract?, false) == true

  defp raise_violations!(:ok, _boundary), do: :ok

  defp raise_violations!({:error, violations}, boundary) do
    raise ArgumentError,
          "dashboard #{boundary} contract violated: " <> format_violations(violations)
  end

  defp format_violations(violations) do
    Enum.map_join(violations, "; ", fn violation ->
      path =
        violation
        |> Map.get(:path, [])
        |> Enum.map_join(".", &to_string/1)

      "#{path}: #{Map.get(violation, :code)}"
    end)
  end
end
