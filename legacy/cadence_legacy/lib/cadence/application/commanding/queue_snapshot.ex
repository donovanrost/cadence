defmodule Cadence.Application.Commanding.QueueSnapshot do
  @moduledoc """
  Snapshot of a target's command queue for data plane startup.

  Control plane builds these snapshots from persisted queue entries
  and injects them into MissionConfig for runtime use.
  """

  alias Cadence.Domain.Commanding.Entities.QueuedCommand

  @type t :: %__MODULE__{
          target_id: String.t(),
          pending_entries: [QueuedCommand.t()],
          sequence_counter: non_neg_integer()
        }

  defstruct target_id: nil, pending_entries: [], sequence_counter: 0
end
