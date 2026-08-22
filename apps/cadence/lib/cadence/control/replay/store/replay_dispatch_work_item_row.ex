defmodule Cadence.Control.Replay.Store.ReplayDispatchWorkItemRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.ApplicationDispatch.WorkItem

  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "replay_dispatch_work_items" do
    field(:dispatch_decision_id, :string)
    field(:binding_rule_id, :string)
    field(:handler_key, :string)

    timestamps()
  end

  @required_fields [:dispatch_decision_id, :binding_rule_id, :handler_key]

  @spec changeset(binary(), WorkItem.t()) :: Ecto.Changeset.t()
  def changeset(dispatch_decision_id, %WorkItem{} = work_item)
      when is_binary(dispatch_decision_id) do
    %__MODULE__{}
    |> cast(
      %{
        dispatch_decision_id: dispatch_decision_id,
        binding_rule_id: work_item.binding_rule_id,
        handler_key: Atom.to_string(work_item.handler_key)
      },
      all_fields()
    )
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:dispatch_decision_id)
  end

  defp all_fields do
    [:dispatch_decision_id, :binding_rule_id, :handler_key]
  end
end
