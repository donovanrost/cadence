defmodule Cadence.Accounts.User do
  @moduledoc """
  Platform user account.
  """

  alias Cadence.Ids

  @type capability :: :platform_admin
  @type lifecycle_state :: :active | :disabled

  @type t :: %__MODULE__{
          user_id: binary(),
          email: binary(),
          display_name: binary(),
          capabilities: [capability()],
          lifecycle_state: lifecycle_state(),
          metadata: map()
        }

  defstruct [
    :user_id,
    :email,
    :display_name,
    capabilities: [],
    lifecycle_state: :active,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      user_id: Map.get(attrs, :user_id, Map.get(attrs, "user_id", Ids.new("user"))),
      email:
        attrs
        |> Map.get(:email, Map.get(attrs, "email"))
        |> normalize_email(),
      display_name: Map.fetch!(attrs, :display_name),
      capabilities:
        attrs
        |> Map.get(:capabilities, Map.get(attrs, "capabilities", []))
        |> Enum.map(&normalize_capability/1),
      lifecycle_state:
        attrs
        |> Map.get(:lifecycle_state, Map.get(attrs, "lifecycle_state", :active))
        |> normalize_lifecycle_state(),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end

  @spec normalize_capability(capability() | binary()) :: capability()
  def normalize_capability(:platform_admin), do: :platform_admin
  def normalize_capability("platform_admin"), do: :platform_admin

  @spec normalize_lifecycle_state(lifecycle_state() | binary()) :: lifecycle_state()
  def normalize_lifecycle_state(:active), do: :active
  def normalize_lifecycle_state("active"), do: :active
  def normalize_lifecycle_state(:disabled), do: :disabled
  def normalize_lifecycle_state("disabled"), do: :disabled

  @spec normalize_email(binary() | nil) :: binary() | nil
  def normalize_email(nil), do: nil

  def normalize_email(email) when is_binary(email) do
    email
    |> String.trim()
    |> String.downcase()
  end

  @spec temporary_setup_access?(t()) :: boolean()
  def temporary_setup_access?(%__MODULE__{metadata: metadata}) when is_map(metadata) do
    truthy_metadata?(metadata, "setup_access", :setup_access) or
      truthy_metadata?(metadata, "bootstrap_admin", :bootstrap_admin)
  end

  defp truthy_metadata?(metadata, string_key, atom_key)
       when is_map(metadata) and is_binary(string_key) and is_atom(atom_key) do
    Map.get(metadata, string_key) == true or Map.get(metadata, atom_key, false) == true
  end
end
