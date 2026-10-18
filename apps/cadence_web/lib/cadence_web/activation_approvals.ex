defmodule CadenceWeb.ActivationApprovals do
  @moduledoc "Host-owned activation inbox and page-instance-bound decision transport."
  alias Cadence.Control.Activations
  alias Cadence.Reads.ActivationApprovals, as: Inbox
  @route "/missions/:mission_id/ops/activations"

  def load(scope, %{route: @route, params: params}) do
    context = %{organization_id: scope.organization_id, mission_id: params["mission_id"]}

    case Inbox.load(scope, params["mission_id"]) do
      {:ok, data} -> %{version: 1, status: "ready", context: context, data: data}
      {:error, _} -> %{version: 1, status: "unavailable", context: context}
    end
  rescue
    _ -> %{version: 1, status: "unavailable"}
  end

  def load(_scope, _info), do: nil

  def session(previous, scope, %{route: @route, params: params}, path) do
    case previous do
      %{path: ^path, organization_id: org} when org == scope.organization_id ->
        previous

      _ ->
        %{
          path: path,
          organization_id: scope.organization_id,
          mission_id: params["mission_id"],
          token: Ecto.UUID.generate()
        }
    end
  end

  def session(_previous, _scope, _info, _path), do: nil

  def matches?(socket, token) when is_binary(token) do
    case socket.assigns[:activation_review_session] do
      %{token: ^token, path: path, organization_id: org} ->
        path == socket.assigns.host_path and org == socket.assigns.current_scope.organization_id

      _ ->
        false
    end
  end

  def matches?(_socket, _token), do: false

  def presentation(assigns) do
    case {assigns[:activation_approvals], assigns[:activation_review_session]} do
      {page, %{token: token}} when is_map(page) -> Map.put(page, :token, token)
      {page, _} -> page
    end
  end

  def decide(scope, session, input) do
    case Activations.review(scope, session.mission_id, input) do
      {:ok, data} ->
        %{status: "ok", data: data}

      {:error, :activation_self_approval_forbidden} ->
        %{status: "invalid", message: "A different person must review this request."}

      {:error, :invalid_activation_decision} ->
        %{status: "invalid", message: "Provide a decision rationale of at most 4096 bytes."}

      {:error, :activation_policy_changed} ->
        %{
          status: "invalid",
          message:
            "Approval settings changed. Review the current requirements and submit the configuration again."
        }

      {:error, :activation_request_not_pending_approval} ->
        %{status: "invalid", message: "This request has already been decided. Refresh the inbox."}

      {:error, _} ->
        %{status: "unavailable"}
    end
  rescue
    _ -> %{status: "unavailable"}
  end
end
