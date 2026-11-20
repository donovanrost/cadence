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
          current_reason: binary() | nil,
          catalog_revision_number: integer() | nil,
          composition_number: pos_integer() | nil
        }

  # current_reason: newer_approved | unrunnable | none_left | nil (E2 adds withdrawn); U109.

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

    case differences(organization_id, mission_id, recorded || %{}, current, opts) do
      [] -> {:ok, {current, pins}}
      entries -> {:error, {:restage_needed, entries}}
    end
  end

  defp differences(organization_id, mission_id, recorded, current, opts) do
    for composition <- Enum.sort(Map.keys(current)),
        Map.get(recorded, composition) != Map.get(current, composition) do
      was = revision(Map.get(recorded, composition))
      now = revision(Map.get(current, composition))
      ranked = Selection.ranked(organization_id, mission_id, composition, opts)

      %{
        composition_id: composition,
        recorded_revision_id: was,
        current_revision_id: now,
        current_reason: reason(was, now, ranked)
      }
      |> Map.merge(numbers(organization_id, mission_id, composition))
    end
  end

  # What the words name the pin by (U109): its catalog revision's number while it's one layer,
  # else the composition's display number. Display only.
  defp numbers(organization_id, mission_id, composition) do
    catalog = CatalogPins.catalog_revision_for(organization_id, mission_id, composition)

    %{
      catalog_revision_number: CatalogPins.catalog_number(organization_id, mission_id, catalog),
      composition_number: CatalogPins.composition_number(organization_id, mission_id, composition)
    }
  end

  # U109's five whys (mms-ux, #633), one to one: E2 (#546) sets "withdrawn" with its decision.
  defp reason(_was, nil, _ranked), do: "none_left"

  defp reason(was, now, ranked) do
    ids = Enum.map(ranked, & &1.revision_id)

    cond do
      Enum.any?(ranked, &(&1.revision_id == was and not &1.runnable)) -> "unrunnable"
      ahead?(ids, now, was) -> "newer_approved"
      true -> nil
    end
  end

  # `now` ranks ahead of `was` (ranked/3 is newest first); a `was` no longer linked counts behind.
  defp ahead?(ids, now, was) do
    case {Enum.find_index(ids, &(&1 == now)), Enum.find_index(ids, &(&1 == was))} do
      {nil, _was} -> false
      {_now, nil} -> true
      {now_at, was_at} -> now_at < was_at
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
