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
  alias Cadence.Persistence.OrganizationScope

  @spec verify(BindingSet.t()) :: :ok
  def verify(%BindingSet{} = written) do
    # The stored version's organization is the set's, else the mission's (OrganizationScope), as
    # storage resolves it: a set written without one is still membership when its mission has one.
    organization_id =
      written.organization_id || OrganizationScope.organization_id_for_mission(written.mission_id)

    scoped = %{written | organization_id: organization_id}
    {:ok, reference} = Governance.rows_expansion(scoped)

    # The Replay reader's read (mission only), and the readers that name the organization.
    compare(written, reference, "fetch_binding_set/3", fn ->
      Governance.fetch_binding_set(written.mission_id, written.binding_set_id, written.version)
    end)

    if organization_id do
      compare(written, reference, "fetch_binding_set/4", fn ->
        Governance.fetch_binding_set(
          organization_id,
          written.mission_id,
          written.binding_set_id,
          written.version
        )
      end)
    end

    :ok
  end

  defp compare(written, reference, reader, read) do
    case read.() do
      {:ok, read} ->
        cond do
          read != reference ->
            mismatch(
              written,
              "#{reader} expands the stored version to a different set than its rows"
            )

          BindingSet.content_sha256(read) != BindingSet.content_sha256(reference) ->
            mismatch(written, "#{reader} hashes the stored version differently from its rows")

          true ->
            :ok
        end

      {:error, reason} ->
        mismatch(written, "#{reader} does not read the stored version back: #{inspect(reason)}")
    end
  end

  defp mismatch(%BindingSet{} = set, why) do
    raise "binding set #{set.binding_set_id} v#{set.version} (mission #{set.mission_id}): #{why} (#447)"
  end
end
