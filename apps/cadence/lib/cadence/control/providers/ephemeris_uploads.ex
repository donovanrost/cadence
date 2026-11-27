defmodule Cadence.Control.Providers.EphemerisUploads do
  @moduledoc """
  Gives each spacecraft's providers its current orbit (#968, slice 5a of #732).

  A run takes a batch of spacecraft, reads their current element sets (one query) and the
  providers their ready routes bind them to (`ProviderScheduling`, batched), and for each
  (provider, spacecraft) pair does what the provider's capabilities say:

  - `accepts_ephemeris_upload`: uploads the set as an OMM through the provider client, unless
    the provider already holds that content hash (`uploaded`). A failure is `failed`, retried
    with backoff (#{inspect([1, 5, 15, 60, 360])} minutes, then every 6 h) by the sweep that
    `retry_due/2` runs.
  - `looks_up_by_norad_id`: nothing to send; `lookup` when the set carries a NORAD id,
    `norad_id_missing` when it doesn't, so a provider that can't find the spacecraft is visible.

  The outcome of every pair is stored in `Cadence.GroundNetworks.EphemerisStates`, in bulk. Runs
  are staged by `Cadence.Platform.EphemerisUploadJobs` and never run in a request.
  """

  require Logger

  alias Cadence.Contacts.ProviderScheduling
  alias Cadence.Control.Providers
  alias Cadence.GroundNetworks.{ElementSets, EphemerisStates, ProviderError}
  alias Cadence.GroundNetworks.ElementSets.OmmDocument
  alias Cadence.Jobs
  alias Cadence.Platform.EphemerisUploadJobs

  @job_type :ephemeris_upload
  @backoff_minutes [1, 5, 15, 60, 360]
  @retry_lease_minutes 10
  @reconcile_limit 5_000

  @type summary :: %{optional(binary()) => non_neg_integer()}

  @doc "Runs a durable `:ephemeris_upload` job (`Cadence.Jobs.Runner`)."
  @spec execute_enqueued_run(binary()) :: {:ok, summary()} | {:error, term()}
  def execute_enqueued_run(run_id) do
    with {:ok, job} <- Jobs.fetch_job_for_run(@job_type, run_id) do
      run(job.payload["organization_id"], job.mission_id, job.payload["spacecraft_ids"] || [])
    end
  end

  @doc """
  Uploads (or checks) these spacecraft's current orbits for every bound provider. `opts`:
  `:now`, `:client` (a provider client, for tests). Answers counts by stored status.
  """
  @spec run(binary(), binary(), [binary()], keyword()) :: {:ok, summary()} | {:error, term()}
  def run(organization_id, mission_id, spacecraft_ids, opts \\ []) do
    now = Keyword.get(opts, :now, DateTime.utc_now())

    sets =
      organization_id
      |> ElementSets.current_for(mission_id, Enum.uniq(spacecraft_ids))
      |> Map.new(&{&1.spacecraft_id, &1})

    with {:ok, routes, providers} <-
           ProviderScheduling.list_ready_downlink_routes_for_fleet(
             organization_id,
             mission_id,
             Map.keys(sets)
           ) do
      bindings = bindings(routes)
      prepared = prepare(bindings, providers, opts)

      previous =
        EphemerisStates.fetch_many(
          organization_id,
          mission_id,
          Enum.map(bindings, &{&1.provider_id, &1.spacecraft_id})
        )

      states =
        Enum.map(bindings, fn binding ->
          attempt(binding, Map.fetch!(sets, binding.spacecraft_id), prepared, previous, now)
        end)

      :ok = EphemerisStates.put_all(organization_id, mission_id, states, now)
      {:ok, Enum.frequencies_by(states, & &1.status)}
    end
  end

  @doc """
  Stages a run for every spacecraft with a failed upload due at `now`, one job per mission, and
  leases those rows for #{@retry_lease_minutes} minutes so the next sweep doesn't stage them
  again before the run records its outcome. Answers how many jobs were staged.
  """
  @spec retry_due(DateTime.t()) :: non_neg_integer()
  def retry_due(now \\ DateTime.utc_now()) do
    now
    |> EphemerisStates.claim_due(DateTime.add(now, @retry_lease_minutes * 60))
    |> Enum.group_by(fn {org, mission, _id} -> {org, mission} end, &elem(&1, 2))
    |> Enum.count(fn {{organization_id, mission_id}, spacecraft_ids} ->
      {:ok, _job} =
        EphemerisUploadJobs.stage_spacecraft(organization_id, mission_id, spacecraft_ids)
    end)
  end

  @doc """
  The safety net for pairs no new element set will reach (#968): a provider newly bound, or
  newly ready, holds nothing although the spacecraft's set is unchanged. Finds every upload pair
  across all missions that is `pending` (no upload of the current set, not `failed`) in one query,
  skips missions whose upload job is already open (one query), and stages one run per remaining
  mission for its pending spacecraft. At most `limit` pairs per sweep. Answers how many jobs.
  """
  @spec reconcile(pos_integer()) :: non_neg_integer()
  def reconcile(limit \\ @reconcile_limit) do
    pending = EphemerisStates.pending(limit)
    open = if pending == [], do: MapSet.new(), else: Jobs.missions_with_open_jobs(@job_type)

    pending
    |> Enum.reject(fn {_org, mission, _id} -> MapSet.member?(open, mission) end)
    |> Enum.group_by(fn {org, mission, _id} -> {org, mission} end, &elem(&1, 2))
    |> Enum.count(fn {{organization_id, mission_id}, spacecraft_ids} ->
      {:ok, _job} =
        EphemerisUploadJobs.stage_spacecraft(organization_id, mission_id, spacecraft_ids)
    end)
  end

  @doc "When a pair that has failed `attempts` times is tried again."
  @spec next_retry_at(DateTime.t(), pos_integer()) :: DateTime.t()
  def next_retry_at(now, attempts) do
    minutes = Enum.at(@backoff_minutes, attempts - 1, List.last(@backoff_minutes))
    DateTime.add(now, minutes * 60)
  end

  # One binding per (provider, spacecraft): every ready route a spacecraft has to a provider
  # names the same provider-side spacecraft.
  defp bindings(routes) do
    for {_spacecraft_id, {:ok, %{routes: ready}}} <- routes,
        route <- ready,
        uniq: true do
      %{
        spacecraft_id: route.spacecraft_id,
        provider_id: route.provider_id,
        provider_version: route.provider_version,
        provider_spacecraft_ref: route.provider_spacecraft_ref
      }
    end
    |> Enum.uniq_by(&{&1.provider_id, &1.spacecraft_id})
  end

  defp prepare(bindings, providers, opts) do
    bindings
    |> Enum.map(&{&1.provider_id, &1.provider_version})
    |> Enum.uniq()
    |> Map.new(fn key ->
      prepared =
        with {:ok, provider} <- Map.fetch(providers, key) |> found(),
             do: Providers.prepare_ephemeris_upload(provider, opts)

      {key, prepared}
    end)
  end

  defp found({:ok, provider}), do: {:ok, provider}
  defp found(:error), do: {:error, :provider_version_not_found}

  defp attempt(binding, set, prepared, previous, now) do
    base = %{
      provider_id: binding.provider_id,
      spacecraft_id: binding.spacecraft_id,
      provider_spacecraft_ref: binding.provider_spacecraft_ref,
      element_set_id: set.element_set_id,
      content_sha256: set.content_sha256
    }

    prior = Map.get(previous, {binding.provider_id, binding.spacecraft_id})

    case Map.fetch!(prepared, {binding.provider_id, binding.provider_version}) do
      {:ok, %{orbit_source: :looks_up_by_norad_id}} ->
        Map.put(base, :status, if(set.norad_id, do: "lookup", else: "norad_id_missing"))

      {:ok, %{orbit_source: :accepts_ephemeris_upload, request: request}} ->
        upload(base, set, prior, request, now)

      {:error, reason} ->
        failed(base, prior, reason, now)
    end
  end

  # The provider already holds this content: nothing to send.
  defp upload(base, _set, %{status: "uploaded", content_sha256: sha}, _request, _now)
       when sha == base.content_sha256,
       do: Map.put(base, :status, "uploaded")

  defp upload(base, set, prior, request, now) do
    ephemeris = %{
      "omm" => OmmDocument.from_element_set(set),
      "epoch" => DateTime.to_iso8601(set.epoch),
      "content_sha256" => set.content_sha256
    }

    case request.(base.provider_spacecraft_ref, ephemeris) do
      {:ok, _stored} -> Map.put(base, :status, "uploaded")
      {:error, reason} -> failed(base, prior, reason, now)
    end
  end

  # Attempts count up while the same element set keeps failing, and start over for a new one.
  defp failed(base, prior, reason, now) do
    attempts =
      case prior do
        %{status: "failed", element_set_id: id, attempts: n} when id == base.element_set_id ->
          n + 1

        _other ->
          1
      end

    Logger.warning("Ephemeris upload failed; retrying",
      cadence_event: "ephemeris_upload.failed",
      error_class: reason_class(reason)
    )

    Map.merge(base, %{
      status: "failed",
      attempts: attempts,
      reason: reason_text(reason),
      next_retry_at: next_retry_at(now, attempts)
    })
  end

  defp reason_class(%ProviderError{category: category}), do: "provider_#{category}"
  defp reason_class(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_class(_reason), do: "other"

  # What an operator reads: never the provider's raw evidence.
  defp reason_text(%ProviderError{category: category, detail: detail}),
    do: "#{category}: #{detail}"

  defp reason_text(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp reason_text(_reason), do: "upload_failed"
end
