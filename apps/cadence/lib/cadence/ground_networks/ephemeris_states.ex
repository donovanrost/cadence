defmodule Cadence.GroundNetworks.EphemerisStates do
  @moduledoc """
  What Cadence last did to give each mission provider each spacecraft's current orbit (#968),
  one row per (mission, provider, spacecraft):

  - `uploaded`: the provider accepted the current element set (`element_set_id`);
  - `failed`: the upload failed (`reason`, `attempts`); it is retried from `next_retry_at`;
  - `lookup`: the provider looks orbits up by NORAD id, and the current set carries one;
  - `norad_id_missing`: the provider looks orbits up by NORAD id, and the current set has none.

  Written by `Cadence.Control.Providers.EphemerisUploads`, in bulk; read as counts per provider.
  """

  import Ecto.Query

  alias Cadence.GroundNetworks.EphemerisStateRow, as: Row
  alias Cadence.Repo

  @statuses ~w(uploaded failed lookup norad_id_missing)
  @chunk 1_000

  @type state :: %{
          required(:provider_id) => binary(),
          required(:spacecraft_id) => binary(),
          required(:status) => binary(),
          optional(atom()) => term()
        }

  @spec statuses() :: [binary()]
  def statuses, do: @statuses

  @doc "The stored rows for these pairs, keyed by `{provider_id, spacecraft_id}` (one query)."
  @spec fetch_many(binary(), binary(), [{binary(), binary()}]) :: %{
          optional({binary(), binary()}) => map()
        }
  def fetch_many(_organization_id, _mission_id, []), do: %{}

  def fetch_many(organization_id, mission_id, pairs) do
    spacecraft_ids = pairs |> Enum.map(&elem(&1, 1)) |> Enum.uniq()

    from(row in Row,
      where:
        row.organization_id == ^organization_id and row.mission_id == ^mission_id and
          row.spacecraft_id in ^spacecraft_ids
    )
    |> Repo.all()
    |> Map.new(&{{&1.provider_id, &1.spacecraft_id}, Map.from_struct(&1)})
    |> Map.take(pairs)
  end

  @doc "Replaces these pairs' rows (one statement per #{@chunk})."
  @spec put_all(binary(), binary(), [state()], DateTime.t()) :: :ok
  def put_all(_organization_id, _mission_id, [], _now), do: :ok

  def put_all(organization_id, mission_id, states, now) do
    rows =
      Enum.map(states, fn state ->
        %{
          organization_id: organization_id,
          mission_id: mission_id,
          provider_id: state.provider_id,
          spacecraft_id: state.spacecraft_id,
          status: state.status,
          element_set_id: Map.get(state, :element_set_id),
          content_sha256: Map.get(state, :content_sha256),
          provider_spacecraft_ref: Map.get(state, :provider_spacecraft_ref),
          provider_version: Map.get(state, :provider_version),
          attempts: Map.get(state, :attempts, 0),
          reason: Map.get(state, :reason),
          next_retry_at: Map.get(state, :next_retry_at),
          updated_at: now
        }
      end)

    rows
    |> Enum.chunk_every(@chunk)
    |> Enum.each(fn chunk ->
      Repo.insert_all(Row, chunk,
        on_conflict:
          {:replace_all_except, [:organization_id, :mission_id, :provider_id, :spacecraft_id]},
        conflict_target: [:mission_id, :provider_id, :spacecraft_id]
      )
    end)
  end

  @doc """
  Claims the failed uploads due at `now` for a retry: moves their `next_retry_at` to
  `lease_until` and answers them as `{organization_id, mission_id, spacecraft_id, provider_id}`
  (one statement; the run that retries them overwrites the rows).
  """
  @spec claim_due(DateTime.t(), DateTime.t()) :: [{binary(), binary(), binary(), binary()}]
  def claim_due(now, lease_until) do
    {_count, claimed} =
      from(row in Row,
        where: row.status == "failed" and row.next_retry_at <= ^now,
        select: {row.organization_id, row.mission_id, row.spacecraft_id, row.provider_id}
      )
      |> Repo.update_all(set: [next_retry_at: lease_until])

    Enum.uniq(claimed)
  end

  # The pairs a run would act on, as `ProviderScheduling` resolves them: each spacecraft's
  # active, enabled downlink routing rules bind it, through a provider-managed transport, to the
  # mission provider VERSION that transport pins (the highest when two transports pin different
  # versions); the provider-side spacecraft ref is the spacecraft's first source endpoint, by id,
  # with a non-blank source_ref (no ref, no route, no pair); and the current element set is the
  # newest epoch. The ref and the set are each one LIMIT 1 index probe per bound pair, so the
  # work scales with bound pairs, never with element-set history. The orbit source is the pinned
  # version's declared one; NULL (undeclared) behaves as lookup. An upload pair is `uploaded`
  # only when the stored row holds the current set for the same pinned version and ref.
  # `$1`/`$2` narrow to one mission when the caller passes `scoped: true`.
  defp bound_sql(scoped?) do
    mission = fn alias ->
      if scoped?, do: "#{alias}.organization_id = $1 AND #{alias}.mission_id = $2", else: "TRUE"
    end

    """
    WITH bound AS (
      SELECT DISTINCT ON (r.organization_id, r.mission_id, r.spacecraft_id, t.mission_provider_id)
        r.organization_id, r.mission_id, r.spacecraft_id,
        t.mission_provider_id AS provider_id, t.mission_provider_version AS provider_version
      FROM comms_routing_rules r
      JOIN comms_transports t
        ON t.organization_id = r.organization_id AND t.mission_id = r.mission_id
       AND t.transport_id = r.transport_id AND t.version = r.transport_version
      WHERE #{mission.("r")} AND r.lifecycle_state = 'active' AND r.enabled
        AND r.direction IN ('inbound', 'bidirectional') AND t.origin = 'provider_managed'
      ORDER BY r.organization_id, r.mission_id, r.spacecraft_id, t.mission_provider_id,
        t.mission_provider_version DESC
    ),
    pairs AS (
      SELECT b.organization_id, b.mission_id, b.provider_id, b.spacecraft_id,
        b.provider_version,
        CASE
          WHEN p.capabilities_document -> 'orbit' ->> 'source' = 'accepts_ephemeris_upload' THEN
            CASE
              WHEN s.status = 'uploaded' AND s.element_set_id = c.element_set_id
               AND s.provider_version = b.provider_version
               AND s.provider_spacecraft_ref = ref.source_ref THEN 'uploaded'
              WHEN s.status = 'failed' THEN 'failed'
              ELSE 'pending'
            END
          WHEN c.norad_id IS NULL THEN 'norad_id_missing'
          ELSE 'lookup'
        END AS bucket
      FROM bound b
      JOIN mission_providers p
        ON p.organization_id = b.organization_id AND p.mission_id = b.mission_id
       AND p.provider_id = b.provider_id AND p.version = b.provider_version
       AND p.lifecycle_state <> 'archived'
      CROSS JOIN LATERAL (
        SELECT se.source_ref
        FROM mission_source_endpoints se
        WHERE se.mission_id = b.mission_id AND se.spacecraft_id = b.spacecraft_id
          AND se.organization_id = b.organization_id AND btrim(se.source_ref) <> ''
        ORDER BY se.source_endpoint_id
        LIMIT 1
      ) ref
      CROSS JOIN LATERAL (
        SELECT e.element_set_id, e.norad_id
        FROM orbit_element_sets e
        WHERE e.mission_id = b.mission_id AND e.spacecraft_id = b.spacecraft_id
          AND e.organization_id = b.organization_id
        ORDER BY e.epoch DESC, e.element_set_id DESC
        LIMIT 1
      ) c
      LEFT JOIN provider_ephemeris_states s
        ON s.mission_id = b.mission_id AND s.provider_id = b.provider_id
       AND s.spacecraft_id = b.spacecraft_id
    )
    """
  end

  @doc """
  Per provider, its bound spacecraft that have a current element set, by bucket (one grouped
  query): `%{provider_id => %{"uploaded" | "failed" | "pending" | "lookup" | "norad_id_missing"
  => n}}`. A spacecraft without a current element set is in no bucket. For an upload provider a
  spacecraft is `uploaded` (it holds the current set for the pinned version and current ref),
  `failed`, or `pending` (never tried, a newer set, or a changed ref or pinned version not yet
  sent); for any other provider, undeclared included, `lookup` or `norad_id_missing` by whether
  the current set carries a NORAD id.
  """
  @spec buckets(binary(), binary()) :: %{optional(binary()) => %{optional(binary()) => integer()}}
  def buckets(organization_id, mission_id) do
    sql = bound_sql(true) <> "SELECT provider_id, bucket, count(*) FROM pairs GROUP BY 1, 2"

    sql
    |> Repo.query!([organization_id, mission_id])
    |> Map.fetch!(:rows)
    |> Enum.reduce(%{}, fn [provider_id, bucket, n], acc ->
      Map.update(acc, provider_id, %{bucket => n}, &Map.put(&1, bucket, n))
    end)
  end

  @doc """
  Pending upload pairs across every mission, at most `limit` PAIRS (one query): the provider
  doesn't hold the current element set for its pinned version and current ref, and the pair
  isn't `failed` (the retry sweep owns those). Answers `{organization_id, mission_id,
  spacecraft_id, provider_id}`.
  """
  @spec pending(pos_integer()) :: [{binary(), binary(), binary(), binary()}]
  def pending(limit) do
    sql =
      bound_sql(false) <>
        """
        SELECT organization_id, mission_id, spacecraft_id, provider_id
        FROM pairs WHERE bucket = 'pending' LIMIT $1
        """

    sql
    |> Repo.query!([limit])
    |> Map.fetch!(:rows)
    |> Enum.map(&List.to_tuple/1)
  end

  @doc false
  # For the EXPLAIN shape check.
  def pending_sql, do: bound_sql(false) <> "SELECT * FROM pairs WHERE bucket = 'pending' LIMIT $1"
end
