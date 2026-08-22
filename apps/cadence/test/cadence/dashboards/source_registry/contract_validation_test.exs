defmodule Cadence.Dashboards.SourceRegistry.ContractValidationTest do
  use Cadence.UnitCase, async: true

  alias Cadence.Dashboards.{
    PlannedSourceRequest,
    SourceFacts,
    SourceResult
  }

  alias Cadence.Dashboards.SourceRegistry.ContractValidation

  test "normalizes planned requests when strict validation is disabled" do
    request =
      ContractValidation.planned_request!(
        %PlannedSourceRequest{
          request_id: "request-1",
          logical_source: "telemetry",
          observables: nil
        },
        []
      )

    assert request.logical_source == :telemetry
    assert request.observables == []
  end

  test "strict planned-request validation raises with the boundary and field path" do
    assert_raise ArgumentError,
                 ~r/dashboard planned_source_request contract violated: request_id:/,
                 fn ->
                   ContractValidation.planned_request!(
                     %PlannedSourceRequest{
                       request_id: "",
                       organization_id: "org-1",
                       mission_id: "mission-1",
                       logical_source: :telemetry
                     },
                     validate_dashboard_contract?: true
                   )
                 end
  end

  test "strict capability validation reports non-struct values" do
    assert_raise ArgumentError,
                 ~r/dashboard source_capabilities contract violated: : invalid_source_capabilities/,
                 fn ->
                   ContractValidation.capabilities!(%{}, validate_dashboard_contract?: true)
                 end
  end

  test "normalizes valid facts and strictly validates result request identity" do
    assert %SourceFacts{source_health: :healthy, meta: %{}} =
             ContractValidation.facts!(%SourceFacts{meta: nil}, [])

    assert %SourceResult{request_id: "request-1"} =
             ContractValidation.result!(
               %SourceResult{request_id: "request-1"},
               validate_dashboard_contract?: true
             )

    assert_raise ArgumentError,
                 ~r/dashboard source_result contract violated: request_id:/,
                 fn ->
                   ContractValidation.result!(
                     %SourceResult{},
                     validate_dashboard_contract?: true
                   )
                 end
  end
end
