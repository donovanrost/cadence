defmodule Cadence.Commanding.LifecyclePolicy do
  @moduledoc """
  Applies command-stage, approval, request, and queue-entry lifecycle guards.
  """

  alias Cadence.Governance.Accountability
  alias Cadence.Persistence.JsonDocument

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

  @doc """
  A command-group member is decided and queued only through its group (the group's GO/NO-GO and
  release), never alone: a standalone decision or enqueue would skip the group's named approver,
  its basis check and its hold acknowledgements (four-eyes audit 11-17, P0).
  """
  @spec ensure_request_not_in_group(map()) :: :ok | {:error, :command_request_in_group}
  def ensure_request_not_in_group(%{command_group_id: nil}), do: :ok

  def ensure_request_not_in_group(%{command_group_id: _group_id}),
    do: {:error, :command_request_in_group}

  @spec ensure_request_pending_approval(map()) :: :ok | {:error, term()}
  def ensure_request_pending_approval(%{lifecycle_state: "approval_pending"}), do: :ok

  def ensure_request_pending_approval(%{
        command_request_id: command_request_id,
        lifecycle_state: lifecycle_state
      }) do
    {:error, {:command_request_not_pending_approval, command_request_id, lifecycle_state}}
  end

  @spec ensure_human_approval_actor(map(), binary()) :: :ok | {:error, term()}
  def ensure_human_approval_actor(decided_by, command_request_id) when is_map(decided_by) do
    case Map.get(decided_by, "user_id") || Map.get(decided_by, :user_id) do
      user_id when is_binary(user_id) and user_id != "" ->
        :ok

      _other ->
        {:error, {:command_request_approval_requires_user_actor, command_request_id}}
    end
  end

  @doc """
  The authors the separation check is given: the requester, as stored. #117 step 4b records exactly
  these as `separated_from` (domain: the same function `Accountability.separate` is given).
  """
  @spec separation_authors(map()) :: [map()]
  def separation_authors(%{requested_by_document: document}),
    do: [JsonDocument.unwrap_value(document)]

  @doc "`separation_authors/1` as ids (a service by its own id), sorted and unique."
  @spec separated_from(map()) :: [binary()]
  def separated_from(request_row),
    do: request_row |> separation_authors() |> Accountability.ids()

  @spec ensure_not_self_approval(map(), map()) :: :ok | {:error, term()}
  # #280: the requester counts as people. A service requester is its issuer and rotators (it has no
  # user_id, so the old comparison passed it); an unknown set refuses (`:command_request_approver_authors_unknown`).
  def ensure_not_self_approval(
        %{
          organization_id: organization_id,
          command_request_id: command_request_id,
          requested_by_document: requested_by_document
        },
        decided_by
      )
      when is_map(decided_by) do
    approver_user_id = Map.get(decided_by, "user_id") || Map.get(decided_by, :user_id)

    case Accountability.separate(
           organization_id,
           {:user, approver_user_id},
           separation_authors(%{requested_by_document: requested_by_document})
         ) do
      :ok ->
        :ok

      {:error, {:self, nil}} ->
        {:error, {:command_request_self_approval_not_allowed, command_request_id}}

      {:error, {:self, via}} ->
        {:error,
         {:command_request_self_approval_not_allowed, command_request_id, %{via_service: via}}}

      {:error, {:unknown, service}} ->
        {:error,
         {:command_request_approver_authors_unknown, command_request_id, %{service: service}}}
    end
  end

  @spec ensure_request_queueable(map()) :: :ok | {:error, term()}
  def ensure_request_queueable(%{lifecycle_state: lifecycle_state})
      when lifecycle_state in ["validated", "approved"],
      do: :ok

  def ensure_request_queueable(%{
        lifecycle_state: "approval_pending",
        command_request_id: command_request_id
      }) do
    {:error, {:command_request_requires_approval, command_request_id}}
  end

  def ensure_request_queueable(%{
        command_request_id: command_request_id,
        lifecycle_state: lifecycle_state
      }) do
    {:error, {:command_request_not_queueable, command_request_id, lifecycle_state}}
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
