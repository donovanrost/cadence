defmodule Cadence.SemanticRuntime.HeadRow do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "semantic_runtime_heads" do
    field(:organization_scope_id, :string, primary_key: true)
    field(:mission_id, :string, primary_key: true)
    field(:partition_id, :string, primary_key: true)
    field(:runtime_basis_sha256, :string)
    field(:generation, :integer)
    field(:ownership_epoch, :integer, default: 0)
    field(:commit_sequence, :integer, default: 0)
  end
end
