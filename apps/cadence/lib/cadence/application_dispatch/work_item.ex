defmodule Cadence.ApplicationDispatch.WorkItem do
  @moduledoc """
  Concrete unit of handler work emitted by the application dispatcher.
  """

  @type t :: %__MODULE__{
          binding_rule_id: binary(),
          capability_instance_id: binary() | nil,
          handler_key: atom(),
          handler_configuration: term()
        }

  defstruct [:binding_rule_id, :capability_instance_id, :handler_key, :handler_configuration]
end
