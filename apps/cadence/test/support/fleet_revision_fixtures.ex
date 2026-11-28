defmodule Cadence.FleetRevisionFixtures do
  @moduledoc """
  A fleet whose spacecraft run different model revisions, as `MissionModels.revision_at/4` and
  `revisions_at/3` read it (the generation's fleet snapshot and its runtime receipt): one
  composition per revision, `assign!/5` makes a generation effective from a receipt time.
  """

  alias Cadence.Activations.{BindingSetActivation, BindingSetActivationRow}
  alias Cadence.Catalog.{FleetSnapshot, SpacecraftConfigurationInput}
  alias Cadence.Repo

  @doc """
  Activates generation `generation` of the mission with `assignments` (`%{spacecraft_id =>
  revision_id}`) and records its runtime receipt at `received_at`.
  """
  @spec assign!(binary(), binary(), pos_integer(), %{binary() => binary()}, DateTime.t()) ::
          BindingSetActivation.t()
  def assign!(organization_id, mission_id, generation, assignments, received_at) do
    entries = Map.new(assignments, fn {id, revision} -> {id, entry(id, revision)} end)
    {:ok, fleet} = FleetSnapshot.store(mission_id, entries)

    activation =
      %{
        organization_id: organization_id,
        mission_id: mission_id,
        binding_set_id: "fleet-revisions",
        binding_set_version: generation,
        activated_at: DateTime.add(received_at, -1, :microsecond),
        generation: generation,
        metadata: FleetSnapshot.metadata(fleet, %{})
      }
      |> BindingSetActivation.new()
      |> BindingSetActivationRow.changeset()
      |> Repo.insert!()

    receipt =
      activation
      |> Map.take([
        :organization_id,
        :mission_id,
        :activation_id,
        :generation,
        :binding_set_id,
        :binding_set_version
      ])
      |> Map.put(:applied_at, DateTime.to_naive(received_at))

    {1, nil} = Repo.insert_all("mission_generation_receipts", [receipt])
    activation
  end

  defp entry(id, revision) do
    %{
      "catalog_revision_id" => "catalog",
      "commanding_enabled" => false,
      "document" => %{SpacecraftConfigurationInput.empty() | "catalog_revision_id" => "catalog"},
      "mission_model" => %{"revision_id" => revision},
      "source_endpoint_ids" => ["source-#{id}"]
    }
  end
end
