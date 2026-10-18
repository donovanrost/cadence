defmodule Cadence.Management.Commanding.RequestAuthoring do
  @moduledoc "Human command discovery, exact server previews and finite durable request creation."
  alias Cadence.Commanding.{CommandRequest, RequestValidation}
  alias Cadence.Management.Commanding
  alias Cadence.Management.Commanding.ArgumentDocument
  alias Cadence.Management.Commanding.{AuthoringCatalog, AuthoringInput, ReviewAccess}

  defdelegate authorize(scope, mission_id), to: ReviewAccess

  def load(scope, mission_id, params) do
    with {:ok, fresh, mission} <- ReviewAccess.authorize(scope, mission_id),
         {:ok, query} <- AuthoringCatalog.query(params) do
      RequestValidation.with_authoring_catalog(
        fresh.organization_id,
        mission_id,
        &AuthoringCatalog.page(fresh, mission, &1, query)
      )
    end
  end

  def preview(scope, mission_id, input) do
    with {:ok, fresh, _} <- ReviewAccess.authorize(scope, mission_id),
         {:ok, input} <- AuthoringInput.preview(input),
         :ok <- expires_in_future(input.expires_at) do
      request =
        CommandRequest.new(%{
          organization_id: fresh.organization_id,
          mission_id: mission_id,
          source_endpoint_ref: input.source_endpoint_ref,
          command_id: input.command_id,
          mission_model_revision_id: nil,
          argument_values: input.argument_values,
          priority: input.priority,
          not_before: input.not_before,
          expires_at: input.expires_at,
          requested_at: DateTime.utc_now(),
          requested_by: %{"actor_kind" => "user", "user_id" => fresh.user.user_id}
        })

      RequestValidation.with_authoring_request(
        request,
        input.expected_basis,
        nil,
        &hold_preview(&1, &2, input.expected_basis)
      )
    end
  end

  # held is exclusively server state returned by preview/3, never a decoded browser payload.
  def create(
        scope,
        mission_id,
        %{token: _, request: %CommandRequest{}, expected_basis: _, expected_target: _} = held,
        input
      ) do
    with {:ok, fresh, _} <- ReviewAccess.authorize(scope, mission_id),
         {:ok, expected} <- AuthoringInput.create(input),
         true <-
           expected == held.token and
             held.token == RequestValidation.authoring_digest(Map.delete(held, :token)),
         %CommandRequest{} = request <- held.request,
         true <-
           request.organization_id == fresh.organization_id and request.mission_id == mission_id and
             request.requested_by == %{"actor_kind" => "user", "user_id" => fresh.user.user_id},
         :ok <- expires_in_future(request.expires_at),
         {:ok, persisted} <-
           Commanding.persist_reviewed_request(
             fresh.organization_id,
             request,
             held.expected_basis,
             held.expected_target,
             fn -> authorize_insert(scope, mission_id) end
           ) do
      {:ok, receipt(persisted)}
    else
      false -> {:error, :command_authoring_preview_changed}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_command_preview}
    end
  end

  def create(_, _, _, _), do: {:error, :invalid_command_preview}

  def recover(scope, mission_id, held) when is_map(held) do
    with {:ok, fresh, _} <- ReviewAccess.authorize(scope, mission_id),
         %CommandRequest{} = expected <- held.request,
         {:ok, persisted} <-
           Commanding.fetch_command_request(
             fresh.organization_id,
             mission_id,
             expected.command_request_id
           ),
         true <-
           persisted.requested_by == expected.requested_by and
             persisted.requested_by["user_id"] == fresh.user.user_id and
             same_intent?(persisted, expected) do
      {:ok, receipt(persisted)}
    else
      _ -> {:error, :unconfirmed}
    end
  end

  def recover(_, _, _), do: {:error, :unconfirmed}

  def public_preview(held) do
    request = held.request

    %{
      "token" => held.token,
      "request_id" => request.command_request_id,
      "target" => held.target,
      "revision_id" => request.mission_model_revision_id,
      "command_id" => request.command_id,
      "command_name" => request.command_name,
      "command_display_name" => request.command_display_name,
      "actor_id" => request.requested_by["user_id"],
      "priority" => request.priority,
      "not_before" => time(request.not_before),
      "expires_at" => time(request.expires_at),
      "requested_at" => time(request.requested_at),
      "lifecycle_state" => to_string(request.lifecycle_state),
      "argument_values_json" => ArgumentDocument.encode!(request.argument_values),
      "resolved_argument_values_json" =>
        ArgumentDocument.encode!(request.resolved_argument_values, 131_072),
      "critical" => request.critical,
      "hazardous" => request.hazardous,
      "significance" => if(request.significance, do: to_string(request.significance), else: nil)
    }
  end

  defp hold_preview(request, state, expected_basis) do
    held = %{
      request: request,
      expected_basis: expected_basis,
      expected_target: state.target_token,
      target: AuthoringCatalog.target(state.target)
    }

    held = Map.put(held, :token, RequestValidation.authoring_digest(held))

    with :ok <- expires_in_future(request.expires_at),
         {:ok, json} <- Jason.encode(public_preview(held)),
         true <- byte_size(json) <= 131_072 do
      {:ok, held}
    else
      _ -> {:error, :command_preview_unavailable}
    end
  rescue
    ArgumentError -> {:error, :command_preview_unavailable}
  end

  defp authorize_insert(scope, mission_id) do
    case ReviewAccess.authorize(scope, mission_id) do
      {:ok, _, _} -> :ok
      _ -> {:error, :unavailable}
    end
  end

  defp same_intent?(persisted, expected) do
    keys = [
      :command_request_id,
      :organization_id,
      :mission_id,
      :source_endpoint_ref,
      :mission_model_revision_id,
      :command_id,
      :argument_values,
      :resolved_argument_values,
      :priority,
      :not_before,
      :expires_at,
      :requested_at,
      :critical,
      :hazardous,
      :metadata
    ]

    Map.take(persisted, keys) == Map.take(expected, keys)
  end

  defp receipt(request),
    do: %{
      "request_id" => request.command_request_id,
      "actor_id" => request.requested_by["user_id"],
      "requested_at" => time(request.requested_at),
      "lifecycle_state" => to_string(request.lifecycle_state)
    }

  defp expires_in_future(nil), do: :ok

  defp expires_in_future(value) do
    if DateTime.compare(value, DateTime.utc_now()) == :gt,
      do: :ok,
      else: {:error, :command_request_expired}
  end

  defp time(nil), do: nil
  defp time(value), do: DateTime.to_iso8601(value)
end
