defmodule Cadence.Persistence.Schemas.CommsRoutingRuleRow do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  alias Cadence.Comms.RoutingRule
  alias Cadence.Persistence.JsonDocument
  alias Cadence.Persistence.OrganizationScope

  @primary_key false
  @timestamps_opts [type: :utc_datetime_usec]

  schema "comms_routing_rules" do
    field(:routing_rule_id, :string)
    field(:organization_id, :string)
    field(:mission_id, :string)
    field(:spacecraft_id, :string)
    field(:lifecycle_state, :string)
    field(:display_name, :string)
    field(:purpose_label, :string)
    field(:direction, :string)
    field(:transport_id, :string)
    field(:transport_version, :integer)
    field(:provider_path_ref, :string)
    field(:role, :string)
    field(:enabled, :boolean, default: true)
    field(:materialized_link_assignment_id, :string)
    field(:metadata, :map, default: %{})

    timestamps()
  end

  @required_fields [
    :routing_rule_id,
    :mission_id,
    :spacecraft_id,
    :lifecycle_state,
    :display_name,
    :purpose_label,
    :direction,
    :transport_id,
    :transport_version,
    :role,
    :enabled,
    :metadata
  ]

  @spec changeset(RoutingRule.t()) :: Ecto.Changeset.t()
  def changeset(%RoutingRule{} = routing_rule) do
    %__MODULE__{}
    |> cast(domain_attrs(routing_rule), all_fields())
    |> OrganizationScope.put_organization_id()
    |> validate_required(@required_fields)
    |> validate_length(:display_name, min: 1, max: 200)
    |> validate_length(:purpose_label, min: 1, max: 120)
    |> unique_constraint([:mission_id, :routing_rule_id],
      name: :comms_routing_rules_scope_idx
    )
  end

  @spec to_domain(struct()) :: RoutingRule.t()
  def to_domain(%__MODULE__{} = row) do
    RoutingRule.new(%{
      routing_rule_id: row.routing_rule_id,
      organization_id: row.organization_id,
      mission_id: row.mission_id,
      spacecraft_id: row.spacecraft_id,
      lifecycle_state: row.lifecycle_state,
      display_name: row.display_name,
      purpose_label: row.purpose_label,
      direction: row.direction,
      transport_id: row.transport_id,
      transport_version: row.transport_version,
      provider_path_ref: row.provider_path_ref,
      role: row.role,
      enabled?: row.enabled,
      materialized_link_assignment_id: row.materialized_link_assignment_id,
      metadata: JsonDocument.unwrap_value(row.metadata)
    })
  end

  defp domain_attrs(%RoutingRule{} = routing_rule) do
    %{
      routing_rule_id: routing_rule.routing_rule_id,
      organization_id: routing_rule.organization_id,
      mission_id: routing_rule.mission_id,
      spacecraft_id: routing_rule.spacecraft_id,
      lifecycle_state: Atom.to_string(routing_rule.lifecycle_state),
      display_name: routing_rule.display_name,
      purpose_label: routing_rule.purpose_label,
      direction: Atom.to_string(routing_rule.direction),
      transport_id: routing_rule.transport_id,
      transport_version: routing_rule.transport_version,
      provider_path_ref: routing_rule.provider_path_ref,
      role: Atom.to_string(routing_rule.role),
      enabled: routing_rule.enabled?,
      materialized_link_assignment_id: routing_rule.materialized_link_assignment_id,
      metadata: JsonDocument.wrap_value(routing_rule.metadata)
    }
  end

  defp all_fields do
    [
      :routing_rule_id,
      :organization_id,
      :mission_id,
      :spacecraft_id,
      :lifecycle_state,
      :display_name,
      :purpose_label,
      :direction,
      :transport_id,
      :transport_version,
      :provider_path_ref,
      :role,
      :enabled,
      :materialized_link_assignment_id,
      :metadata
    ]
  end
end
