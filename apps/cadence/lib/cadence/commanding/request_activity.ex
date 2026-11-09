defmodule Cadence.Commanding.RequestActivity do
  @moduledoc "Which source endpoints have ever had command requests (spacecraft traffic, #49/#50)."

  import Ecto.Query

  alias Cadence.Commanding.CommandRequestRow
  alias Cadence.Repo

  @spec endpoints_with_requests(binary(), binary(), [binary()]) :: MapSet.t()
  def endpoints_with_requests(_organization_id, _mission_id, []), do: MapSet.new()

  def endpoints_with_requests(organization_id, mission_id, endpoint_refs) do
    CommandRequestRow
    |> where(
      [r],
      r.organization_id == ^organization_id and r.mission_id == ^mission_id and
        r.source_endpoint_ref in ^endpoint_refs
    )
    |> distinct(true)
    |> select([r], r.source_endpoint_ref)
    |> Repo.all()
    |> MapSet.new()
  end
end
