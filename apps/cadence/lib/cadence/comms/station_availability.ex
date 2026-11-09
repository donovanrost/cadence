defmodule Cadence.Comms.StationAvailability do
  @moduledoc """
  Ground station availability (S7, DECISIONS #39, `docs/apogee/domain/station-availability.md`).

  Windows are `outage`, `maintenance` (the station can't be used) or `degraded` (usable with
  limits). They come from operators or from provider reports. Status is derived from the
  windows and never stored:

  - `down`: an outage or maintenance window is active;
  - `degraded`: a degraded window is active;
  - `up`: nothing is reported. That means "no known problem", not live telemetry, and the
    status says so in `basis`.

  Writes publish `:stations_changed` and `:contacts_changed` read invalidations after commit.
  """

  import Ecto.Query

  alias Cadence.Auth.{Policy, Scope}
  alias Cadence.Comms.GroundStationStore
  alias Cadence.Comms.StationAvailability.WindowRow
  alias Cadence.Ids
  alias Cadence.Platform.ScopedReadUpdates
  alias Cadence.Repo

  @kinds ~w(outage maintenance degraded)
  @blocking ~w(outage maintenance)
  # Explicit maps, not String.to_existing_atom: an atom no loaded module mentions doesn't exist
  # yet, and the read crashed on the first outage window (qa #20).
  @kind_atoms %{"outage" => :outage, "maintenance" => :maintenance, "degraded" => :degraded}
  @sources %{"operator" => :operator, "provider" => :provider}

  # -- scoped facade --------------------------------------------------------------------------

  @spec status(Scope.t(), String.t(), String.t() | :all, DateTime.t()) ::
          {:ok, map() | [map()]} | {:error, term()}
  def status(%Scope{} = scope, mission_id, station, at \\ DateTime.utc_now()) do
    with :ok <- authorize(scope, mission_id),
         do: {:ok, status_of(scope.organization_id, mission_id, station, at)}
  end

  @spec windows(Scope.t(), String.t(), String.t() | :all, DateTime.t(), DateTime.t()) ::
          {:ok, [map()]} | {:error, term()}
  def windows(%Scope{} = scope, mission_id, station, from, to) do
    with :ok <- authorize(scope, mission_id),
         do:
           {:ok,
            Enum.map(
              active_windows(scope.organization_id, mission_id, station, from, to),
              &view/1
            )}
  end

  @doc "Schedules maintenance or declares an outage/degradation. `attrs`: kind, starts_at, ends_at | eta, reason, detail."
  @spec schedule(Scope.t(), String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def schedule(%Scope{} = scope, mission_id, station_id, attrs) do
    with :ok <- authorize(scope, mission_id),
         {:ok, _station} <- station(scope.organization_id, mission_id, station_id),
         {:ok, attrs} <- window_attrs(attrs),
         :ok <- no_overlap(scope.organization_id, mission_id, station_id, attrs) do
      %WindowRow{
        window_id: Ids.new("station_window"),
        organization_id: scope.organization_id,
        mission_id: mission_id,
        ground_station_id: station_id,
        source: "operator",
        reported_by: actor(scope)
      }
      |> struct(attrs)
      |> Repo.insert()
      |> published(scope.organization_id, mission_id)
    end
  end

  @spec clear(Scope.t(), String.t(), String.t(), String.t() | nil) ::
          {:ok, map()} | {:error, term()}
  def clear(%Scope{} = scope, mission_id, window_id, reason \\ nil) do
    with :ok <- authorize(scope, mission_id),
         {:ok, row} <- fetch(scope.organization_id, mission_id, window_id),
         :ok <- not_cleared(row) do
      row
      |> Ecto.Changeset.change(
        cleared_at: DateTime.utc_now(),
        cleared_by: Map.put(actor(scope), "reason", reason)
      )
      |> Repo.update()
      |> published(scope.organization_id, mission_id)
    end
  end

  # -- provider entry point -------------------------------------------------------------------

  @doc """
  Upserts a provider-reported window, keyed by the provider's own reference. Adapters call this
  when their API reports station status. A window the provider reports again is active again,
  even if it was cleared: the provider's report is the source of truth for its own windows. `report`: ground_station_id, kind, starts_at,
  ends_at | eta, provider_ref, reason, provider (name for `reported_by`).
  """
  @spec record_provider_report(String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def record_provider_report(organization_id, mission_id, %{provider_ref: ref} = report)
      when is_binary(ref) do
    with {:ok, _station} <- station(organization_id, mission_id, report.ground_station_id),
         {:ok, attrs} <- window_attrs(report) do
      %WindowRow{
        window_id: Ids.new("station_window"),
        organization_id: organization_id,
        mission_id: mission_id,
        ground_station_id: report.ground_station_id,
        source: "provider",
        provider_ref: ref,
        reported_by: %{"kind" => "provider", "id" => Map.get(report, :provider, "provider")}
      }
      |> struct(attrs)
      |> Repo.insert(
        on_conflict:
          {:replace,
           [
             :kind,
             :starts_at,
             :ends_at,
             :eta,
             :reason,
             :detail,
             :cleared_at,
             :cleared_by,
             :updated_at
           ]},
        conflict_target:
          {:unsafe_fragment, "(mission_id, provider_ref) WHERE provider_ref IS NOT NULL"}
      )
      |> published(organization_id, mission_id)
    end
  end

  # -- reads used by planning ------------------------------------------------------------------

  @doc "Blocking (outage/maintenance) windows overlapping `[from, to]`, by station id."
  @spec blocking_windows(String.t(), String.t(), DateTime.t(), DateTime.t()) :: %{
          String.t() => [map()]
        }
  def blocking_windows(organization_id, mission_id, from, to) do
    organization_id
    |> active_windows(mission_id, :all, from, to)
    |> Enum.filter(&(&1.kind in @blocking))
    |> Enum.group_by(
      & &1.ground_station_id,
      &%{
        window_id: &1.window_id,
        starts_at: &1.starts_at,
        ends_at: &1.ends_at,
        source: Map.fetch!(@sources, &1.source)
      }
    )
  end

  @doc """
  Every active window (outage, maintenance and degraded) overlapping `[from, to]`, by station
  id, with its `kind` (`:outage | :maintenance | :degraded`). For plan checks (U26).
  """
  @spec planning_windows(String.t(), String.t(), DateTime.t(), DateTime.t()) :: %{
          String.t() => [map()]
        }
  def planning_windows(organization_id, mission_id, from, to) do
    organization_id
    |> active_windows(mission_id, :all, from, to)
    |> Enum.group_by(
      & &1.ground_station_id,
      &%{
        window_id: &1.window_id,
        kind: Map.fetch!(@kind_atoms, &1.kind),
        starts_at: &1.starts_at,
        ends_at: &1.ends_at
      }
    )
  end

  @doc "Whether `[starts_at, ends_at]` overlaps any of `windows` (open windows never end)."
  @spec overlaps?([map()], DateTime.t(), DateTime.t()) :: map() | nil
  def overlaps?(windows, starts_at, ends_at) do
    Enum.find(windows, fn window ->
      DateTime.before?(window.starts_at, ends_at) and
        (is_nil(window.ends_at) or DateTime.after?(window.ends_at, starts_at))
    end)
  end

  @doc "Pure status of one station from its active windows at `at`."
  @spec derive(String.t(), [WindowRow.t()], DateTime.t()) :: map()
  def derive(station_id, windows, at) do
    current = Enum.filter(windows, &active_at?(&1, at))
    blocking = Enum.find(current, &(&1.kind in @blocking))
    degraded = Enum.find(current, &(&1.kind == "degraded"))

    {state, window} =
      cond do
        blocking -> {:down, blocking}
        degraded -> {:degraded, degraded}
        true -> {:up, nil}
      end

    %{ground_station_id: station_id, state: state}
    |> Map.merge(window_fields(window))
    |> Map.put(
      :windows,
      windows |> Enum.filter(&upcoming_or_active?(&1, at)) |> Enum.map(&view/1)
    )
  end

  defp window_fields(nil),
    do: %{
      since: nil,
      eta: nil,
      reported_by: nil,
      reported_at: nil,
      source: nil,
      basis: "no reported windows"
    }

  defp window_fields(window) do
    %{
      since: window.starts_at,
      eta: window.ends_at || window.eta,
      reported_by: window.reported_by,
      reported_at: window.inserted_at,
      source: Map.fetch!(@sources, window.source),
      basis: "#{window.source} reported #{window.kind}"
    }
  end

  defp status_of(organization_id, mission_id, :all, at) do
    windows =
      organization_id
      |> active_windows(mission_id, :all, at, DateTime.add(at, 7, :day))
      |> Enum.group_by(& &1.ground_station_id)

    organization_id
    |> GroundStationStore.list_ground_stations(mission_id)
    |> Enum.map(&derive(&1.ground_station_id, Map.get(windows, &1.ground_station_id, []), at))
  end

  defp status_of(organization_id, mission_id, station_id, at) do
    windows =
      active_windows(organization_id, mission_id, station_id, at, DateTime.add(at, 7, :day))

    derive(station_id, windows, at)
  end

  defp active_windows(organization_id, mission_id, station, from, to) do
    WindowRow
    |> where(
      [w],
      w.organization_id == ^organization_id and w.mission_id == ^mission_id and
        is_nil(w.cleared_at) and
        w.starts_at < ^to and (is_nil(w.ends_at) or w.ends_at > ^from)
    )
    |> station_filter(station)
    |> order_by([w], asc: w.starts_at)
    |> Repo.all()
  end

  defp station_filter(query, :all), do: query

  defp station_filter(query, station_id),
    do: where(query, [w], w.ground_station_id == ^station_id)

  defp active_at?(window, at),
    do:
      not DateTime.after?(window.starts_at, at) and
        (is_nil(window.ends_at) or DateTime.after?(window.ends_at, at))

  defp upcoming_or_active?(window, at),
    do: is_nil(window.ends_at) or DateTime.after?(window.ends_at, at)

  defp window_attrs(attrs) do
    kind = to_string(Map.get(attrs, :kind))
    starts_at = Map.get(attrs, :starts_at)
    ends_at = Map.get(attrs, :ends_at)

    cond do
      kind not in @kinds ->
        {:error, :invalid_window}

      not match?(%DateTime{}, starts_at) ->
        {:error, :invalid_window}

      match?(%DateTime{}, ends_at) and not DateTime.after?(ends_at, starts_at) ->
        {:error, :invalid_window}

      true ->
        {:ok,
         %{
           kind: kind,
           starts_at: usec(starts_at),
           ends_at: ends_at && usec(ends_at),
           eta: (eta = Map.get(attrs, :eta)) && usec(eta),
           reason: Map.get(attrs, :reason),
           detail: Map.get(attrs, :detail, %{})
         }}
    end
  end

  defp no_overlap(organization_id, mission_id, station_id, attrs) do
    far = attrs.ends_at || DateTime.add(attrs.starts_at, 3650, :day)

    organization_id
    |> active_windows(mission_id, station_id, attrs.starts_at, far)
    |> Enum.any?(&(&1.kind == attrs.kind))
    |> if(do: {:error, :window_overlaps}, else: :ok)
  end

  defp fetch(organization_id, mission_id, window_id) do
    case Repo.get_by(WindowRow,
           organization_id: organization_id,
           mission_id: mission_id,
           window_id: window_id
         ) do
      nil -> {:error, :window_not_found}
      row -> {:ok, row}
    end
  end

  defp not_cleared(%WindowRow{cleared_at: nil}), do: :ok
  defp not_cleared(_row), do: {:error, :window_cleared}

  defp station(organization_id, mission_id, station_id) do
    case GroundStationStore.fetch_ground_station(organization_id, mission_id, station_id) do
      {:ok, station} -> {:ok, station}
      {:error, _} -> {:error, :station_not_found}
    end
  end

  defp authorize(%Scope{} = scope, mission_id) do
    case Policy.authorize(scope, :operate_mission, %{
           organization_id: scope.organization_id,
           mission_id: mission_id
         }) do
      :ok -> :ok
      {:error, _reason} -> {:error, :forbidden}
    end
  end

  defp actor(%Scope{actor_kind: :user, user: user}),
    do: %{"kind" => "user", "id" => user.user_id, "name" => user.display_name || user.email}

  defp actor(%Scope{} = scope), do: Scope.audit_actor(scope)

  defp published({:ok, row}, organization_id, mission_id) do
    ScopedReadUpdates.publish(:stations_changed, organization_id, mission_id)
    ScopedReadUpdates.publish(:contacts_changed, organization_id, mission_id)
    {:ok, view(row)}
  end

  defp published(error, _organization_id, _mission_id), do: error

  defp view(%WindowRow{} = row) do
    %{
      id: row.window_id,
      ground_station_id: row.ground_station_id,
      kind: Map.fetch!(@kind_atoms, row.kind),
      from: row.starts_at,
      to: row.ends_at,
      eta: row.eta,
      source: Map.fetch!(@sources, row.source),
      reported_by: row.reported_by,
      created_by: row.reported_by,
      reported_at: row.inserted_at,
      reason: row.reason,
      detail: row.detail,
      cleared_at: row.cleared_at
    }
  end

  defp usec(%DateTime{microsecond: {value, _}} = time), do: %{time | microsecond: {value, 6}}
end
