defmodule Cadence.Reads.MissionRuntimeStatus do
  @moduledoc """
  The `runtime` key of `/missions/:id/counts` (ux U38: the mission-wide banner) and the source
  of the `mission_runtime` attention item: whether the mission's runtime has applied its active
  generation. A recorded-snapshot lookup (`Cadence.Control.MissionRuntimeStatus`), cheap and
  non-blocking; `nil` when it can't tell.

  `%{state: "not_applied" | "applied", reason, failure_message, desired_generation,
  applied_generation, since, applied_at, activated_at, change_set_id}`; `reason` is one of
  `Cadence.Control.MissionRuntimeStatus.reasons/0` or nil.
  """

  alias Cadence.Control.MissionRuntimeStatus

  @spec status(binary(), binary()) :: map() | nil
  def status(organization_id, mission_id)
      when is_binary(organization_id) and is_binary(mission_id),
      do: MissionRuntimeStatus.status(mission_id)
end
