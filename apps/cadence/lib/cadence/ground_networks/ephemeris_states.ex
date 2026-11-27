defmodule Cadence.GroundNetworks.EphemerisStates do
  @moduledoc """
  What Cadence last did to give each mission provider each spacecraft's current orbit (#968),
  one row per (mission, provider, spacecraft):

  - `uploaded`: the provider accepted the current element set (`element_set_id`);
  - `failed`: the upload failed (`reason`, `attempts`); it is retried from `next_retry_at`;
  - `not_ready`: routing rules bind the pair but no route to the provider is ready (`reason`, the
    scheduling refusal); nothing was sent, and it is re-checked from `next_retry_at` (#974);
  - `lookup`: the provider looks orbits up by NORAD id, and the current set carries one;
  - `norad_id_missing`: the provider looks orbits up by NORAD id, and the current set has none.

  Written by `Cadence.Control.Providers.EphemerisUploads`, in bulk; read as counts per provider.
  """

  import Ecto.Query

  alias Cadence.GroundNetworks.EphemerisStateRow, as: Row
  alias Cadence.Repo

  @statuses ~w(uploaded failed not_ready lookup norad_id_missing)
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
          bound_provider_version: Map.get(state, :bound_provider_version),
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
  Claims the pairs due at `now` for another try: a failed upload, a `not_ready` pair to re-check,
  or one uploaded through a lower pinned version than its routing rules bind (to move to the
  higher once its route is ready). Moves their `next_retry_at` to `lease_until` and answers them
  as `{organization_id, mission_id, spacecraft_id, provider_id}` (one statement; the run that
  tries them overwrites the rows).
  """
  @spec claim_due(DateTime.t(), DateTime.t()) :: [{binary(), binary(), binary(), binary()}]
  def claim_due(now, lease_until) do
    {_count, claimed} =
      from(row in Row,
        where: not is_nil(row.next_retry_at) and row.next_retry_at <= ^now,
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
  # version's declared one; NULL (undeclared) behaves as lookup. A stored outcome (`uploaded`,
  # `failed`, `not_ready`, `lookup`, `norad_id_missing`) decides the bucket only while its basis
  # still holds: the same current set, the same bound (pinned) version and the same ref. The run
  # knows readiness, so its outcome wins over this query's view of the orbit source (a lower
  # ready version may differ from the highest pinned one, #974). Without a matching outcome every
  # pair is `pending`, whatever its orbit source: the run decides (upload, lookup,
  # norad_id_missing or not_ready), so a new set, a new ref or a newly pinned version is acted on
  # now instead of waiting out an old backoff or re-check, and a lookup pair is pending only until
  # its first run records an outcome.
  # `scope`: `:all` missions, `:mission` (`$1`/`$2`), or `:spacecraft` (`$1`/`$2` and the ids in
  # `$3`).
  @doc false
  # The bound-pairs CTE (`pairs`) for `EphemerisFindings`, scoped `:mission` ($1, $2).
  def pairs_sql(:mission), do: bound_sql(:mission)

  defp bound_sql(scope) do
    mission = fn alias ->
      case scope do
        :all ->
          "TRUE"

        :mission ->
          "#{alias}.organization_id = $1 AND #{alias}.mission_id = $2"

        :spacecraft ->
          "#{alias}.organization_id = $1 AND #{alias}.mission_id = $2 AND " <>
            "#{alias}.spacecraft_id = ANY($3::text[])"
      end
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
        b.provider_version, ref.source_ref AS provider_spacecraft_ref,
        c.element_set_id, s.reason AS state_reason, s.next_retry_at AS state_next_retry_at,
        s.attempts AS state_attempts, s.updated_at AS state_updated_at,
        CASE
          WHEN s.status IS NOT NULL AND s.element_set_id = c.element_set_id
           AND s.bound_provider_version = b.provider_version
           AND s.provider_spacecraft_ref = ref.source_ref THEN s.status
          ELSE 'pending'
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
  query): `%{provider_id => %{"uploaded" | "failed" | "not_ready" | "pending" | "lookup" |
  "norad_id_missing" => n}}`. A spacecraft without a current element set is in no bucket. A
  recorded outcome counts while its set, pinned version and ref still hold: `uploaded`, `failed`,
  `not_ready` (bound, but no route to the provider is ready), `lookup`, `norad_id_missing`.
  Otherwise an upload provider's spacecraft is `pending` (never tried, a newer set, or a changed
  ref or pinned version not yet sent), and any other provider's is `lookup` or
  `norad_id_missing` by whether the current set carries a NORAD id.
  """
  @spec buckets(binary(), binary()) :: %{optional(binary()) => %{optional(binary()) => integer()}}
  def buckets(organization_id, mission_id) do
    sql = bound_sql(:mission) <> "SELECT provider_id, bucket, count(*) FROM pairs GROUP BY 1, 2"

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
      bound_sql(:all) <>
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
  def pending_sql, do: bound_sql(:all) <> "SELECT * FROM pairs WHERE bucket = 'pending' LIMIT $1"

  @doc """
  The bound pairs of these spacecraft that have a current element set, as the reconcile reads
  them (one query): `%{{provider_id, spacecraft_id} => %{provider_version, provider_spacecraft_ref,
  element_set_id}}`, where `provider_version` is the highest version the routing rules pin. The
  run records a pair it finds bound but without a ready route against exactly this basis.
  """
  @spec bound_pairs(binary(), binary(), [binary()]) :: %{optional({binary(), binary()}) => map()}
  def bound_pairs(_organization_id, _mission_id, []), do: %{}

  def bound_pairs(organization_id, mission_id, spacecraft_ids) do
    sql =
      bound_sql(:spacecraft) <>
        """
        SELECT pairs.provider_id, pairs.spacecraft_id, pairs.provider_version,
          pairs.provider_spacecraft_ref, pairs.element_set_id,
          ARRAY(
            SELECT r.routing_rule_id
            FROM comms_routing_rules r
            JOIN comms_transports t
              ON t.organization_id = r.organization_id AND t.mission_id = r.mission_id
             AND t.transport_id = r.transport_id AND t.version = r.transport_version
            WHERE r.organization_id = pairs.organization_id AND r.mission_id = pairs.mission_id
              AND r.spacecraft_id = pairs.spacecraft_id
              AND t.mission_provider_id = pairs.provider_id
              AND r.lifecycle_state = 'active' AND r.enabled
              AND r.direction IN ('inbound', 'bidirectional') AND t.origin = 'provider_managed'
          ) AS rule_ids
        FROM pairs
        """

    sql
    |> Repo.query!([organization_id, mission_id, spacecraft_ids])
    |> Map.fetch!(:rows)
    |> Map.new(fn [provider_id, spacecraft_id, version, ref, set, rule_ids] ->
      {{provider_id, spacecraft_id},
       %{
         provider_version: version,
         provider_spacecraft_ref: ref,
         element_set_id: set,
         rule_ids: rule_ids
       }}
    end)
  end
end
