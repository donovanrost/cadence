defmodule Cadence.Spacecraft.ConfigKinds.CompositionPin do
  @moduledoc """
  D3's pin rules (#544; design §3), shared by the profile and the per-craft override. A pin is
  `{catalog_revision_id, composition_id}`: the composition is the pin, the catalog revision its
  provenance while the composition is one layer.

  - **Translation, at staging only.** An op that sets the catalog revision and not the composition
    (an old client) gets the catalog revision's one-layer composition. One that sets only the
    composition gets the provenance catalog revision (the one it names, else the earliest that
    imported its layer). One that sets both keeps both, and validation refuses a mismatch.
  - **Validation (NO-GO), at preview and again at apply:** the composition exists in the mission,
    agrees with the catalog revision, and has an approved, runnable revision (`Selection`).
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

  @doc "The translated pin, given whether the op set the catalog revision and the composition."
  @spec translate(binary(), binary(), pin(), {boolean(), boolean()}) :: pin()
  def translate(organization_id, mission_id, {catalog, composition}, touched) do
    case touched do
      {true, false} ->
        {catalog, composition_of(organization_id, mission_id, catalog, composition)}

      {false, true} ->
        {provenance(organization_id, mission_id, catalog, composition), composition}

      _both_or_neither ->
        {catalog, composition}
    end
  end

  # The catalog revision's one-layer composition; a catalog revision that has none (or doesn't
  # exist) keeps the composition as it was, and validation words the refusal.
  defp composition_of(_organization_id, _mission_id, nil, _composition), do: nil

  defp composition_of(organization_id, mission_id, catalog, composition)
       when is_binary(catalog) do
    case CatalogPins.for_catalog_revision(organization_id, mission_id, catalog) do
      {:ok, id} -> id
      {:error, _none} -> composition
    end
  end

  defp composition_of(_organization_id, _mission_id, _catalog, composition), do: composition

  defp provenance(_organization_id, _mission_id, _catalog, nil), do: nil

  defp provenance(organization_id, mission_id, catalog, composition)
       when is_binary(composition) do
    if is_binary(catalog) and
         CatalogPins.for_catalog_revision(organization_id, mission_id, catalog) ==
           {:ok, composition},
       do: catalog,
       else: CatalogPins.catalog_revision_for(organization_id, mission_id, composition)
  end

  defp provenance(_organization_id, _mission_id, catalog, _composition), do: catalog

  @doc """
  Field errors for a pin that changed (`path` names the composition field). An unchanged pin is
  never re-judged here: what's running is the activation gate's to check.
  """
  @spec errors(binary(), binary(), pin(), pin(), binary()) :: [map()]
  def errors(_organization_id, _mission_id, pin, pin, _path), do: []
  def errors(_organization_id, _mission_id, _previous, {_catalog, nil}, _path), do: []

  def errors(organization_id, mission_id, _previous, {catalog, composition}, path)
      when is_binary(composition) do
    with :ok <- exists(organization_id, mission_id, composition, path),
         :ok <- agrees(organization_id, mission_id, catalog, composition, path),
         :ok <- runnable_approved(organization_id, mission_id, catalog, composition, path) do
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

  defp agrees(_organization_id, _mission_id, nil, _composition, _path), do: :ok

  defp agrees(organization_id, mission_id, catalog, composition, path) do
    if CatalogPins.for_catalog_revision(organization_id, mission_id, catalog) ==
         {:ok, composition} do
      :ok
    else
      number = CatalogPins.catalog_number(organization_id, mission_id, catalog)
      label = if number, do: "catalog rev #{number}", else: "that catalog revision"

      {:error,
       error(
         path,
         "Cadence couldn't match this to #{label}; choose the catalog revision again",
         %{
           reason: "mismatch",
           composition_id: composition,
           catalog_revision_id: catalog,
           catalog_revision_number: number
         }
       )}
    end
  end

  defp runnable_approved(organization_id, mission_id, catalog, composition, path) do
    case Selection.select(organization_id, mission_id, composition) do
      {:ok, _revision_id} ->
        :ok

      {:error, reason} ->
        pin = pin_details(organization_id, mission_id, catalog, composition)
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

  defp pin_details(organization_id, mission_id, catalog, composition) do
    catalog =
      if is_binary(catalog) and
           CatalogPins.for_catalog_revision(organization_id, mission_id, catalog) ==
             {:ok, composition},
         do: catalog,
         else: CatalogPins.catalog_revision_for(organization_id, mission_id, composition)

    %{
      composition_id: composition,
      catalog_revision_id: catalog,
      catalog_revision_number: CatalogPins.catalog_number(organization_id, mission_id, catalog),
      composition_number: CatalogPins.composition_number(organization_id, mission_id, composition)
    }
  end

  defp error(path, message, details), do: Map.put(F.error(path, message), :details, details)
end
