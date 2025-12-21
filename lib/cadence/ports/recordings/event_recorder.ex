defmodule Cadence.Ports.Recordings.EventRecorder do
  @moduledoc """
  Port (behavior) defining the contract for recording domain events.

  This behavior abstracts the event recording system from the domain,
  enabling:
  - Unit testing with in-memory implementations
  - Swapping recording backends without changing domain logic
  - Clear separation between domain events and recording infrastructure

  ## Implementations

  - `Cadence.Adapters.Recordings.RecordingsEventRecorder` - Production implementation
  - `Cadence.Test.Adapters.InMemoryEventRecorder` - In-memory for tests

  ## Usage in Use Cases

      def acknowledge_alarm(alarm_id, user_id, note) do
        with {:ok, alarm} <- AlarmQueries.find(alarm_id),
             {:ok, updated} <- Alarm.acknowledge(alarm, user_id, note),
             {:ok, saved} <- repo().save(updated) do
          recorder().record(:alarm_acknowledged, saved, user_id, %{note: note})
          {:ok, saved}
        end
      end
  """

  @type event_type ::
          # Alarm events
          :alarm_triggered
          | :alarm_acknowledged
          | :alarm_cleared
          | :alarm_shelved
          | :alarm_unshelved
          | :alarm_escalated
          # Command queue events
          | :command_queued
          | :command_dequeued
          | :command_claimed
          | :command_completed
          | :command_failed
          | :command_cancelled
          | :command_expired
          # Procedure version events
          | :procedure_version_created
          | :procedure_version_submitted
          | :procedure_version_approved
          | :procedure_version_rejected
          | :procedure_version_withdrawn
          | :procedure_version_deprecated
          | :procedure_approval_added

  @type aggregate :: struct()
  @type actor_id :: String.t() | nil
  @type attrs :: map()
  @type recording_context :: %{
          required(:organization_id) => String.t(),
          optional(:mission_id) => String.t() | nil,
          optional(:bucket_id) => String.t() | nil,
          optional(:target_id) => String.t() | nil,
          optional(:parent_id) => String.t() | nil,
          optional(:root_id) => String.t() | nil
        }
  @type error :: term()

  @doc """
  Records a domain event.

  Takes the event type, the aggregate (domain entity), the actor who
  triggered the event, and any additional event-specific attributes.

  The recording context (organization_id, mission_id, etc.) is extracted
  from the aggregate when possible, but can be provided explicitly.

  ## Parameters

  - `event_type` - The type of domain event (see @type event_type)
  - `aggregate` - The domain entity involved in the event
  - `actor_id` - UUID of the user/system that triggered the event
  - `attrs` - Additional event-specific attributes

  ## Returns

  - `:ok` - Successfully recorded
  - `{:error, reason}` - Recording failed

  ## Examples

      # Record an alarm acknowledgement
      recorder().record(:alarm_acknowledged, alarm, user_id, %{note: "Investigating"})

      # Record a command being queued
      recorder().record(:command_queued, queued_command, user_id, %{})

      # Record procedure version approval
      recorder().record(:procedure_version_approved, version, approver_id, %{comment: "LGTM"})
  """
  @callback record(event_type(), aggregate(), actor_id(), attrs()) ::
              :ok | {:error, error()}

  @doc """
  Records a domain event with explicit recording context.

  Use this when the aggregate doesn't contain all necessary context,
  or when you need to link recordings in a causality chain.

  ## Parameters

  - `event_type` - The type of domain event
  - `aggregate` - The domain entity involved
  - `actor_id` - UUID of the actor
  - `attrs` - Event-specific attributes
  - `context` - Recording context (organization_id, parent_id, etc.)

  ## Examples

      # Record with causality chain
      recorder().record_with_context(
        :command_completed,
        queued_command,
        nil,
        %{result: "success"},
        %{
          organization_id: org_id,
          parent_id: dispatch_recording_id,
          root_id: original_recording_id
        }
      )
  """
  @callback record_with_context(
              event_type(),
              aggregate(),
              actor_id(),
              attrs(),
              recording_context()
            ) :: :ok | {:error, error()}

  @doc """
  Returns the configured event recorder implementation.
  """
  @spec impl() :: module()
  def impl do
    Application.get_env(
      :cadence,
      :event_recorder,
      Cadence.Adapters.Recordings.RecordingsEventRecorder
    )
  end
end
