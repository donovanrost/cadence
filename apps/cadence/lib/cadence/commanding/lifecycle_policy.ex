defmodule Cadence.Commanding.LifecyclePolicy do
  @moduledoc """
  Applies command-stage, request-release and queue-entry lifecycle guards.
  """

  @spec ensure_stage_editable(map()) :: :ok | {:error, term()}
  def ensure_stage_editable(%{
        lifecycle_state: lifecycle_state,
        command_stage_id: command_stage_id
      }) do
    ensure_stage_editable(lifecycle_state, command_stage_id)
  end

  @spec ensure_staged_item_editable(map()) :: :ok | {:error, term()}
  def ensure_staged_item_editable(%{lifecycle_state: "draft"}), do: :ok

  def ensure_staged_item_editable(%{
        staged_command_item_id: staged_command_item_id,
        lifecycle_state: lifecycle_state
      }) do
    {:error, {:staged_command_item_not_editable, staged_command_item_id, lifecycle_state}}
  end

  @spec ensure_request_releasable(map()) :: :ok | {:error, term()}
  def ensure_request_releasable(%{lifecycle_state: "queued"}), do: :ok

  def ensure_request_releasable(%{
        command_request_id: command_request_id,
        lifecycle_state: lifecycle_state
      }) do
    {:error, {:command_request_not_releasable, command_request_id, lifecycle_state}}
  end

  @spec ensure_request_not_expired(map()) :: :ok | {:error, term()}
  def ensure_request_not_expired(%{expires_at: nil}), do: :ok

  def ensure_request_not_expired(%{
        command_request_id: command_request_id,
        expires_at: %DateTime{} = expires_at
      }) do
    if DateTime.compare(expires_at, DateTime.utc_now()) == :lt do
      {:error, {:command_request_expired, command_request_id}}
    else
      :ok
    end
  end

  @spec ensure_queue_entry_releaseable(map(), DateTime.t()) :: :ok | {:error, term()}
  def ensure_queue_entry_releaseable(
        %{lifecycle_state: "pending"} = queue_entry,
        %DateTime{} = attempted_at
      ) do
    with :ok <- ensure_queue_entry_not_before_elapsed(queue_entry, attempted_at) do
      ensure_queue_entry_not_expired(queue_entry, attempted_at)
    end
  end

  def ensure_queue_entry_releaseable(
        %{
          command_queue_entry_id: command_queue_entry_id,
          lifecycle_state: lifecycle_state
        },
        %DateTime{}
      ) do
    {:error, {:command_queue_entry_not_releasable, command_queue_entry_id, lifecycle_state}}
  end

  defp ensure_stage_editable(lifecycle_state, _command_stage_id)
       when lifecycle_state in [:draft, :in_review, :ready_to_submit] do
    :ok
  end

  defp ensure_stage_editable(lifecycle_state, _command_stage_id)
       when lifecycle_state in ["draft", "in_review", "ready_to_submit"], do: :ok

  defp ensure_stage_editable(lifecycle_state, command_stage_id) do
    {:error, {:command_stage_not_editable, command_stage_id, lifecycle_state}}
  end

  defp ensure_queue_entry_not_before_elapsed(%{not_before: nil}, _attempted_at),
    do: :ok

  defp ensure_queue_entry_not_before_elapsed(
         %{
           command_queue_entry_id: command_queue_entry_id,
           not_before: %DateTime{} = not_before
         },
         %DateTime{} = attempted_at
       ) do
    if DateTime.compare(not_before, attempted_at) in [:lt, :eq] do
      :ok
    else
      {:error, {:command_queue_entry_not_ready, command_queue_entry_id, not_before}}
    end
  end

  defp ensure_queue_entry_not_expired(%{expires_at: nil}, _attempted_at), do: :ok

  defp ensure_queue_entry_not_expired(
         %{
           command_queue_entry_id: command_queue_entry_id,
           expires_at: %DateTime{} = expires_at
         },
         %DateTime{} = attempted_at
       ) do
    if DateTime.compare(expires_at, attempted_at) == :lt do
      {:error, {:command_queue_entry_expired, command_queue_entry_id}}
    else
      :ok
    end
  end
end
