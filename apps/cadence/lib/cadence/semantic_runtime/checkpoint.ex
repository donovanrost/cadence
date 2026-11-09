defmodule Cadence.SemanticRuntime.Checkpoint do
  @moduledoc """
  A versioned, integrity-checked reference to an already durable semantic state.

  Publication must share the fenced commit transaction (or validate the recovered
  writer under the head lock). No second copy of the potentially large state is
  stored. Bump `@version` when engine/state semantics make old snapshots unsafe;
  incompatible checkpoints fall back to deterministic replay, which must succeed
  before a replacement is published. Full-history auditing remains Store.recover/3.
  """
  use Ecto.Schema
  import Ecto.Query

  alias Cadence.Platform.ContentHash
  alias Cadence.Repo
  alias Cadence.Runtime.PartitionKey
  alias Cadence.SemanticRuntime.{CommitRow, State, Terms}

  @version 1
  @identity [:organization_scope_id, :mission_id, :partition_id, :runtime_basis_sha256]
  @primary_key false
  schema "semantic_runtime_checkpoints" do
    field(:organization_scope_id, :string, primary_key: true)
    field(:mission_id, :string, primary_key: true)
    field(:partition_id, :string, primary_key: true)
    field(:runtime_basis_sha256, :string, primary_key: true)
    field(:version, :integer)
    field(:commit_sequence, :integer)
    field(:integrity_sha256, :string)
  end

  def load(spec, key, through_sequence) do
    restore(fetch(spec, key), through_sequence)
  end

  def fetch(spec, key) do
    __MODULE__
    |> where(
      [c],
      c.organization_scope_id == ^(spec.organization_id || "__unscoped_organization__")
    )
    |> where([c], c.mission_id == ^spec.mission_id)
    |> where([c], c.partition_id == ^PartitionKey.identifier(key))
    |> where([c], c.runtime_basis_sha256 == ^spec.runtime_basis_sha256)
    |> Repo.one()
  end

  # The head is locked by Store. A stale writer cannot reach this publication.
  def publish(%CommitRow{} = row) do
    attrs = Map.take(row, @identity)

    checkpoint =
      struct!(
        __MODULE__,
        Map.merge(attrs, %{
          version: @version,
          commit_sequence: row.commit_sequence,
          integrity_sha256: checksum(row)
        })
      )

    Repo.insert!(checkpoint,
      conflict_target: @identity,
      on_conflict: {:replace, [:version, :commit_sequence, :integrity_sha256]}
    )

    :ok
  end

  def restore(nil, _through), do: {:missing, %State{}, 0}

  def restore(%{version: version}, _through) when version != @version,
    do: {:incompatible, %State{}, 0}

  def restore(%{commit_sequence: sequence}, through) when sequence > through,
    do: {:ahead, %State{}, 0}

  def restore(checkpoint, _through) do
    fields = @identity ++ [:commit_sequence, :commit_id, :state_term]

    row =
      CommitRow
      |> where([r], r.commit_sequence == ^checkpoint.commit_sequence)
      |> select([r], struct(r, ^fields))
      |> Repo.one()

    with %CommitRow{} <- row,
         true <- Map.take(checkpoint, @identity) == Map.take(row, @identity),
         true <- checkpoint.integrity_sha256 == checksum(row),
         {:ok, %State{} = state} <- Terms.decode(row.state_term) do
      {:hit, state, row.commit_sequence}
    else
      _ -> {:invalid, %State{}, 0}
    end
  rescue
    ArgumentError -> {:invalid, %State{}, 0}
  end

  defp checksum(row) do
    ContentHash.term_sha256(
      {@version, Map.take(row, @identity), row.commit_sequence, row.commit_id, row.state_term}
    )
  end
end
