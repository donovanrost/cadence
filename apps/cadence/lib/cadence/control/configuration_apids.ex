defmodule Cadence.Control.ConfigurationApids do
  @moduledoc """
  A spacecraft's handled APIDs as a profile/override field (L22, lead/ux 2026-11-13).

  The profile (with overrides) sets `handled_apids`: a list, or nil for "all of the catalog's
  APIDs". It governs only spacecraft whose profile sets their catalog (#65). At apply, the
  spacecraft's configuration follows the effective list, nil expanded to the effective catalog's
  APIDs (`CatalogApids.effective/2`). Nothing changes unseen: the spacecraft kinds' HOLDs
  (`Cadence.Spacecraft.ConfigKinds.ApidCompatibility`) show every change and refuse strays.

  Pure: the generation builder supplies effective profile values, running entries and catalog
  APIDs.
  """

  alias Cadence.MissionModels.CatalogApids

  @doc """
  What each spacecraft would decode after the apply: `%{id => %{from, to, stray}}` for those whose
  decoded APIDs change or whose list names APIDs the catalog doesn't define. `effective` is
  `%{id => %{"catalog_revision_id", "handled_apids"}}`; `catalog_apids` is
  `%{catalog_revision_id => [apid]}`.
  """
  @spec changes(map(), map(), map()) :: map()
  def changes(effective, entries, catalog_apids) do
    for {id, values} <- effective,
        catalog = values["catalog_revision_id"],
        is_binary(catalog),
        entry = Map.get(entries, id),
        is_map(entry),
        apids = Map.get(catalog_apids, catalog, []),
        to = CatalogApids.effective(values["handled_apids"], apids),
        from = running(entry),
        stray = CatalogApids.stray(values["handled_apids"], apids),
        to != from or stray != [],
        into: %{},
        do: {id, %{from: from, to: to, stray: stray}}
  end

  @doc "What the running configuration decodes, sorted."
  def running(entry),
    do: ((entry || %{})["document"] || %{})["handled_apids"] |> List.wrap() |> Enum.sort()

  @doc "The derivations an apply makes: `%{id => %{\"handled_apids\" => [apid]}}` (no strays)."
  def derivations(changes) do
    for {id, %{to: to, from: from, stray: []}} <- changes, to != from, into: %{} do
      {id, %{"handled_apids" => to}}
    end
  end
end
