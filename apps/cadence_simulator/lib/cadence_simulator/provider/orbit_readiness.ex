defmodule CadenceSimulator.Provider.OrbitReadiness do
  @moduledoc """
  Provider-owned orbit readiness for opportunity generation.

  `source_kind` `"synthetic"` (the default) answers from the scenario's configured status.
  `"uploaded"` (#968) answers from the element sets Cadence uploaded
  (`CadenceSimulator.Provider.Ephemeris`): every searched spacecraft needs an upload whose epoch
  is at most 14 days old at the search start, else the status is `"missing"` or `"expired"`. A
  configured status other than `"current"` still wins, as a fault the scenario injects.
  """

  alias CadenceSimulator.Provider.{Contract, Ephemeris}

  @statuses ~w(current missing expired processing)
  @source_kinds ~w(synthetic uploaded)
  @default_validity_seconds 7 * 24 * 60 * 60
  @maximum_validity_seconds 365 * 24 * 60 * 60

  @spec normalize(term()) :: {:ok, map()} | {:error, {:invalid, binary()}}
  def normalize(attrs) when is_map(attrs) do
    attrs = Contract.sanitize(attrs)
    status = Map.get(attrs, "status", "current")
    validity_seconds = Map.get(attrs, "validity_seconds", @default_validity_seconds)
    source_kind = Map.get(attrs, "source_kind", "synthetic")

    cond do
      status not in @statuses ->
        {:error, {:invalid, "orbit_readiness.status is invalid"}}

      source_kind not in @source_kinds ->
        {:error, {:invalid, "orbit_readiness.source_kind must be synthetic or uploaded"}}

      not is_integer(validity_seconds) or validity_seconds <= 0 or
          validity_seconds > @maximum_validity_seconds ->
        {:error, {:invalid, "orbit_readiness.validity_seconds is invalid"}}

      true ->
        {:ok,
         %{
           "status" => status,
           "source_kind" => source_kind,
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

    evidence =
      if config["source_kind"] == "uploaded" and config["status"] == "current",
        do: uploaded_evidence(run, params, config),
        else: evidence(run, params, config)

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

  # The worst readiness over the searched spacecraft: missing, then expired, then current.
  # The evidence names the upload when there is exactly one spacecraft (Cadence's searches).
  defp uploaded_evidence(run, params, config) do
    starts_at = parsed_time(params["starts_at"], DateTime.utc_now())
    refs = List.wrap(params["spacecraft_refs"])
    readiness = Enum.map(refs, &spacecraft_readiness(run, &1, starts_at))

    status =
      if refs == [],
        do: "missing",
        else: Enum.find(["missing", "expired"], "current", &worst?(readiness, &1))

    single =
      case readiness do
        [{_status, upload, valid_until}] -> {upload, valid_until}
        _many -> {nil, nil}
      end

    uploaded_document(run, config, status, single)
  end

  defp spacecraft_readiness(run, ref, starts_at) do
    case Ephemeris.fetch(run, ref) do
      {:ok, upload} ->
        valid_until = Ephemeris.valid_until(upload)
        status = if DateTime.after?(valid_until, starts_at), do: "current", else: "expired"
        {status, upload, valid_until}

      {:error, :not_found} ->
        {"missing", nil, nil}
    end
  end

  defp worst?(readiness, status), do: Enum.any?(readiness, &(elem(&1, 0) == status))

  defp uploaded_document(run, config, status, {nil, _valid_until}) do
    uploaded_document(run, config, status, %{}, nil)
  end

  defp uploaded_document(run, config, status, {upload, valid_until}) do
    uploaded_document(run, config, status, upload, DateTime.to_iso8601(valid_until))
  end

  defp uploaded_document(run, config, status, upload, valid_until) do
    %{
      "status" => status,
      "source_kind" => "uploaded",
      "ephemeris_ref" => upload["content_sha256"],
      "version" => config["version"],
      "epoch" => upload["epoch"],
      "valid_from" => upload["epoch"],
      "valid_until" => valid_until,
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
