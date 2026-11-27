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
  `lease_until` and answers them as `{organization_id, mission_id, spacecraft_id}` (one
  statement; the run that retries them overwrites the rows).
  """
  @spec claim_due(DateTime.t(), DateTime.t()) :: [{binary(), binary(), binary()}]
  def claim_due(now, lease_until) do
    {_count, claimed} =
      from(row in Row,
        where: row.status == "failed" and row.next_retry_at <= ^now,
        select: {row.organization_id, row.mission_id, row.spacecraft_id}
      )
      |> Repo.update_all(set: [next_retry_at: lease_until])

    Enum.uniq(claimed)
  end

  # Each spacecraft's current element set (the newest epoch), and the providers its active,
  # enabled downlink routing rules bind it to through a provider-managed transport. A provider's
  # orbit source is its latest version's declared one; NULL (undeclared) behaves as lookup.
  # `$1`/`$2` narrow to one mission when the caller passes `scoped: true`.
  defp bound_sql(scoped?) do
    mission = fn alias ->
      if scoped?, do: "#{alias}.organization_id = $1 AND #{alias}.mission_id = $2", else: "TRUE"
    end

    """
    WITH current_sets AS (
      SELECT DISTINCT ON (organization_id, mission_id, spacecraft_id)
        organization_id, mission_id, spacecraft_id, element_set_id, norad_id
      FROM orbit_element_sets e
      WHERE #{mission.("e")}
      ORDER BY organization_id, mission_id, spacecraft_id, epoch DESC, element_set_id DESC
    ),
    sources AS (
      SELECT DISTINCT ON (organization_id, mission_id, provider_id)
        organization_id, mission_id, provider_id,
        capabilities_document -> 'orbit' ->> 'source' AS source
      FROM mission_providers p
      WHERE #{mission.("p")} AND p.lifecycle_state <> 'archived'
      ORDER BY organization_id, mission_id, provider_id, version DESC
    ),
    bound AS (
      SELECT DISTINCT r.organization_id, r.mission_id, r.spacecraft_id,
        t.mission_provider_id AS provider_id
      FROM comms_routing_rules r
      JOIN comms_transports t
        ON t.organization_id = r.organization_id AND t.mission_id = r.mission_id
       AND t.transport_id = r.transport_id AND t.version = r.transport_version
      WHERE #{mission.("r")} AND r.lifecycle_state = 'active' AND r.enabled
        AND r.direction IN ('inbound', 'bidirectional') AND t.origin = 'provider_managed'
    ),
    pairs AS (
      SELECT b.organization_id, b.mission_id, b.provider_id, b.spacecraft_id,
        CASE
          WHEN src.source = 'accepts_ephemeris_upload' THEN
            CASE
              WHEN s.status = 'uploaded' AND s.element_set_id = c.element_set_id THEN 'uploaded'
              WHEN s.status = 'failed' THEN 'failed'
              ELSE 'pending'
            END
          WHEN c.norad_id IS NULL THEN 'norad_id_missing'
          ELSE 'lookup'
        END AS bucket
      FROM bound b
      JOIN current_sets c
        ON c.organization_id = b.organization_id AND c.mission_id = b.mission_id
       AND c.spacecraft_id = b.spacecraft_id
      JOIN sources src
        ON src.organization_id = b.organization_id AND src.mission_id = b.mission_id
       AND src.provider_id = b.provider_id
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
  spacecraft is `uploaded` (it holds the current set), `failed`, or `pending` (never tried, or a
  newer set not yet sent); for any other provider, undeclared included, `lookup` or
  `norad_id_missing` by whether the current set carries a NORAD id.
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
  Upload pairs across every mission whose provider doesn't hold the current element set yet and
  that aren't failed (the retry sweep owns those): `pending`, as `{organization_id, mission_id,
  spacecraft_id}`, at most `limit` (one query).
  """
  @spec pending(pos_integer()) :: [{binary(), binary(), binary()}]
  def pending(limit) do
    sql =
      bound_sql(false) <>
        """
        SELECT DISTINCT organization_id, mission_id, spacecraft_id
        FROM pairs WHERE bucket = 'pending' LIMIT $1
        """

    sql
    |> Repo.query!([limit])
    |> Map.fetch!(:rows)
    |> Enum.map(&List.to_tuple/1)
  end
end
