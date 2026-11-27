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

  A pair the routing rules bind but with no ready route to the provider is `not_ready` (#974),
  with the scheduling refusal as its reason. Nothing is sent, the reconcile doesn't stage it again
  while its set, pinned version and ref are unchanged, and the retry sweep re-checks it every
  60 minutes so a route that becomes ready is picked up. When two transports pin versions of one
  provider, the run uses the highest whose route is READY; a pair uploaded through a lower
  version than the rules bind is re-checked on the same cadence so it moves up once that route
  is ready.

  The outcome of every pair is stored in `Cadence.GroundNetworks.EphemerisStates`, in bulk. Runs
  are staged by `Cadence.Platform.EphemerisUploadJobs` and never run in a request.
  """

  require Logger

  alias Cadence.Contacts.ProviderScheduling
  alias Cadence.Control.Providers
  alias Cadence.GroundNetworks.{ElementSets, EphemerisStates, ProviderError}
  alias Cadence.GroundNetworks.ElementSets.OmmDocument
  alias Cadence.Jobs
  alias Cadence.Jobs.OpenMissions
  alias Cadence.Platform.{EphemerisUploadJobs, ScopedReadUpdates}

  @job_type :ephemeris_upload
  @backoff_minutes [1, 5, 15, 60, 360]
  @retry_lease_minutes 10
  @recheck_minutes 60
  @reconcile_limit 5_000

  @type summary :: %{optional(binary()) => non_neg_integer()}

  @doc "Runs a durable `:ephemeris_upload` job (`Cadence.Jobs.Runner`)."
  @spec execute_enqueued_run(binary()) :: {:ok, summary()} | {:error, term()}
  def execute_enqueued_run(run_id) do
    with {:ok, job} <- Jobs.fetch_job_for_run(@job_type, run_id) do
      run(job.payload["organization_id"], job.mission_id, job.payload["spacecraft_ids"] || [],
        pairs: payload_pairs(job.payload["pairs"])
      )
    end
  end

  @doc """
  Uploads (or checks) these spacecraft's current orbits for their bound providers. `opts`:
  `:now`; `:pairs`, a list of `{spacecraft_id, provider_id}` to attempt only those (the retry
  and reconcile sweeps; nil, the default, attempts every bound provider); `:client` (a provider
  client, for tests). Answers counts by stored status.
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
      pairs = Keyword.get(opts, :pairs)
      bound = EphemerisStates.bound_pairs(organization_id, mission_id, Map.keys(sets))
      bindings = routes |> bindings() |> only(pairs)
      not_ready = not_ready(bound, bindings, pairs)
      prepared = prepare(bindings, providers, opts)

      previous =
        EphemerisStates.fetch_many(
          organization_id,
          mission_id,
          Enum.map(bindings, &{&1.provider_id, &1.spacecraft_id}) ++
            Enum.map(not_ready, &elem(&1, 0))
        )

      states =
        Enum.map(bindings, fn binding ->
          binding
          |> attempt(Map.fetch!(sets, binding.spacecraft_id), prepared, previous, now)
          |> bound_to(Map.get(bound, {binding.provider_id, binding.spacecraft_id}), now)
        end) ++
          Enum.map(not_ready, fn {{provider_id, spacecraft_id}, basis} ->
            not_ready_state(provider_id, Map.fetch!(sets, spacecraft_id), basis, routes, now)
          end)

      :ok = EphemerisStates.put_all(organization_id, mission_id, states, now)
      if Enum.any?(states, &changed?(&1, previous)), do: published(organization_id, mission_id)
      {:ok, Enum.frequencies_by(states, & &1.status)}
    end
  end

  @doc """
  Stages a run for every (spacecraft, provider) pair with a failed upload due at `now`, one job
  per mission attempting exactly those pairs, and leases those rows for #{@retry_lease_minutes}
  minutes so the next sweep doesn't stage them again before the run records its outcome.
  Answers how many jobs were staged.
  """
  @spec retry_due(DateTime.t()) :: non_neg_integer()
  def retry_due(now \\ DateTime.utc_now()) do
    now
    |> EphemerisStates.claim_due(DateTime.add(now, @retry_lease_minutes * 60))
    |> stage_pairs()
  end

  @doc """
  The safety net for pairs no new element set will reach (#968): a provider newly bound or
  ready, a changed provider-side ref, or a newly pinned provider version holds nothing for the
  unchanged set. Finds at most `limit` PAIRS across all missions that are `pending` (one query,
  `EphemerisStates.pending/1`), skips missions whose upload job is already open (one query), and
  stages one run per remaining mission that attempts exactly those pairs. Answers how many jobs.
  """
  @spec reconcile(pos_integer()) :: non_neg_integer()
  def reconcile(limit \\ @reconcile_limit) do
    pending = EphemerisStates.pending(limit)
    open = if pending == [], do: MapSet.new(), else: OpenMissions.of_type(@job_type)

    pending
    |> Enum.reject(fn {_org, mission, _sc, _provider} -> MapSet.member?(open, mission) end)
    |> stage_pairs()
  end

  # One job per mission for these `{org, mission, spacecraft_id, provider_id}` pairs.
  defp stage_pairs(pairs) do
    pairs
    |> Enum.group_by(fn {org, mission, _sc, _provider} -> {org, mission} end, fn {_o, _m, sc,
                                                                                  provider} ->
      {sc, provider}
    end)
    |> Enum.count(fn {{organization_id, mission_id}, pairs} ->
      {:ok, _job} = EphemerisUploadJobs.stage_pairs(organization_id, mission_id, pairs)
    end)
  end

  defp payload_pairs(nil), do: nil

  defp payload_pairs(pairs) when is_list(pairs),
    do: Enum.map(pairs, fn [sc, provider] -> {sc, provider} end)

  defp only(bindings, nil), do: bindings

  defp only(bindings, pairs) do
    wanted = MapSet.new(pairs)
    Enum.filter(bindings, &MapSet.member?(wanted, {&1.spacecraft_id, &1.provider_id}))
  end

  @doc "When a pair that has failed `attempts` times is tried again."
  @spec next_retry_at(DateTime.t(), pos_integer()) :: DateTime.t()
  def next_retry_at(now, attempts) do
    minutes = Enum.at(@backoff_minutes, attempts - 1, List.last(@backoff_minutes))
    DateTime.add(now, minutes * 60)
  end

  # What the providers read and the provider_ephemeris findings show of a state; a run that
  # changes none of it for any pair publishes nothing (a refreshed retry time alone is no change).
  @shown [
    :status,
    :element_set_id,
    :provider_version,
    :bound_provider_version,
    :provider_spacecraft_ref,
    :reason
  ]

  defp changed?(state, previous) do
    case Map.get(previous, {state.provider_id, state.spacecraft_id}) do
      nil -> true
      prior -> Map.take(prior, @shown) != Map.new(@shown, &{&1, Map.get(state, &1)})
    end
  end

  # After the states are stored (outside any transaction): the providers read's `ephemeris` and
  # the `provider_ephemeris` attention items both derive from them (#972).
  defp published(organization_id, mission_id) do
    ScopedReadUpdates.publish(:providers_changed, organization_id, mission_id)
    ScopedReadUpdates.publish(:attention_changed, organization_id, mission_id)
  end

  # The bound pairs (as the reconcile reads them) with no ready route, among the ones asked for.
  defp not_ready(bound, bindings, pairs) do
    ready = MapSet.new(bindings, &{&1.provider_id, &1.spacecraft_id})
    wanted = if pairs, do: MapSet.new(pairs, fn {sc, provider} -> {provider, sc} end)

    Enum.reject(bound, fn {key, _basis} ->
      MapSet.member?(ready, key) or (wanted != nil and not MapSet.member?(wanted, key))
    end)
  end

  defp not_ready_state(provider_id, set, basis, routes, now) do
    %{
      provider_id: provider_id,
      spacecraft_id: set.spacecraft_id,
      status: "not_ready",
      element_set_id: set.element_set_id,
      content_sha256: set.content_sha256,
      provider_spacecraft_ref: basis.provider_spacecraft_ref,
      provider_version: basis.provider_version,
      bound_provider_version: basis.provider_version,
      reason: refusal(Map.get(routes, set.spacecraft_id), basis.rule_ids),
      next_retry_at: DateTime.add(now, @recheck_minutes * 60)
    }
  end

  @doc false
  # Why this provider's route isn't ready: the `ProviderScheduling` findings on the routing rules
  # that bind the spacecraft to THIS provider (a finding's `resource_id` is its rule). A finding
  # on another provider's rule never names this pair's cause; when none matches, the reason is
  # the generic `no_ready_route`. A spacecraft-wide scheduling error applies to every provider.
  @spec refusal(term(), [binary()]) :: binary()
  def refusal({:ok, %{findings: findings}}, rule_ids) when is_list(findings) do
    rules = MapSet.new(rule_ids || [])

    findings
    |> Enum.filter(&MapSet.member?(rules, &1[:resource_id]))
    |> Enum.map(&to_string(&1.code))
    |> Enum.min(fn -> "no_ready_route" end)
  end

  def refusal({:error, reason}, _rule_ids) when is_atom(reason), do: Atom.to_string(reason)
  def refusal(_none, _rule_ids), do: "no_ready_route"

  # Records the version the routing rules bind alongside the one used, and re-checks any outcome
  # reached through a lower version than they bind (uploaded, lookup or norad_id_missing alike),
  # so the pair moves to the bound version once its route is ready. A failed or not_ready state
  # keeps its own retry time.
  defp bound_to(state, nil, _now),
    do: Map.put(state, :bound_provider_version, state.provider_version)

  defp bound_to(state, basis, now) do
    state = Map.put(state, :bound_provider_version, basis.provider_version)

    if state.provider_version < basis.provider_version and
         Map.get(state, :next_retry_at) == nil,
       do: Map.put(state, :next_retry_at, DateTime.add(now, @recheck_minutes * 60)),
       else: state
  end

  # One binding per (provider, spacecraft): every ready route a spacecraft has to a provider
  # names the same provider-side spacecraft (its first mapped source endpoint).
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
    # Two transports may pin different versions of one provider: the highest READY one (#974).
    |> Enum.sort_by(& &1.provider_version, :desc)
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
      provider_version: binding.provider_version,
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

  # The provider already holds this content at this ref, for this pinned version: nothing to
  # send. A changed ref or version sends again.
  defp upload(base, _set, %{status: "uploaded"} = prior, _request, _now)
       when prior.content_sha256 == base.content_sha256 and
              prior.provider_spacecraft_ref == base.provider_spacecraft_ref and
              prior.provider_version == base.provider_version,
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
  defp same_target?(prior, base) do
    prior.element_set_id == base.element_set_id and
      prior.provider_spacecraft_ref == base.provider_spacecraft_ref and
      prior.provider_version == base.provider_version
  end

  # Attempts count up only while the same set keeps failing to the same pinned version and ref; a
  # new set or a new target starts over.
  defp failed(base, prior, reason, now) do
    attempts =
      case prior do
        %{status: "failed", attempts: n} = prior when is_integer(n) ->
          if same_target?(prior, base), do: n + 1, else: 1

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
