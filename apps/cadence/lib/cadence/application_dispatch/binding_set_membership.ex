defmodule Cadence.ApplicationDispatch.BindingSetMembership do
  @moduledoc """
  A binding set the runtime holds as the membership it is stored as (#450, ADR-020 phase 4a): the
  version's shared templates (one per distinct configuration), which endpoint uses which, and the
  packet definitions they reference, loaded once. Nothing per spacecraft is built until a partition
  asks for its endpoint (`BindingSetIndex.select/2`), and then only that endpoint's rows are
  expanded and hydrated, by the code a full read uses.

  It lives here, beside `BindingSet`, because both the governance context that stores it and the
  runtime that selects from it use it; the expansion is a function the governance context puts in
  (`expand_member`, `expand_all`), so the runtime never depends on a storage module.

  It is only built by `Cadence.Governance.fetch_binding_set_for_runtime/5`, after the version's
  integrity was checked (its hash is the activation's, its members and artifacts are the version's,
  each artifact hashes to its key), so the content hash is not recomputed from an expansion.
  Copy-safe: plain data, no process or connection.
  """

  alias Cadence.ApplicationDispatch.BindingSet

  @enforce_keys [
    :shell,
    :content_sha256,
    :members,
    :templates,
    :packets,
    :expand_member,
    :expand_all
  ]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          shell: BindingSet.t(),
          content_sha256: binary(),
          members: %{(binary() | nil) => binary()},
          templates: %{binary() => map()},
          packets: map(),
          # (membership, endpoint | nil) -> the BindingSet slice of that endpoint's member
          expand_member: (t(), binary() | nil -> BindingSet.t()),
          # membership -> the whole BindingSet, as a full read hydrates it
          expand_all: (t() -> BindingSet.t())
        }
end
