defmodule CadenceSimulator.Provider.Ephemeris do
  @moduledoc """
  Element sets uploaded to the simulated provider (#968, Provider Contract v1 ephemeris upload).

  Cadence uploads each spacecraft's current element set as an OMM (CCSDS keys, as CelesTrak
  publishes them) with its epoch and content hash. One upload is kept per run and spacecraft:
  the same content hash again is a no-op, a different one replaces it. Opportunity generation
  doesn't read uploads yet (that is #893); `OrbitReadiness` does, for a scenario whose
  `orbit_readiness.source_kind` is `"uploaded"`.
  """

  alias CadenceSimulator.Provider.{Contract, Store}

  # An upload whose epoch is older than this is expired: SGP4 drifts several km a day.
  @max_age_seconds 14 * 24 * 60 * 60
  @required_omm ~w(EPOCH MEAN_MOTION ECCENTRICITY INCLINATION RA_OF_ASC_NODE ARG_OF_PERICENTER
                   MEAN_ANOMALY)

  @spec max_age_seconds() :: pos_integer()
  def max_age_seconds, do: @max_age_seconds

  @doc """
  Stores `attrs` (`omm`, `epoch`, `content_sha256`) for the run's spacecraft `ref`. Answers
  `{:ok, upload, :created | :unchanged}`.
  """
  @spec put(map(), binary(), map()) ::
          {:ok, map(), :created | :unchanged} | {:error, :not_found | {:invalid, binary()}}
  def put(run, ref, attrs) when is_map(run) and is_binary(ref) and is_map(attrs) do
    attrs = Contract.sanitize(attrs)

    with true <- spacecraft_ref?(run, ref) || {:error, :not_found},
         {:ok, omm} <- omm(attrs["omm"]),
         {:ok, epoch} <- epoch(attrs["epoch"]),
         {:ok, sha} <- sha(attrs["content_sha256"]) do
      case fetch(run, ref) do
        {:ok, %{"content_sha256" => ^sha} = stored} ->
          {:ok, stored, :unchanged}

        _other ->
          upload = %{
            "id" => key(run, ref),
            "run_id" => run["id"],
            "spacecraft_ref" => ref,
            "omm" => omm,
            "epoch" => DateTime.to_iso8601(epoch),
            "content_sha256" => sha,
            "received_at" => DateTime.to_iso8601(DateTime.utc_now())
          }

          {:ok, stored} = Store.put(:ephemeris, upload)
          {:ok, stored, :created}
      end
    end
  end

  def put(_run, _ref, _attrs), do: {:error, {:invalid, "ephemeris must be an object"}}

  @spec fetch(map(), binary()) :: {:ok, map()} | {:error, :not_found}
  def fetch(run, ref), do: Store.fetch(:ephemeris, key(run, ref))

  @doc "When `upload` stops being usable: its epoch plus the maximum age."
  @spec valid_until(map()) :: DateTime.t()
  def valid_until(%{"epoch" => epoch}) do
    {:ok, at, _offset} = DateTime.from_iso8601(epoch)
    DateTime.add(at, @max_age_seconds, :second)
  end

  @doc "Whether `ref` names one of the run's spacecraft (`<prefix>-<n>`, 1 ≤ n ≤ count)."
  @spec spacecraft_ref?(map(), term()) :: boolean()
  def spacecraft_ref?(%{"scenario_snapshot" => scenario}, ref) when is_binary(ref) do
    prefix = scenario["spacecraft_prefix"] <> "-"
    count = scenario["spacecraft_count"]
    width = max(3, byte_size(Integer.to_string(count)))

    with ^prefix <> digits <- ref,
         true <- byte_size(digits) == width,
         {index, ""} <- Integer.parse(digits) do
      index >= 1 and index <= count
    else
      _other -> false
    end
  end

  def spacecraft_ref?(_run, _ref), do: false

  defp key(run, ref), do: run["id"] <> "/" <> ref

  defp omm(omm) when is_map(omm) do
    case Enum.reject(@required_omm, &Map.has_key?(omm, &1)) do
      [] -> {:ok, omm}
      missing -> {:error, {:invalid, "ephemeris.omm is missing " <> Enum.join(missing, ", ")}}
    end
  end

  defp omm(_omm), do: {:error, {:invalid, "ephemeris.omm must be an OMM object"}}

  defp epoch(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, at, _offset} -> {:ok, at}
      _error -> {:error, {:invalid, "ephemeris.epoch must be an ISO 8601 time"}}
    end
  end

  defp epoch(_value), do: {:error, {:invalid, "ephemeris.epoch must be an ISO 8601 time"}}

  defp sha(value) when is_binary(value) and byte_size(value) == 64 do
    if value =~ ~r/\A[0-9a-f]{64}\z/,
      do: {:ok, value},
      else: {:error, {:invalid, "ephemeris.content_sha256 must be 64 lowercase hex digits"}}
  end

  defp sha(_value),
    do: {:error, {:invalid, "ephemeris.content_sha256 must be 64 lowercase hex digits"}}
end
