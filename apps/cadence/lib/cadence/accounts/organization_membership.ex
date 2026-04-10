defmodule Cadence.Accounts.OrganizationMembership do
  @moduledoc """
  Durable human membership inside an organization tenant.
  """

  alias Cadence.Ids

  @roles [:organization_admin, :member]
  @lifecycle_states [:active, :revoked]

  @type capability :: :organization_admin
  @type role :: :organization_admin | :member
  @type lifecycle_state :: :active | :revoked

  @type t :: %__MODULE__{
          organization_membership_id: binary(),
          user_id: binary(),
          organization_id: binary(),
          role: role(),
          lifecycle_state: lifecycle_state(),
          metadata: map()
        }

  defstruct [
    :organization_membership_id,
    :user_id,
    :organization_id,
    :role,
    lifecycle_state: :active,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      organization_membership_id:
        Map.get(
          attrs,
          :organization_membership_id,
          Map.get(attrs, "organization_membership_id", Ids.new("orgmem"))
        ),
      user_id: map_fetch!(attrs, :user_id, "user_id"),
      organization_id: map_fetch!(attrs, :organization_id, "organization_id"),
      role:
        attrs
        |> Map.get(:role, Map.get(attrs, "role", :member))
        |> normalize_role(),
      lifecycle_state:
        attrs
        |> Map.get(:lifecycle_state, Map.get(attrs, "lifecycle_state", :active))
        |> normalize_lifecycle_state(),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end

  @spec roles() :: [role()]
  def roles, do: @roles

  @spec lifecycle_states() :: [lifecycle_state()]
  def lifecycle_states, do: @lifecycle_states

  @spec normalize_role(role() | binary()) :: role()
  def normalize_role(:organization_admin), do: :organization_admin
  def normalize_role("organization_admin"), do: :organization_admin
  def normalize_role(:member), do: :member
  def normalize_role("member"), do: :member

  @spec normalize_lifecycle_state(lifecycle_state() | binary()) :: lifecycle_state()
  def normalize_lifecycle_state(:active), do: :active
  def normalize_lifecycle_state("active"), do: :active
  def normalize_lifecycle_state(:revoked), do: :revoked
  def normalize_lifecycle_state("revoked"), do: :revoked

  @spec active?(t()) :: boolean()
  def active?(%__MODULE__{lifecycle_state: :active}), do: true
  def active?(%__MODULE__{}), do: false

  @spec capabilities(t() | nil) :: [capability()]
  def capabilities(nil), do: []

  def capabilities(%__MODULE__{} = membership) do
    if active?(membership), do: role_capabilities(membership.role), else: []
  end

  @spec role_capabilities(role()) :: [capability()]
  def role_capabilities(:organization_admin), do: [:organization_admin]
  def role_capabilities(:member), do: []

  defp map_fetch!(attrs, atom_key, string_key) when is_map(attrs) do
    case Map.get(attrs, atom_key, Map.get(attrs, string_key)) do
      nil -> raise KeyError, key: atom_key, term: attrs
      value -> value
    end
  end
end
