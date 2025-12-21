defprotocol Cadence.Recordings.Recordable do
  @moduledoc """
  Protocol for recordable event types.

  Each recordable (event) type implements this protocol to provide uniform
  access to display fields for timeline rendering and filtering.

  ## Example Implementation

      defimpl Cadence.Recordings.Recordable, for: Cadence.Recordings.Recordables.CommandDispatched do
        def recording_type(_), do: "CommandDispatched"
        def aggregate_type(_), do: "Command"
        def title(r), do: r.command_name
        def status(_), do: "pending"
        def severity(_), do: nil
      end
  """

  @doc """
  Returns the recording type name for this recordable.
  This must match the recordable_type stored in the recordings table.
  """
  @spec recording_type(t) :: String.t()
  def recording_type(recordable)

  @doc """
  Returns the aggregate type this recordable belongs to.
  Examples: "Command", "Alarm", "Procedure", "Automation", "QueueEntry"
  """
  @spec aggregate_type(t) :: String.t()
  def aggregate_type(recordable)

  @doc """
  Returns a human-readable title for timeline display.
  """
  @spec title(t) :: String.t()
  def title(recordable)

  @doc """
  Returns a status string for filtering.
  """
  @spec status(t) :: String.t() | nil
  def status(recordable)

  @doc """
  Returns severity if applicable (for alarms).
  """
  @spec severity(t) :: String.t() | nil
  def severity(recordable)
end
