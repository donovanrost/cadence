defmodule Cadence.Persistence.Schemas.DispatchWorkItemRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.ApplicationDispatch.WorkItem

  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "application_dispatch_work_items" do
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
    |> cast(row_attrs(dispatch_decision_id, work_item), all_fields())
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:dispatch_decision_id)
  end

  @spec row_attrs(binary(), WorkItem.t(), keyword()) :: map()
  def row_attrs(dispatch_decision_id, %WorkItem{} = work_item, opts \\ [])
      when is_binary(dispatch_decision_id) do
    inserted_at = Keyword.get(opts, :inserted_at)

    %{
      dispatch_decision_id: dispatch_decision_id,
      binding_rule_id: work_item.binding_rule_id,
      handler_key: Atom.to_string(work_item.handler_key)
    }
    |> maybe_put_inserted_at(inserted_at)
  end

  defp all_fields do
    [:dispatch_decision_id, :binding_rule_id, :handler_key]
  end

  defp maybe_put_inserted_at(attrs, nil), do: attrs
  defp maybe_put_inserted_at(attrs, inserted_at), do: Map.put(attrs, :inserted_at, inserted_at)
end
