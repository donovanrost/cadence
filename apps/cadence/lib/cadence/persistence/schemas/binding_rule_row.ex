defmodule Cadence.Persistence.Schemas.BindingRuleRow do
  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.ApplicationDispatch.BindingRule
  alias Cadence.Persistence.JsonDocument

  @timestamps_opts [type: :utc_datetime_usec, updated_at: false]

  schema "governed_binding_rules" do
    field(:binding_rule_id, :string)
    field(:binding_set_row_id, :id)
    field(:capability_instance_id, :string)
    field(:handler_key, :string)
    field(:selector_scope, :map, default: %{})
    field(:selector_match, :map, default: %{})
    field(:priority, :integer)
    field(:fanout_mode, :string)

    timestamps()
  end

  @required_fields [
    :binding_rule_id,
    :binding_set_row_id,
    :capability_instance_id,
    :handler_key,
    :selector_scope,
    :selector_match,
    :priority,
    :fanout_mode
  ]

  @spec changeset(pos_integer(), BindingRule.t(), map()) :: Ecto.Changeset.t()
  def changeset(binding_set_row_id, %BindingRule{} = binding_rule, configuration_attrs)
      when is_integer(binding_set_row_id) and is_map(configuration_attrs) do
    attrs =
      Map.merge(
        %{
          binding_rule_id: binding_rule.binding_rule_id,
          binding_set_row_id: binding_set_row_id,
          capability_instance_id: binding_rule.capability_instance_id,
          handler_key: Map.fetch!(configuration_attrs, :handler_key),
          selector_scope: selector_scope_document(binding_rule),
          selector_match: selector_match_document(binding_rule),
          priority: binding_rule.priority,
          fanout_mode: Atom.to_string(binding_rule.fanout_mode)
        },
        configuration_attrs
      )

    %__MODULE__{}
    |> cast(attrs, all_fields())
    |> validate_required(@required_fields)
    |> foreign_key_constraint(:binding_set_row_id)
    |> unique_constraint([:binding_set_row_id, :binding_rule_id],
      name: :governed_binding_rules_binding_set_rule_idx
    )
  end

  defp all_fields do
    [
      :binding_rule_id,
      :binding_set_row_id,
      :capability_instance_id,
      :handler_key,
      :selector_scope,
      :selector_match,
      :priority,
      :fanout_mode
    ]
  end

  defp selector_scope_document(%BindingRule{} = binding_rule) do
    JsonDocument.encode(%{
      target_scope: BindingRule.target_scope(binding_rule),
      source_endpoint_ref: BindingRule.source_endpoint_ref(binding_rule)
    })
  end

  defp selector_match_document(%BindingRule{} = binding_rule) do
    JsonDocument.encode(%{
      packet_kind: BindingRule.packet_kind(binding_rule),
      apid: BindingRule.apid(binding_rule)
    })
  end
end
