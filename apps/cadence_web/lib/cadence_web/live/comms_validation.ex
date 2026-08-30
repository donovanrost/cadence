defmodule CadenceWeb.CommsValidation do
  @moduledoc "Legacy web adapter for the core-owned bounded Comms validation model."

  alias Cadence.Auth.Scope
  alias Cadence.Reads.ApplicationSurfaces.Comms, as: CommsRead

  @spec findings_for_mission(Scope.t(), binary()) :: [map()]
  def findings_for_mission(%Scope{} = scope, mission_id) do
    case CommsRead.validation(scope, mission_id) do
      {:ok, findings} -> findings
      {:error, _reason} -> []
    end
  end

  @spec finding_groups([map()]) :: [map()]
  def finding_groups(findings) when is_list(findings), do: CommsRead.finding_groups(findings)

  @spec finding_label(atom()) :: binary()
  def finding_label(value), do: CommsRead.finding_label(value)
end
