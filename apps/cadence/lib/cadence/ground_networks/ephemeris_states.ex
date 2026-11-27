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

  @doc "Counts by status per provider for the mission: `%{provider_id => %{status => n}}`."
  @spec counts(binary(), binary()) :: %{optional(binary()) => %{optional(binary()) => integer()}}
  def counts(organization_id, mission_id) do
    from(row in Row,
      where: row.organization_id == ^organization_id and row.mission_id == ^mission_id,
      group_by: [row.provider_id, row.status],
      select: {row.provider_id, row.status, count()}
    )
    |> Repo.all()
    |> Enum.reduce(%{}, fn {provider_id, status, n}, acc ->
      Map.update(acc, provider_id, %{status => n}, &Map.put(&1, status, n))
    end)
  end
end
