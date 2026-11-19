defmodule Cadence.Control.ActivationRequests do
  @moduledoc """
  The console's activation approvals (§11 L10, docs/apogee/api/activations.md): a mission's
  requests by tab, one request with what it activates, and approve, reject and resume (`Retry
  apply`). Every call compares the request's mission with the route's (Management's `fetch/2`
  checks only the organization). Decisions announce `:activations_changed`.

  todo(authz): reads are open to the mission's console members; deciding and resuming use
  `:approve_activation` (today `:operate_mission`), which Cedar should settle.
  """

  alias Cadence.Auth.Scope
  alias Cadence.Control.ActivationRequests.{ConfigurationChanges, Refusals, Rows}
  alias Cadence.Control.Activations, as: ControlActivations
  alias Cadence.Management.Activations, as: ManagementActivations
  alias Cadence.Management.Activations.Directory
  alias Cadence.Platform.ScopedReadUpdates

  require Logger

  @tabs %{"pending" => :pending, "decided" => :decided}
  @reason_bytes 1..4096

  @spec list(Scope.t(), binary(), map()) :: {:ok, map()} | {:error, term()}
  def list(%Scope{} = scope, mission_id, params) do
    with {:ok, tab} <- tab(params["state"]),
         {:ok, before} <- Rows.decode_cursor(params["before"]) do
      {requests, more?} = Directory.page(scope.organization_id, mission_id, tab, before)

      {:ok,
       %{
         requests: Rows.rows(scope, mission_id, requests),
         next: if(more?, do: Rows.cursor(List.last(requests))),
         permissions: Rows.permissions(scope, mission_id)
       }}
    end
  end

  @spec get(Scope.t(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def get(%Scope{} = scope, mission_id, request_id) do
    with {:ok, request} <- Directory.fetch(scope.organization_id, mission_id, request_id) do
      {:ok, Rows.detail(scope, mission_id, request)}
    end
  end

  @doc """
  One page of a #235 group's spacecraft names (`group`: the index in `configuration_changes`
  as the detail sent it; `offset`: from its `next_offset`).
  """
  @spec configuration_change_names(Scope.t(), binary(), binary(), map()) ::
          {:ok, map()} | {:error, term()}
  def configuration_change_names(%Scope{} = scope, mission_id, request_id, params) do
    with {:ok, group, offset} <- names_params(params),
         {:ok, request} <- Directory.fetch(scope.organization_id, mission_id, request_id),
         {:ok, mission} <- Cadence.Missions.fetch_mission(scope.organization_id, mission_id) do
      ConfigurationChanges.names(mission, request, group, offset)
    end
  end

  defp names_params(params) do
    with {group, ""} <- Integer.parse(to_string(params["group"] || "")),
         {offset, ""} <- Integer.parse(to_string(params["offset"] || "0")),
         true <- group >= 0 and offset >= 0 do
      {:ok, group, offset}
    else
      _ ->
        {:error,
         {:invalid_params,
          %{group: "a group index from configuration_changes", offset: "0 or more"}}}
    end
  end

  @doc "Approves and applies: `{:ok, %{request, outcome: applied | needs_review}}`."
  @spec approve(Scope.t(), binary(), binary(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def approve(%Scope{} = scope, mission_id, request_id, params, opts \\ []) do
    # `:execute` is a test seam for an apply that exits (default `ControlActivations.execute/1`).
    {run, opts} = Keyword.pop(opts, :execute, &ControlActivations.execute/1)

    with {:ok, reason} <- reason(params["reason"]),
         {:ok, request} <- pending(scope, mission_id, request_id),
         {:ok, _request, _decision, approved} <-
           scope
           |> ControlActivations.approve(request_id, reason, opts)
           |> Refusals.explain(scope.organization_id, mission_id, request)
           |> decision_result() do
      outcome = run |> execute(approved) |> outcome()
      announce(scope, mission_id)
      reply(scope, mission_id, request_id, outcome)
    end
  end

  @spec reject(Scope.t(), binary(), binary(), map()) :: {:ok, map()} | {:error, term()}
  def reject(%Scope{} = scope, mission_id, request_id, params) do
    with {:ok, reason} <- reason(params["reason"]),
         {:ok, _request} <- pending(scope, mission_id, request_id),
         {:ok, _request, _decision} <-
           decision_result(ManagementActivations.reject(scope, request_id, reason)) do
      announce(scope, mission_id)
      reply(scope, mission_id, request_id, nil)
    end
  end

  @doc "The requester withdraws a pending request: `{:ok, %{request}}`."
  @spec withdraw(Scope.t(), binary(), binary(), map()) :: {:ok, map()} | {:error, term()}
  def withdraw(%Scope{} = scope, mission_id, request_id, params) do
    with {:ok, reason} <- reason(params["reason"]),
         {:ok, _request} <- pending(scope, mission_id, request_id),
         {:ok, _request, _decision} <-
           decision_result(ManagementActivations.withdraw(scope, request_id, reason)) do
      reply(scope, mission_id, request_id, nil)
    end
  end

  @doc "Retry apply (domain's resume): `{:ok, %{request, outcome}}` or a refusal."
  @spec resume(Scope.t(), binary(), binary()) :: {:ok, map()} | {:error, term()}
  def resume(%Scope{} = scope, mission_id, request_id) do
    case ControlActivations.resume(scope, mission_id, request_id) do
      {:error, reason} when is_tuple(reason) or is_atom(reason) ->
        if refusal?(reason),
          do: {:error, reason},
          else: resumed(scope, mission_id, request_id, {:error, reason})

      result ->
        resumed(scope, mission_id, request_id, result)
    end
  end

  defp resumed(scope, mission_id, request_id, result) do
    announce(scope, mission_id)
    reply(scope, mission_id, request_id, outcome(result))
  end

  defp refusal?({:nothing_to_resume, _state}), do: true
  defp refusal?({:not_resumable, _code}), do: true

  defp refusal?(reason),
    do: reason in [:activation_execution_in_progress, :activation_request_not_found, :forbidden]

  # An apply that raised, exited (a pool or GenServer timeout) or threw still leaves the request
  # approved: it reads as needs_review, never a 500 for a recorded approval (#263, ca-security).
  defp execute(run, approved) do
    run.(approved)
  rescue
    _error -> {:error, :activation_execution_raised}
  catch
    :exit, reason -> exited(approved, "exit: " <> inspect(reason))
    :throw, value -> exited(approved, "throw: " <> inspect(value))
  end

  defp exited(approved, cause) do
    Logger.error(
      "activation request #{approved.activation_request_id}: approved, but its apply didn't " <>
        "finish: " <> (cause |> String.split("\n", parts: 2) |> hd())
    )

    {:error, :activation_execution_raised}
  end

  defp outcome({:ok, %{status: :succeeded}}), do: "applied"
  defp outcome(_result), do: "needs_review"

  defp reply(scope, mission_id, request_id, outcome) do
    {:ok, request} = get(scope, mission_id, request_id)
    {:ok, if(outcome, do: %{request: request, outcome: outcome}, else: %{request: request})}
  end

  defp pending(scope, mission_id, request_id) do
    case Directory.fetch(scope.organization_id, mission_id, request_id) do
      {:ok, %{state: :approval_pending} = request} -> {:ok, request}
      {:ok, request} -> {:error, {:not_pending, Atom.to_string(request.state)}}
      error -> error
    end
  end

  defp decision_result({:error, :activation_self_approval_forbidden}),
    do: {:error, :self_approval_forbidden}

  # #280 (U100): through a service identity the approver is accountable for.
  defp decision_result({:error, {:activation_self_approval_forbidden, details}}),
    do: {:error, {:self_approval_forbidden, details}}

  defp decision_result({:error, :activation_request_not_pending_approval}),
    do: {:error, {:not_pending, nil}}

  defp decision_result({:error, :invalid_reason}),
    do: {:error, {:invalid_params, %{reason: "Say why."}}}

  defp decision_result({:error, reason})
       when reason in [:invalid_activation_scope, :human_activation_approver_required],
       do: {:error, :forbidden}

  defp decision_result(result), do: result

  defp announce(scope, mission_id),
    do: ScopedReadUpdates.publish(:activations_changed, scope.organization_id, mission_id)

  defp tab(nil), do: {:ok, :pending}

  defp tab(value) do
    case Map.fetch(@tabs, value) do
      {:ok, tab} -> {:ok, tab}
      :error -> {:error, {:invalid_params, %{state: "must be pending or decided"}}}
    end
  end

  defp reason(value) when is_binary(value) do
    trimmed = String.trim(value)

    if byte_size(trimmed) in @reason_bytes,
      do: {:ok, trimmed},
      else: {:error, {:invalid_params, %{reason: "Say why."}}}
  end

  defp reason(_value), do: {:error, {:invalid_params, %{reason: "Say why."}}}
end
