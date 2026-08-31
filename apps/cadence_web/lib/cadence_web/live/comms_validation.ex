defmodule CadenceWeb.CommsValidation do
  @moduledoc "Legacy web adapter for the core-owned bounded Comms validation model."

  alias Cadence.Auth.Scope
  alias Cadence.Reads.ApplicationSurfaces.Comms, as: CommsRead

  @spec findings_for_mission(Scope.t(), binary()) :: {:ok, [map()]} | {:error, term()}
  def findings_for_mission(%Scope{} = scope, mission_id),
    do: CommsRead.validation(scope, mission_id)

  @spec unavailable_finding() :: map()
  def unavailable_finding do
    %{
      id: "comms-validation-unavailable",
      owner: :advanced_runtime_identity,
      severity: :blocked,
      title: "Validation unavailable",
      body: "Cadence could not safely evaluate the saved communications configuration."
    }
  end

  @spec finding_groups([map()]) :: [map()]
  def finding_groups(findings) when is_list(findings), do: CommsRead.finding_groups(findings)

  @spec finding_label(atom()) :: binary()
  def finding_label(value), do: CommsRead.finding_label(value)
end
