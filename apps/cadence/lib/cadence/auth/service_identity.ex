defmodule Cadence.Auth.ServiceIdentity do
  @moduledoc """
  Organization- or mission-scoped service identity used for API and internal
  automation authentication.
  """

  alias Cadence.Ids

  @type capability :: :organization_admin | :mission_admin
  @type lifecycle_state :: :active | :disabled

  @type t :: %__MODULE__{
          service_identity_id: binary(),
          organization_id: binary(),
          mission_id: binary() | nil,
          display_name: binary(),
          capabilities: [capability()],
          lifecycle_state: lifecycle_state(),
          token_hint: binary() | nil,
          metadata: map()
        }

  defstruct [
    :service_identity_id,
    :organization_id,
    :mission_id,
    :display_name,
    :token_hint,
    capabilities: [],
    lifecycle_state: :active,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      service_identity_id:
        Map.get(
          attrs,
          :service_identity_id,
          Map.get(attrs, "service_identity_id", Ids.new("svc"))
        ),
      organization_id: Map.fetch!(attrs, :organization_id),
      mission_id: Map.get(attrs, :mission_id, Map.get(attrs, "mission_id")),
      display_name: Map.fetch!(attrs, :display_name),
      capabilities:
        attrs
        |> Map.get(:capabilities, Map.get(attrs, "capabilities", []))
        |> Enum.map(&normalize_capability/1),
      lifecycle_state:
        attrs
        |> Map.get(:lifecycle_state, Map.get(attrs, "lifecycle_state", :active))
        |> normalize_lifecycle_state(),
      token_hint: Map.get(attrs, :token_hint, Map.get(attrs, "token_hint")),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end

  @spec mission_scoped?(t()) :: boolean()
  def mission_scoped?(%__MODULE__{mission_id: mission_id}),
    do: is_binary(mission_id) and mission_id != ""

  @spec normalize_capability(capability() | binary()) :: capability()
  def normalize_capability(:organization_admin), do: :organization_admin
  def normalize_capability("organization_admin"), do: :organization_admin
  def normalize_capability(:mission_admin), do: :mission_admin
  def normalize_capability("mission_admin"), do: :mission_admin

  defp normalize_lifecycle_state(:active), do: :active
  defp normalize_lifecycle_state("active"), do: :active
  defp normalize_lifecycle_state(:disabled), do: :disabled
  defp normalize_lifecycle_state("disabled"), do: :disabled
end
