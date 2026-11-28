defmodule Cadence.Reads.RevisionsInUse do
  @moduledoc """
  The model revisions a mission's spacecraft are running (#451, after M): each craft runs the head
  revision of its composition, so a mission can run several at once. `MissionModels.revision_at/4`
  and `revisions_at/3` answer it from the generation receipts (one statement each, however many
  spacecraft); a mission whose activation has no fleet assignments (one model for everything) has
  its activation's revision.

    * `of_spacecraft/4`: the revision one craft runs, or nil.
    * `all/3`: `%{revision_id => [spacecraft_id] | :all}`; `:all` for the single-model fallback.
  """

  alias Cadence.MissionModels
  alias Cadence.Reads.MissionModels.ActiveBasis

  @doc "The revision `spacecraft_id` runs at `at` (default now), or nil."
  @spec of_spacecraft(binary(), binary(), binary(), DateTime.t() | nil) :: binary() | nil
  def of_spacecraft(organization_id, mission_id, spacecraft_id, at \\ nil) do
    MissionModels.revision_at(
      organization_id,
      mission_id,
      spacecraft_id,
      at || DateTime.utc_now()
    ) ||
      ActiveBasis.active_revision_id(organization_id, mission_id)
  end

  @doc "The revisions in use at `at` (default now) with the spacecraft on each."
  @spec all(binary(), binary(), DateTime.t() | nil) :: %{binary() => [binary()] | :all}
  def all(organization_id, mission_id, at \\ nil) do
    case MissionModels.revisions_at(organization_id, mission_id, at || DateTime.utc_now()) do
      assignments when map_size(assignments) > 0 ->
        assignments

      _no_fleet_assignments ->
        case ActiveBasis.active_revision_id(organization_id, mission_id) do
          nil -> %{}
          revision_id -> %{revision_id => :all}
        end
    end
  end
end
