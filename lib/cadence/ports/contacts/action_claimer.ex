defmodule Cadence.Ports.Contacts.ActionClaimer do
  @moduledoc """
  Port (behavior) for claiming contact actions via recordables.

  This provides idempotent action execution by inserting a
  ContactActionDispatched recordable with a unique contact_action_id.
  """

  @type action :: struct()
  @type context :: %{
          required(:organization_id) => String.t(),
          required(:mission_id) => String.t(),
          optional(:bucket_id) => String.t(),
          optional(:actor_id) => String.t() | nil
        }

  @callback claim(action(), context()) :: :ok | {:error, :already_claimed} | {:error, term()}

  @spec impl() :: module()
  def impl do
    Application.get_env(
      :cadence,
      :contact_action_claimer,
      Cadence.Adapters.Contacts.ActionClaimer
    )
  end
end
