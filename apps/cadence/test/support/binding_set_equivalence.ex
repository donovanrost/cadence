defmodule Cadence.TestSupport.BindingSetEquivalence do
  @moduledoc """
  The #447 equivalence check, on every binding set any test persists (config/test.exs points
  `:binding_set_storage_verifier` here; dev and prod never do).

  After a version is written, it is read back through `Governance.fetch_binding_set/4`, the path
  every reader uses (generation, catalog move, revision, activation apply, replay, the runtime
  reconciler), and compared with the rows-form expansion of the same set (`rows_expansion/1`, the
  expansion before #447): the structs must be equal, field for field and in order, and hash alike
  (`BindingSet.content_sha256/1`, #108). A difference raises, naming the version, so the suite of
  whichever path wrote it fails there, not in a later apply.
  """

  alias Cadence.ApplicationDispatch.BindingSet
  alias Cadence.Governance

  @spec verify(BindingSet.t()) :: :ok
  # A set persisted without an organization (a test helper path) is stored as rows, whose read is
  # the reference itself: nothing to compare.
  def verify(%BindingSet{organization_id: nil}), do: :ok

  def verify(%BindingSet{} = written) do
    {:ok, reference} = Governance.rows_expansion(written)

    read =
      case Governance.fetch_binding_set(
             written.organization_id,
             written.mission_id,
             written.binding_set_id,
             written.version
           ) do
        {:ok, read} ->
          read

        {:error, reason} ->
          mismatch(written, "the stored version does not read back: #{inspect(reason)}")
      end

    cond do
      read != reference ->
        mismatch(written, "the stored version expands to a different set than its rows")

      BindingSet.content_sha256(read) != BindingSet.content_sha256(reference) ->
        mismatch(written, "the stored version hashes differently from its rows")

      true ->
        :ok
    end
  end

  defp mismatch(%BindingSet{} = set, why) do
    raise "binding set #{set.binding_set_id} v#{set.version} (mission #{set.mission_id}): #{why} (#447)"
  end
end
