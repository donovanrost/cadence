defmodule Cadence.GroundNetworks.PredictedPasses.Basis do
  @moduledoc """
  What the recompute runs actually searched (#892), kept on the mission's prediction state
  (`search_basis`) so an opportunity is flagged `no_predicted_pass` only with per-pair evidence:

      %{
        "spacecraft" => %{id => %{"element_set_id" => id, "from" => iso, "to" => iso}},
        "stations" => %{id => %{"fingerprint" => "lat|lon|height|mask", "from" => iso}},
        "pruned_before" => iso | nil
      }

  A spacecraft's entry is the element set it was searched with and the window its stored rows
  cover; a station's is the geometry it was searched with and from when. A run forgets what it
  can't vouch for: a full run starts every entry at its own start, a spacecraft or station run
  restarts those entries, and an extension keeps an entry only while the set or geometry it
  searched with is still the recorded one. The prune raises the lower bound for every pair.

  `covered?/5` holds for a pair and window only when the spacecraft's current element set is
  the one it was searched with, the station's current geometry is the one it was searched with,
  the window lies wholly inside what both searched (and above the prune bound), and the pair has
  no unbracketed search result.
  """

  alias Cadence.Comms.GroundStation

  @type t :: map()

  @doc "A station's geometry as searched (location and mask), or nil when it has no location."
  @spec fingerprint(GroundStation.t()) :: binary() | nil
  def fingerprint(%GroundStation{} = station) do
    case GroundStation.effective_location(station) do
      %{latitude_deg: lat, longitude_deg: lon, height_m: height} ->
        Enum.map_join([lat, lon, height, station.elevation_mask_deg], "|", &number/1)

      nil ->
        nil
    end
  end

  @doc "A full run over `[from, to)`: every entry starts here."
  @spec full(t(), [map()], [GroundStation.t()], DateTime.t(), DateTime.t()) :: t()
  def full(basis, searched_sets, stations, from, to) do
    %{
      "spacecraft" => Map.new(searched_sets, &spacecraft_entry(&1, from, to)),
      "stations" => station_entries(stations, from),
      "pruned_before" => basis["pruned_before"]
    }
  end

  @doc "A run of these spacecraft over `[from, to)`: their entries restart."
  @spec spacecraft(t(), [binary()], [map()], DateTime.t(), DateTime.t()) :: t()
  def spacecraft(basis, ids, searched_sets, from, to) do
    entries =
      basis
      |> section("spacecraft")
      |> Map.drop(ids)
      |> Map.merge(Map.new(searched_sets, &spacecraft_entry(&1, from, to)))

    Map.put(basis, "spacecraft", entries)
  end

  @doc "A run of these stations from `from`: their entries restart."
  @spec stations(t(), [binary()], [GroundStation.t()], DateTime.t()) :: t()
  def stations(basis, ids, searched_stations, from) do
    entries =
      basis
      |> section("stations")
      |> Map.drop(ids)
      |> Map.merge(station_entries(searched_stations, from))

    Map.put(basis, "stations", entries)
  end

  @doc """
  An extension to `to`: a spacecraft entry extends only when it was searched with the same set
  again, a station entry stays only while its geometry is unchanged; any other entry is dropped,
  since its stored rows now mix two bases.
  """
  @spec extend(t(), [map()], [GroundStation.t()], DateTime.t()) :: t()
  def extend(basis, searched_sets, stations, to) do
    sets = Map.new(searched_sets, &{&1.spacecraft_id, &1.element_set_id})
    prints = Map.new(stations, &{&1.ground_station_id, fingerprint(&1)})

    spacecraft =
      for {id, %{"element_set_id" => set} = entry} <- section(basis, "spacecraft"),
          Map.get(sets, id) == set,
          into: %{},
          do: {id, Map.put(entry, "to", iso(to))}

    stations =
      for {id, %{"fingerprint" => print} = entry} <- section(basis, "stations"),
          print != nil and Map.get(prints, id) == print,
          into: %{},
          do: {id, entry}

    Map.merge(basis, %{"spacecraft" => spacecraft, "stations" => stations})
  end

  @doc "The horizon shrank to `to`: no entry reaches past it."
  @spec shrink(t(), DateTime.t()) :: t()
  def shrink(basis, to) do
    spacecraft =
      Map.new(section(basis, "spacecraft"), fn {id, entry} ->
        {id, Map.update!(entry, "to", &iso(earliest(at(&1), to)))}
      end)

    Map.put(basis, "spacecraft", spacecraft)
  end

  @doc """
  The prune deleted every pass that ended before `bound`. The bound only moves forward: a
  repeated or backdated prune (a clock rollback) never claims rows it already deleted are back.
  """
  @spec pruned(t(), DateTime.t()) :: t()
  def pruned(basis, bound) do
    basis = basis || %{}
    Map.put(basis, "pruned_before", latest(basis["pruned_before"], iso(bound)))
  end

  @doc """
  Whether the search covers this pair and window (see the moduledoc). A spacecraft a run could
  not propagate (`unpropagated`, by spacecraft) is never covered, whatever its earlier basis says:
  a station run may have failed for it while leaving its spacecraft entry in place.
  """
  @spec covered?(t(), map(), map(), map(), map(), map()) :: boolean()
  def covered?(basis, not_bracketed, unpropagated, current_sets, current_prints, window) do
    with false <- Map.has_key?(unpropagated || %{}, window.spacecraft_id),
         %{"element_set_id" => set, "from" => sc_from, "to" => sc_to} <-
           get_in(basis, ["spacecraft", window.spacecraft_id]),
         ^set <- Map.get(current_sets, window.spacecraft_id),
         %{"fingerprint" => print, "from" => st_from} <-
           get_in(basis, ["stations", window.ground_station_id]),
         true <- print != nil and Map.get(current_prints, window.ground_station_id) == print,
         0 <- Map.get(not_bracketed || %{}, pair(window), 0) do
      lower = Enum.reduce([sc_from, st_from, basis["pruned_before"]], &latest/2)

      DateTime.compare(window.starts_at, at(lower)) != :lt and
        DateTime.compare(window.ends_at, at(sc_to)) != :gt
    else
      _uncovered -> false
    end
  end

  defp spacecraft_entry(set, from, to),
    do:
      {set.spacecraft_id,
       %{"element_set_id" => set.element_set_id, "from" => iso(from), "to" => iso(to)}}

  defp station_entries(stations, from) do
    for station <- stations,
        print = fingerprint(station),
        print != nil,
        into: %{},
        do: {station.ground_station_id, %{"fingerprint" => print, "from" => iso(from)}}
  end

  defp section(basis, key), do: (basis || %{}) |> Map.get(key) |> Kernel.||(%{})

  defp pair(window), do: window.spacecraft_id <> "|" <> window.ground_station_id

  defp latest(nil, acc), do: acc
  defp latest(iso, acc), do: if(DateTime.after?(at(iso), at(acc)), do: iso, else: acc)

  defp earliest(%DateTime{} = a, %DateTime{} = b), do: if(DateTime.before?(a, b), do: a, else: b)

  defp number(value) when is_number(value),
    do: :erlang.float_to_binary(value * 1.0, [:short])

  defp number(_value), do: "-"

  defp iso(%DateTime{} = at), do: DateTime.to_iso8601(at)

  defp at(iso) when is_binary(iso) do
    {:ok, at, 0} = DateTime.from_iso8601(iso)
    at
  end
end
