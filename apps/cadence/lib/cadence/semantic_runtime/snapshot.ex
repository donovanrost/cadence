defmodule Cadence.SemanticRuntime.Snapshot do
  @moduledoc """
  The partition's semantic snapshot (DECISIONS #94/#96): its whole `State` (latest values,
  algorithm memory, monitoring state) and, for every journal stream it consumed, the offset the
  state includes (`resume`).

  A snapshot is the recovery point: load it, then replay each stream's journal from its `resume`
  offset. Replay is duplicate-free because effect ids are derived from (stream, offset) (#476,
  #480). The journal's durable processing cursor never passes the offsets of the partition's last
  snapshot (`Cadence.Runtime.IngressJournalConsumer`), so the journal always still holds what a
  replay needs.

  One row per partition and runtime basis, replaced in place. Written by `Store.snapshot/5` under
  the partition's head lock, so a fenced (stale) owner cannot write. Bump `@version` when
  engine/state semantics make an old snapshot unsafe; an incompatible one reads as missing.
  """
  use Ecto.Schema

  import Ecto.Query

  alias Cadence.Platform.ContentHash
  alias Cadence.Repo
  alias Cadence.Runtime.PartitionKey
  alias Cadence.SemanticRuntime.{State, Terms}

  @version 1
  @identity [:organization_scope_id, :mission_id, :partition_id, :runtime_basis_sha256]

  @type resume :: %{binary() => non_neg_integer()}
  @type t :: %__MODULE__{}

  @primary_key false
  schema "semantic_runtime_snapshots" do
    field(:organization_scope_id, :string, primary_key: true)
    field(:mission_id, :string, primary_key: true)
    field(:partition_id, :string, primary_key: true)
    field(:runtime_basis_sha256, :string, primary_key: true)
    field(:version, :integer)
    field(:ownership_epoch, :integer)
    field(:state_term, :binary)
    field(:resume, :map, default: %{})
    field(:integrity_sha256, :string)
    field(:snapshotted_at, :utc_datetime_usec)
  end

  @doc """
  Replaces the partition's snapshot; returns the size of its encoded state in bytes. The caller
  holds the head lock and has validated the writer.
  """
  @spec put(map(), PartitionKey.t(), pos_integer(), State.t(), resume()) ::
          {:ok, non_neg_integer()}
  def put(spec, %PartitionKey{} = key, epoch, %State{} = state, resume) when is_map(resume) do
    identity = identity(spec, key)
    state_term = Terms.encode(state)

    snapshot =
      struct!(
        __MODULE__,
        Map.merge(identity, %{
          version: @version,
          ownership_epoch: epoch,
          state_term: state_term,
          resume: resume,
          integrity_sha256: checksum(identity, state_term, resume),
          snapshotted_at: DateTime.utc_now()
        })
      )

    Repo.insert!(snapshot,
      conflict_target: @identity,
      on_conflict:
        {:replace,
         [:version, :ownership_epoch, :state_term, :resume, :integrity_sha256, :snapshotted_at]}
    )

    {:ok, byte_size(state_term)}
  end

  @doc """
  `{:ok, state, resume}` for the partition's snapshot, `:missing` when it has none, and
  `{:invalid, reason}` for one that is incompatible or fails its integrity check (recovery treats
  that as missing, and the next snapshot replaces it).
  """
  @spec fetch(map(), PartitionKey.t()) ::
          {:ok, State.t(), resume()} | :missing | {:invalid, atom()}
  def fetch(spec, %PartitionKey{} = key) do
    identity = identity(spec, key)

    __MODULE__
    |> where(^Enum.to_list(identity))
    |> Repo.one()
    |> restore(identity)
  end

  defp restore(nil, _identity), do: :missing

  defp restore(%__MODULE__{version: version}, _identity) when version != @version,
    do: {:invalid, :incompatible_version}

  defp restore(%__MODULE__{} = row, identity) do
    with true <- checksum(identity, row.state_term, row.resume) == row.integrity_sha256,
         {:ok, %State{} = state} <- Terms.decode(row.state_term) do
      {:ok, state, row.resume}
    else
      _ -> {:invalid, :integrity}
    end
  end

  defp identity(spec, key) do
    %{
      organization_scope_id: spec.organization_id || "__unscoped_organization__",
      mission_id: spec.mission_id,
      partition_id: PartitionKey.identifier(key),
      runtime_basis_sha256: spec.runtime_basis_sha256
    }
  end

  defp checksum(identity, state_term, resume),
    do: ContentHash.term_sha256({@version, Map.take(identity, @identity), state_term, resume})
end
