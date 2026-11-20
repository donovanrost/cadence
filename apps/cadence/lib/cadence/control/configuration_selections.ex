defmodule Cadence.Control.ConfigurationSelections do
  @moduledoc """
  D3 (#544; design §3): which revision each pinned composition runs in a generation, recorded at
  submit and selected again at apply.

  - `for_catalogs/3` maps the generation's derived catalogs to their one-layer compositions and
    `Selection.select/3`'s answer: `%{composition_id => revision_id | "not_approved" |
    "reapproval_needed"}`. A catalog revision with no composition (a shape D1's backfill skipped)
    adds nothing; the activation gate's per-revision check still applies to it.
  - `check/4` runs under the activation lock (api-ops): it holds the selected revision rows
    `FOR SHARE`, selects again, and compares with what the submit recorded. Any difference
    (a newer approval in between, the recorded revision withdrawn or unrunnable) refuses
    `{:restage_needed, entries}` and nothing is written. A set recorded before D3 recorded
    nothing, so it's refused whenever its apply would select anything (#112: no shim).
  """

  import Ecto.Query

  alias Cadence.MissionModels
  alias Cadence.MissionModels.{CatalogPins, Selection}
  alias Cadence.Repo
  alias Cadence.SpacecraftStore.OverrideRow
  alias Cadence.SpacecraftTypeStore.SpacecraftTypeRow

  @type answer :: binary()
  @type entry :: %{
          composition_id: binary(),
          recorded_revision_id: binary() | nil,
          current_revision_id: binary() | nil,
          current_reason: binary() | nil
        }

  @doc "`%{composition_id => answer}` and `%{catalog_revision_id => composition_id}`."
  @spec for_catalogs(binary(), binary(), [binary() | nil], keyword()) ::
          {%{binary() => answer()}, %{binary() => binary()}}
  def for_catalogs(organization_id, mission_id, catalogs, opts \\ []) do
    pins =
      for catalog <- Enum.uniq(catalogs),
          is_binary(catalog),
          {:ok, composition} <- [
            CatalogPins.for_catalog_revision(organization_id, mission_id, catalog)
          ],
          into: %{},
          do: {catalog, composition}

    selected =
      pins
      |> Map.values()
      |> Enum.uniq()
      |> Map.new(&{&1, answer(Selection.select(organization_id, mission_id, &1, opts))})

    {selected, pins}
  end

  @doc "Every catalog revision a profile or a catalog override in the mission pins (two queries)."
  @spec pinned_catalogs(binary(), binary()) :: [binary()]
  def pinned_catalogs(organization_id, mission_id) do
    profiles =
      from(profile in SpacecraftTypeRow,
        where:
          profile.organization_id == ^organization_id and profile.mission_id == ^mission_id and
            not is_nil(profile.catalog_revision_id),
        distinct: true,
        select: profile.catalog_revision_id
      )
      |> Repo.all()

    overrides =
      from(override in OverrideRow,
        where:
          override.organization_id == ^organization_id and override.mission_id == ^mission_id and
            override.path == "catalog_revision_id",
        distinct: true,
        select: fragment("? ->> 'value'", override.value)
      )
      |> Repo.all()

    Enum.reject(profiles ++ overrides, &is_nil/1)
  end

  defp answer({:ok, revision_id}), do: revision_id
  defp answer({:error, reason}), do: Atom.to_string(reason)

  @doc """
  Under the activation lock: `{:ok, {selected, pins}}` when what's selected now equals `recorded`,
  else `{:error, {:restage_needed, [entry()]}}`. `opts` passes `Selection.select/4`'s test-only `:runnable`.
  """
  @spec check(binary(), binary(), map() | nil, [binary() | nil], keyword()) ::
          {:ok, {map(), map()}} | {:error, {:restage_needed, [entry()]}}
  def check(organization_id, mission_id, recorded, catalogs, opts \\ []) do
    {first, _pins} = for_catalogs(organization_id, mission_id, catalogs, opts)
    :ok = MissionModels.share_lock_revisions(organization_id, mission_id, revisions(first))
    {current, pins} = for_catalogs(organization_id, mission_id, catalogs, opts)

    case differences(recorded || %{}, current) do
      [] -> {:ok, {current, pins}}
      entries -> {:error, {:restage_needed, entries}}
    end
  end

  defp differences(recorded, current) do
    for composition <- Enum.sort(Map.keys(current)),
        Map.get(recorded, composition) != Map.get(current, composition) do
      now = Map.get(current, composition)

      %{
        composition_id: composition,
        recorded_revision_id: revision(Map.get(recorded, composition)),
        current_revision_id: revision(now),
        current_reason: if(revision(now), do: nil, else: now)
      }
    end
  end

  @reasons ["not_approved", "reapproval_needed"]

  @doc "The revision id in a selection answer, or nil for a reason none is selectable."
  @spec revision_of(answer() | nil) :: binary() | nil
  def revision_of(answer) when answer in @reasons, do: nil
  def revision_of(answer), do: answer

  defp revision(answer), do: revision_of(answer)

  defp revisions(selected),
    do: selected |> Map.values() |> Enum.map(&revision/1) |> Enum.reject(&is_nil/1)
end
