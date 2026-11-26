defmodule Cadence.Spacecraft.ConfigKinds.CompositionPin do
  @moduledoc """
  D3's pin rules (#544; design §3), shared by the profile and the per-craft override. The pin is
  `composition_id`, and only the client sets it. `catalog_revision_id` is the composition's
  provenance catalog revision, which Cadence derives at staging and stores for the runtime readers
  that still key on it, until phase 4 (#448–#450) re-keys them on the effective revision.

  - **Derivation, at staging only.** An op that gives a `catalog_revision_id` other than the
    composition's own is refused; every op gets the one derived from its composition, so the
    staged op is exactly what apply writes.
  - **Validation (NO-GO), at preview and again at apply:** the composition exists in the mission
    and has an approved, runnable revision (`Selection`).
  - **The number is display-only** (mms-security on #581): a pin is a composition id string. A
    number is refused by the kinds' shape checks and is never resolved.
  - **Words** (mms-ux, a U109 amendment): a field error, no final period, naming the pin by U109's
    rule: a one-catalog pin is "catalog rev 4" (every pin until D4); several catalogs read
    "composition 3" (D2's number), and "this composition" without one. `details` carries the reason
    and the numbers so the console can rebuild the line.
  """

  alias Cadence.MissionModels.{CatalogPins, Compositions, Selection}
  alias Cadence.Platform.ConfigFields, as: F

  @type pin :: {binary() | nil, binary() | nil}

  @doc """
  The staged pin `{catalog_revision_id, composition_id}` for a document pinning `composition`. A
  `catalog_revision_id` the op gives (`given`; nil when it gives none) must be the composition's
  own, e.g. a rollback restoring both; any other value is refused.
  """
  @spec derive(binary(), binary(), binary() | nil, binary() | nil) ::
          {:ok, pin()} | {:error, [map()]}
  def derive(organization_id, mission_id, composition, given) do
    derived = provenance(organization_id, mission_id, composition)

    if is_nil(given) or given == derived,
      do: {:ok, {derived, composition}},
      else:
        {:error,
         [
           F.error(
             "catalog_revision_id",
             "Cadence sets this from the mission composition; choose the composition instead"
           )
         ]}
  end

  defp provenance(organization_id, mission_id, composition) when is_binary(composition),
    do: CatalogPins.catalog_revision_for(organization_id, mission_id, composition)

  defp provenance(_organization_id, _mission_id, _composition), do: nil

  @doc """
  Field errors for a pin that changed (`path` names the composition field). An unchanged pin is
  never re-judged here: what's running is the activation gate's to check.
  """
  @spec errors(binary(), binary(), pin(), pin(), binary()) :: [map()]
  def errors(_organization_id, _mission_id, pin, pin, _path), do: []
  def errors(_organization_id, _mission_id, _previous, {_catalog, nil}, _path), do: []

  def errors(organization_id, mission_id, _previous, {_catalog, composition}, path)
      when is_binary(composition) do
    with :ok <- exists(organization_id, mission_id, composition, path),
         :ok <- runnable_approved(organization_id, mission_id, composition, path) do
      []
    else
      {:error, error} -> [error]
    end
  end

  def errors(_organization_id, _mission_id, _previous, _pin, _path), do: []

  defp exists(organization_id, mission_id, composition, path) do
    case Compositions.fetch(organization_id, mission_id, composition) do
      {:ok, _composition} -> :ok
      {:error, _missing} -> {:error, F.error(path, "That mission composition doesn't exist")}
    end
  end

  defp runnable_approved(organization_id, mission_id, composition, path) do
    case Selection.select(organization_id, mission_id, composition) do
      {:ok, _revision_id} ->
        :ok

      {:error, reason} ->
        pin = pin_details(organization_id, mission_id, composition)
        {:error, error(path, sentence(reason, pin), Map.put(pin, :reason, to_string(reason)))}
    end
  end

  defp sentence(:not_approved, pin),
    do: "#{subject(pin)} isn't approved yet; an org admin approves it in Setup › Catalog first"

  defp sentence(:reapproval_needed, pin),
    do:
      "#{subject(pin)} was approved for an earlier version of Cadence, so it needs approving " <>
        "again; an org admin does that in Setup › Catalog"

  # U109: one catalog reads "Catalog rev 4"; several, the composition's number (D2) or this one.
  defp subject(%{catalog_revision_number: number}) when is_integer(number),
    do: "Catalog rev #{number}"

  defp subject(%{composition_number: number}) when is_integer(number),
    do: "Composition #{number}"

  defp subject(_pin), do: "This composition"

  defp pin_details(organization_id, mission_id, composition) do
    catalog = CatalogPins.catalog_revision_for(organization_id, mission_id, composition)

    %{
      composition_id: composition,
      catalog_revision_id: catalog,
      catalog_revision_number: CatalogPins.catalog_number(organization_id, mission_id, catalog),
      composition_number: CatalogPins.composition_number(organization_id, mission_id, composition)
    }
  end

  defp error(path, message, details), do: Map.put(F.error(path, message), :details, details)
end
