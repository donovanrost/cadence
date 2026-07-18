defmodule CadenceSimulator.Provider do
  @moduledoc """
  Canonical provider control plane for deterministic ground-network simulation.

  All public maps use string keys so they can cross the JSON boundary without
  exposing internal structs or atoms.
  """

  alias CadenceSimulator.Provider.{
    Capabilities,
    Contract,
    DeliveryProfiles,
    FaultProfile,
    Ids,
    OrbitReadiness,
    RouteProfiles,
    ServiceProfiles,
    Store
  }

  @terminal_run_states ["completed", "failed"]
  @terminal_reservation_states ["rejected", "canceled", "completed", "failed", "terminated_early"]
  @default_stations [
    %{
      "id" => "station-svalbard",
      "name" => "Svalbard",
      "region" => "arctic",
      "antenna_count" => 10
    },
    %{"id" => "station-troll", "name" => "Troll", "region" => "antarctic", "antenna_count" => 10},
    %{"id" => "station-hawaii", "name" => "Hawaii", "region" => "pacific", "antenna_count" => 10}
  ]

  @spec create_scenario(map()) :: {:ok, map()} | {:error, term()}
  def create_scenario(attrs) when is_map(attrs) do
    now = now_iso8601()
    spacecraft_count = integer(attrs, "spacecraft_count", 500)

    with :ok <- validate_range(spacecraft_count, 1, 10_000, "spacecraft_count"),
         {:ok, stations} <-
           normalize_stations(Map.get(attrs, "ground_stations", @default_stations)),
         {:ok, behavior} <-
           Capabilities.normalize_behavior(Map.get(attrs, "provider_behavior", %{})),
         {:ok, service_profiles} <-
           ServiceProfiles.normalize(
             Map.get(attrs, "service_profiles", ServiceProfiles.default())
           ),
         {:ok, delivery_profiles} <-
           DeliveryProfiles.normalize(Map.get(attrs, "delivery_profiles", [])),
         {:ok, orbit_readiness} <-
           OrbitReadiness.normalize(Map.get(attrs, "orbit_readiness", %{})),
         {:ok, route_profiles} <-
           RouteProfiles.normalize(
             Map.get(attrs, "route_profiles", []),
             stations,
             service_profiles
           ),
         {:ok, fault_profile} <-
           FaultProfile.normalize(Map.get(attrs, "fault_profile", %{})) do
      scenario = %{
        "id" => Map.get(attrs, "id", Ids.new("scenario")),
        "name" => Map.get(attrs, "name", "Constellation rehearsal"),
        "description" => Map.get(attrs, "description", ""),
        "spacecraft_count" => spacecraft_count,
        "spacecraft_prefix" => Map.get(attrs, "spacecraft_prefix", "SC"),
        "ground_stations" => stations,
        "provider_behavior" => behavior,
        "service_profiles" => service_profiles,
        "delivery_profiles" => delivery_profiles,
        "orbit_readiness" => orbit_readiness,
        "route_profiles" => route_profiles,
        "pass_model" => %{
          "cadence_seconds" => nested_integer(attrs, "pass_model", "cadence_seconds", 5_400),
          "duration_seconds" => nested_integer(attrs, "pass_model", "duration_seconds", 600),
          "jitter_seconds" => nested_integer(attrs, "pass_model", "jitter_seconds", 120)
        },
        "telemetry_profile" => Map.get(attrs, "telemetry_profile", %{"rate_hz" => 1.0}),
        "fault_profile" => fault_profile,
        "created_at" => now,
        "updated_at" => now
      }

      Store.put(:scenario, scenario)
    end
  end

  @spec list_scenarios() :: [map()]
  def list_scenarios, do: Store.list(:scenario)

  @spec fetch_scenario(binary()) :: {:ok, map()} | {:error, :not_found}
  def fetch_scenario(id), do: Store.fetch(:scenario, id)

  @spec create_run(binary(), map()) :: {:ok, map()} | {:error, term()}
  def create_run(scenario_id, attrs \\ %{}) when is_binary(scenario_id) and is_map(attrs) do
    with {:ok, scenario} <- Store.fetch(:scenario, scenario_id),
         speed when is_number(speed) <- number(attrs, "speed", 1.0),
         :ok <- validate_speed(speed) do
      now = DateTime.utc_now()
      state = Map.get(attrs, "state", "running")

      run_id = Map.get(attrs, "id", Ids.new("run"))

      run = %{
        "id" => run_id,
        "provider_environment_ref" => run_id,
        "scenario_id" => scenario_id,
        "state" => state,
        "speed" => speed * 1.0,
        "seed" => Map.get(attrs, "seed", :erlang.phash2({scenario_id, now})),
        "scenario_snapshot" => scenario,
        "started_at" => DateTime.to_iso8601(now),
        "created_at" => DateTime.to_iso8601(now),
        "updated_at" => DateTime.to_iso8601(now),
        "paused_at" => nil,
        "paused_duration_seconds" => 0,
        "stopped_at" => nil
      }

      with {:ok, run} <- Store.put(:run, run) do
        emit("run.created", run, %{"state" => state, "speed" => speed})
        {:ok, run}
      end
    else
      value when is_number(value) -> {:error, {:invalid, "speed"}}
      error -> error
    end
  end

  @spec transition_run(binary(), binary()) :: {:ok, map()} | {:error, term()}
  def transition_run(run_id, action) when action in ["pause", "resume", "stop"] do
    with {:ok, run} <- Store.fetch(:run, run_id),
         {:ok, next_run} <- apply_run_transition(run, action),
         {:ok, next_run} <- Store.put(:run, next_run) do
      emit(run_event_type(action), next_run, %{"state" => next_run["state"]})
      {:ok, next_run}
    end
  end

  @spec fetch_run(binary()) :: {:ok, map()} | {:error, :not_found}
  def fetch_run(id), do: Store.fetch(:run, id)

  @spec list_runs() :: [map()]
  def list_runs, do: Store.list(:run)

  @spec configure_run_faults(binary(), map()) :: {:ok, map()} | {:error, term()}
  def configure_run_faults(run_id, attrs) when is_binary(run_id) and is_map(attrs) do
    with {:ok, run} <- Store.fetch(:run, run_id),
         current = get_in(run, ["scenario_snapshot", "fault_profile"]) || FaultProfile.defaults(),
         {:ok, fault_profile} <- FaultProfile.merge(current, attrs) do
      updated =
        run
        |> put_in(["scenario_snapshot", "fault_profile"], fault_profile)
        |> timestamp_update()

      Store.put(:run, updated)
    end
  end

  @spec ground_stations(binary()) :: {:ok, [map()]} | {:error, :not_found}
  def ground_stations(run_id) do
    with {:ok, run} <- Store.fetch(:run, run_id) do
      {:ok, run["scenario_snapshot"]["ground_stations"]}
    end
  end

  @spec spacecraft(binary()) :: {:ok, [map()]} | {:error, :not_found}
  def spacecraft(run_id) do
    with {:ok, run} <- Store.fetch(:run, run_id) do
      scenario = run["scenario_snapshot"]
      {:ok, spacecraft_inventory(scenario)}
    end
  end

  @spec search_opportunities(map()) :: {:ok, map()} | {:error, term()}
  def search_opportunities(params) when is_map(params) do
    with {:ok, run} <- Store.fetch(:run, Map.get(params, "run_id", "")),
         :ok <- ensure_run_searchable(run),
         {:ok, starts_at} <- parse_datetime(params, "starts_at"),
         {:ok, ends_at} <- parse_datetime(params, "ends_at"),
         :ok <- validate_interval(starts_at, ends_at) do
      scenario = run["scenario_snapshot"]
      station_ids = Map.get(params, "ground_station_ids", [])
      requested_spacecraft_ids = Map.get(params, "spacecraft_ids", [])
      limit = params |> integer("limit", 100) |> min(500) |> max(1)

      stations =
        scenario["ground_stations"]
        |> maybe_filter_by_ids(station_ids)

      spacecraft =
        scenario
        |> spacecraft_inventory()
        |> maybe_filter_by_ids(requested_spacecraft_ids)

      opportunities =
        generate_opportunities(run, spacecraft, stations, starts_at, ends_at)
        |> Enum.take(limit)

      {:ok,
       %{
         "data" => opportunities,
         "run_id" => run["id"],
         "synthetic" => true,
         "generated_at" => now_iso8601(),
         "truncated" => length(opportunities) == limit
       }}
    end
  end

  @spec reserve_contact(map(), binary() | nil) :: {:ok, map()} | {:error, term()}
  def reserve_contact(attrs, idempotency_key \\ nil) when is_map(attrs) do
    with nil <- existing_idempotent_reservation(idempotency_key),
         {:ok, run} <- Store.fetch(:run, Map.get(attrs, "run_id", "")),
         :ok <- ensure_run_searchable(run),
         {:ok, starts_at} <- parse_datetime(attrs, "starts_at"),
         {:ok, ends_at} <- parse_datetime(attrs, "ends_at"),
         :ok <- validate_interval(starts_at, ends_at),
         :ok <- validate_reservation_resources(run, attrs),
         :ok <- ensure_capacity(attrs, starts_at, ends_at) do
      now = now_iso8601()
      status = initial_reservation_status(run, attrs)

      reservation = %{
        "id" => Ids.new("reservation"),
        "provider_contact_ref" => Ids.new("provider-contact"),
        "run_id" => run["id"],
        "opportunity_id" => Map.get(attrs, "opportunity_id"),
        "spacecraft_id" => Map.fetch!(attrs, "spacecraft_id"),
        "ground_station_id" => Map.fetch!(attrs, "ground_station_id"),
        "antenna_id" => Map.fetch!(attrs, "antenna_id"),
        "starts_at" => DateTime.to_iso8601(starts_at),
        "ends_at" => DateTime.to_iso8601(ends_at),
        "status" => status,
        "status_reason" =>
          if(status == "rejected", do: "fault_profile_scheduling_rejection", else: nil),
        "mission_profile_ref" => Map.get(attrs, "mission_profile_ref"),
        "dataflow_profile_ref" => Map.get(attrs, "dataflow_profile_ref"),
        "data_plane" => Map.get(attrs, "data_plane", %{}),
        "configuration_snapshot" => attrs,
        "idempotency_key" => idempotency_key,
        "created_at" => now,
        "updated_at" => now
      }

      with {:ok, reservation} <- Store.put(:reservation, reservation) do
        emit("reservation.#{status}", reservation, %{"status" => status})
        {:ok, reservation}
      end
    else
      %{} = reservation -> {:ok, reservation}
      error -> error
    end
  rescue
    KeyError -> {:error, {:invalid, "reservation resources are required"}}
  end

  @spec fetch_reservation(binary()) :: {:ok, map()} | {:error, :not_found}
  def fetch_reservation(id), do: Store.fetch(:reservation, id)

  @spec list_reservations(map()) :: [map()]
  def list_reservations(filters \\ %{}) do
    Store.list(:reservation)
    |> Enum.filter(fn reservation ->
      Enum.all?(
        ["run_id", "spacecraft_id", "ground_station_id", "status", "idempotency_key"],
        fn key ->
          filter = Map.get(filters, key)
          is_nil(filter) or filter == "" or reservation[key] == filter
        end
      )
    end)
  end

  @spec cancel_reservation(binary()) :: {:ok, map()} | {:error, term()}
  def cancel_reservation(id) do
    with {:ok, reservation} <- Store.fetch(:reservation, id),
         false <- reservation["status"] in @terminal_reservation_states do
      update_reservation_status(reservation, "canceled", "operator_canceled")
    else
      true -> {:error, {:conflict, "reservation is already terminal"}}
      error -> error
    end
  end

  @spec update_reservation_status(map(), binary(), binary() | nil) :: {:ok, map()}
  def update_reservation_status(reservation, status, reason \\ nil) do
    updated =
      reservation
      |> Map.put("status", status)
      |> Map.put("status_reason", reason)
      |> Map.put("updated_at", now_iso8601())

    with {:ok, updated} <- Store.put(:reservation, updated) do
      emit("reservation.#{status}", updated, %{"status" => status, "reason" => reason})
      {:ok, updated}
    end
  end

  def terminal_reservation_status?(status), do: status in @terminal_reservation_states

  defp generate_opportunities(run, spacecraft, stations, starts_at, ends_at) do
    scenario = run["scenario_snapshot"]
    pass_model = scenario["pass_model"]
    speed = run["speed"]
    cadence = max(10, round(pass_model["cadence_seconds"] / speed))
    duration = max(5, round(pass_model["duration_seconds"] / speed))
    jitter = max(0, round(pass_model["jitter_seconds"] / speed))
    start_unix = DateTime.to_unix(starts_at)
    end_unix = DateTime.to_unix(ends_at)

    for craft <- spacecraft,
        stations != [],
        window_start <- opportunity_starts(run, craft, start_unix, end_unix, cadence, jitter),
        station =
          Enum.at(stations, rem(:erlang.phash2({craft["id"], window_start}), length(stations))),
        antenna_index = rem(:erlang.phash2({window_start, craft["id"]}), station["antenna_count"]),
        window_end = min(window_start + duration, end_unix) do
      opportunity_id =
        Ids.stable("opportunity", [
          run["id"],
          craft["id"],
          station["id"],
          Integer.to_string(window_start)
        ])

      %{
        "id" => opportunity_id,
        "run_id" => run["id"],
        "spacecraft_id" => craft["id"],
        "ground_station_id" => station["id"],
        "antenna_id" => "#{station["id"]}-antenna-#{antenna_index + 1}",
        "starts_at" => window_start |> DateTime.from_unix!() |> DateTime.to_iso8601(),
        "ends_at" => window_end |> DateTime.from_unix!() |> DateTime.to_iso8601(),
        "synthetic" => true,
        "model" => "deterministic_pass_v1"
      }
    end
    |> Enum.sort_by(& &1["starts_at"])
  end

  defp opportunity_starts(run, craft, start_unix, end_unix, cadence, jitter) do
    base_offset = rem(:erlang.phash2({run["seed"], craft["id"]}), cadence)

    jitter_offset =
      rem(:erlang.phash2({craft["id"], run["seed"], :jitter}), jitter * 2 + 1) - jitter

    offset = max(0, base_offset + jitter_offset)
    first = start_unix + rem(cadence - rem(start_unix - offset, cadence), cadence)

    Stream.iterate(first, &(&1 + cadence))
    |> Enum.take_while(&(&1 < end_unix))
  end

  defp spacecraft_inventory(scenario) do
    count = scenario["spacecraft_count"]
    width = max(3, count |> Integer.to_string() |> String.length())

    Enum.map(1..count, fn index ->
      id =
        "#{scenario["spacecraft_prefix"]}-#{index |> Integer.to_string() |> String.pad_leading(width, "0")}"

      %{"id" => id, "name" => "Spacecraft #{index}", "synthetic" => true}
    end)
  end

  defp normalize_stations(stations) when is_list(stations) and stations != [] do
    normalized =
      Enum.map(stations, fn station ->
        %{
          "id" => Map.fetch!(station, "id"),
          "name" => Map.get(station, "name", Map.fetch!(station, "id")),
          "region" => Map.get(station, "region", "simulated"),
          "antenna_count" => integer(station, "antenna_count", 1),
          "synthetic" => true
        }
      end)

    if Enum.all?(normalized, &(&1["antenna_count"] > 0)) do
      {:ok, normalized}
    else
      {:error, {:invalid, "antenna_count"}}
    end
  rescue
    KeyError -> {:error, {:invalid, "ground_stations.id"}}
  end

  defp normalize_stations(_stations), do: {:error, {:invalid, "ground_stations"}}

  defp initial_reservation_status(run, attrs) do
    fault_profile = run["scenario_snapshot"]["fault_profile"]

    if fault_profile["provider_outage"] or
         deterministic_fault?(
           run,
           attrs,
           "scheduling_rejection",
           fault_profile["scheduling_rejection_rate"]
         ) do
      "rejected"
    else
      "pending"
    end
  end

  defp deterministic_fault?(_run, _attrs, _kind, rate) when rate <= 0, do: false
  defp deterministic_fault?(_run, _attrs, _kind, rate) when rate >= 1, do: true

  defp deterministic_fault?(run, attrs, kind, rate) do
    roll = :erlang.phash2({run["seed"], attrs["opportunity_id"], kind}, 1_000_000) / 1_000_000
    roll < rate
  end

  defp validate_reservation_resources(run, attrs) do
    scenario = run["scenario_snapshot"]
    spacecraft_ids = MapSet.new(spacecraft_inventory(scenario), & &1["id"])

    station =
      Enum.find(scenario["ground_stations"], &(&1["id"] == Map.get(attrs, "ground_station_id")))

    cond do
      not MapSet.member?(spacecraft_ids, Map.get(attrs, "spacecraft_id")) ->
        {:error, {:invalid, "spacecraft_id"}}

      is_nil(station) ->
        {:error, {:invalid, "ground_station_id"}}

      not valid_antenna?(station, Map.get(attrs, "antenna_id")) ->
        {:error, {:invalid, "antenna_id"}}

      true ->
        :ok
    end
  end

  defp ensure_capacity(attrs, starts_at, ends_at) do
    conflict? =
      Store.list(:reservation)
      |> Enum.any?(fn reservation ->
        reservation["run_id"] == attrs["run_id"] and
          reservation["antenna_id"] == attrs["antenna_id"] and
          reservation["status"] not in @terminal_reservation_states and
          intervals_overlap?(reservation, starts_at, ends_at)
      end)

    if conflict?, do: {:error, {:conflict, "antenna is already reserved"}}, else: :ok
  end

  defp intervals_overlap?(reservation, starts_at, ends_at) do
    {:ok, existing_start, _offset} = DateTime.from_iso8601(reservation["starts_at"])
    {:ok, existing_end, _offset} = DateTime.from_iso8601(reservation["ends_at"])

    DateTime.compare(starts_at, existing_end) == :lt and
      DateTime.compare(ends_at, existing_start) == :gt
  end

  defp existing_idempotent_reservation(nil), do: nil
  defp existing_idempotent_reservation(""), do: nil

  defp existing_idempotent_reservation(key) do
    Enum.find(Store.list(:reservation), &(&1["idempotency_key"] == key))
  end

  defp maybe_filter_by_ids(resources, []), do: resources
  defp maybe_filter_by_ids(resources, ids), do: Enum.filter(resources, &(&1["id"] in ids))

  defp apply_run_transition(%{"state" => state}, _action) when state in @terminal_run_states,
    do: {:error, {:conflict, "run is terminal"}}

  defp apply_run_transition(%{"state" => "running"} = run, "pause") do
    {:ok,
     run
     |> timestamp_update()
     |> Map.put("state", "paused")
     |> Map.put("paused_at", now_iso8601())}
  end

  defp apply_run_transition(%{"state" => "paused"} = run, "resume") do
    paused_seconds =
      case DateTime.from_iso8601(run["paused_at"] || "") do
        {:ok, paused_at, _offset} -> max(0, DateTime.diff(DateTime.utc_now(), paused_at))
        _error -> 0
      end

    {:ok,
     run
     |> timestamp_update()
     |> Map.put("state", "running")
     |> Map.put("paused_at", nil)
     |> Map.update("paused_duration_seconds", paused_seconds, &(&1 + paused_seconds))}
  end

  defp apply_run_transition(run, "stop") do
    {:ok,
     run
     |> timestamp_update()
     |> Map.put("state", "completed")
     |> Map.put("stopped_at", now_iso8601())}
  end

  defp apply_run_transition(_run, action),
    do: {:error, {:conflict, "cannot #{action} run in its current state"}}

  defp timestamp_update(resource), do: Map.put(resource, "updated_at", now_iso8601())

  defp valid_antenna?(station, antenna_id) when is_binary(antenna_id) do
    prefix = station["id"] <> "-antenna-"

    with true <- String.starts_with?(antenna_id, prefix),
         suffix <- String.replace_prefix(antenna_id, prefix, ""),
         {number, ""} <- Integer.parse(suffix) do
      number >= 1 and number <= station["antenna_count"]
    else
      _other -> false
    end
  end

  defp valid_antenna?(_station, _antenna_id), do: false

  defp run_event_type("pause"), do: "run.paused"
  defp run_event_type("resume"), do: "run.resumed"
  defp run_event_type("stop"), do: "run.stopped"

  defp ensure_run_searchable(%{"state" => state}) when state in ["running", "paused"], do: :ok
  defp ensure_run_searchable(_run), do: {:error, {:conflict, "run is not active"}}

  defp parse_datetime(params, key) do
    case DateTime.from_iso8601(Map.get(params, key, "")) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _error -> {:error, {:invalid, key}}
    end
  end

  defp validate_interval(starts_at, ends_at) do
    if DateTime.compare(starts_at, ends_at) == :lt,
      do: :ok,
      else: {:error, {:invalid, "ends_at must be after starts_at"}}
  end

  defp validate_range(value, min, max, _field) when value >= min and value <= max, do: :ok
  defp validate_range(_value, _min, _max, field), do: {:error, {:invalid, field}}

  defp validate_speed(speed) when speed > 0 and speed <= 1_000, do: :ok
  defp validate_speed(_speed), do: {:error, {:invalid, "speed"}}

  defp integer(map, key, default), do: Map.get(map, key, default) |> normalize_integer(default)
  defp number(map, key, default), do: Map.get(map, key, default) |> normalize_number(default)

  defp nested_integer(map, parent, key, default) do
    map |> Map.get(parent, %{}) |> integer(key, default)
  end

  defp normalize_integer(value, _default) when is_integer(value), do: value

  defp normalize_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {integer, ""} -> integer
      _other -> default
    end
  end

  defp normalize_integer(_value, default), do: default

  defp normalize_number(value, _default) when is_number(value), do: value

  defp normalize_number(value, default) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> number
      _other -> default
    end
  end

  defp normalize_number(_value, default), do: default

  defp emit(type, resource, data) do
    data =
      %{
        "mission_profile_ref" => resource["mission_profile_ref"],
        "provider_contact_ref" => resource["provider_contact_ref"],
        "status" => resource["status"]
      }
      |> Map.merge(data)
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    Store.append_event(%{
      "schema_version" => Contract.version(),
      "type" => type,
      "resource_type" => event_resource_type(type),
      "run_id" => resource["run_id"] || resource["id"],
      "resource_id" => resource["id"],
      "request_id" => nil,
      "data" => data
    })
  end

  defp event_resource_type("run." <> _rest), do: "run"
  defp event_resource_type(_type), do: "reservation"

  defp now_iso8601, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
