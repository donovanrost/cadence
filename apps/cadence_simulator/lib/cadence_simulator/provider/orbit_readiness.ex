defmodule CadenceSimulator.Provider.OrbitReadiness do
  @moduledoc "Provider-owned synthetic orbit readiness for opportunity generation."

  alias CadenceSimulator.Provider.Contract

  @statuses ~w(current missing expired processing)
  @default_validity_seconds 7 * 24 * 60 * 60
  @maximum_validity_seconds 365 * 24 * 60 * 60

  @spec normalize(term()) :: {:ok, map()} | {:error, {:invalid, binary()}}
  def normalize(attrs) when is_map(attrs) do
    attrs = Contract.sanitize(attrs)
    status = Map.get(attrs, "status", "current")
    validity_seconds = Map.get(attrs, "validity_seconds", @default_validity_seconds)

    cond do
      status not in @statuses ->
        {:error, {:invalid, "orbit_readiness.status is invalid"}}

      not is_integer(validity_seconds) or validity_seconds <= 0 or
          validity_seconds > @maximum_validity_seconds ->
        {:error, {:invalid, "orbit_readiness.validity_seconds is invalid"}}

      true ->
        {:ok,
         %{
           "status" => status,
           "source_kind" => Map.get(attrs, "source_kind", "synthetic"),
           "ephemeris_ref" => Map.get(attrs, "ephemeris_ref", "synthetic-ephemeris-v1"),
           "version" => Map.get(attrs, "version", 1),
           "validity_seconds" => validity_seconds
         }}
    end
  end

  def normalize(_attrs), do: {:error, {:invalid, "orbit_readiness must be an object"}}

  @spec for_search(map(), map()) :: {:ok, map()} | {:error, {:orbit_not_ready, map()}}
  def for_search(run, params) when is_map(run) and is_map(params) do
    config = get_in(run, ["scenario_snapshot", "orbit_readiness"]) || elem(normalize(%{}), 1)
    evidence = evidence(run, params, config)

    if evidence["status"] == "current",
      do: {:ok, evidence},
      else: {:error, {:orbit_not_ready, evidence}}
  end

  defp evidence(run, params, config) do
    epoch = run["started_at"]
    starts_at = parsed_time(params["starts_at"], DateTime.utc_now())
    validity_seconds = config["validity_seconds"]

    valid_until =
      case config["status"] do
        "expired" -> DateTime.add(starts_at, -1, :second)
        _status -> DateTime.add(starts_at, validity_seconds, :second)
      end

    %{
      "status" => config["status"],
      "source_kind" => config["source_kind"],
      "ephemeris_ref" =>
        if(config["status"] == "missing", do: nil, else: config["ephemeris_ref"]),
      "version" => config["version"],
      "epoch" => epoch,
      "valid_from" => epoch,
      "valid_until" => DateTime.to_iso8601(valid_until),
      "provider_environment_ref" => run["provider_environment_ref"]
    }
    |> Contract.sanitize()
  end

  defp parsed_time(value, fallback) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _error -> fallback
    end
  end

  defp parsed_time(_value, fallback), do: fallback
end
