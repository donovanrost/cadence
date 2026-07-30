defmodule CadenceWeb.FallbackController do
  use CadenceWeb, :controller

  alias Ecto.Changeset

  def call(conn, {:error, :source_endpoint_not_found}) do
    error_response(conn, :not_found, "source_endpoint_not_found")
  end

  def call(conn, {:error, :spacecraft_not_found}) do
    error_response(conn, :not_found, "spacecraft_not_found")
  end

  def call(conn, {:error, :organization_not_found}) do
    error_response(conn, :not_found, "organization_not_found")
  end

  def call(conn, {:error, :mission_not_found}) do
    error_response(conn, :not_found, "mission_not_found")
  end

  def call(conn, {:error, :command_stage_not_found}) do
    error_response(conn, :not_found, "command_stage_not_found")
  end

  def call(conn, {:error, :staged_command_item_not_found}) do
    error_response(conn, :not_found, "staged_command_item_not_found")
  end

  def call(conn, {:error, :command_request_not_found}) do
    error_response(conn, :not_found, "command_request_not_found")
  end

  def call(conn, {:error, :command_approval_not_found}) do
    error_response(conn, :not_found, "command_approval_not_found")
  end

  def call(conn, {:error, :command_queue_entry_not_found}) do
    error_response(conn, :not_found, "command_queue_entry_not_found")
  end

  def call(conn, {:error, :command_release_attempt_not_found}) do
    error_response(conn, :not_found, "command_release_attempt_not_found")
  end

  def call(conn, {:error, :command_verifier_instance_not_found}) do
    error_response(conn, :not_found, "command_verifier_instance_not_found")
  end

  def call(conn, {:error, :service_identity_not_found}) do
    error_response(conn, :not_found, "service_identity_not_found")
  end

  def call(conn, {:error, :binding_set_not_found}) do
    error_response(conn, :not_found, "binding_set_not_found")
  end

  def call(conn, {:error, :activation_request_not_found}) do
    error_response(conn, :not_found, "activation_request_not_found")
  end

  def call(conn, {:error, :catalog_importer_not_found}) do
    error_response(conn, :not_found, "catalog_importer_not_found")
  end

  def call(conn, {:error, :catalog_artifact_not_found}) do
    error_response(conn, :not_found, "catalog_artifact_not_found")
  end

  def call(conn, {:error, :catalog_import_run_not_found}) do
    error_response(conn, :not_found, "catalog_import_run_not_found")
  end

  def call(conn, {:error, :catalog_telemetry_snapshot_not_found}) do
    error_response(conn, :not_found, "catalog_telemetry_snapshot_not_found")
  end

  def call(conn, {:error, :contact_provider_profile_not_found}) do
    error_response(conn, :not_found, "contact_provider_profile_not_found")
  end

  def call(conn, {:error, :contact_transport_profile_not_found}) do
    error_response(conn, :not_found, "contact_transport_profile_not_found")
  end

  def call(conn, {:error, :contact_path_template_not_found}) do
    error_response(conn, :not_found, "contact_path_template_not_found")
  end

  def call(conn, {:error, :contact_link_assignment_not_found}) do
    error_response(conn, :not_found, "contact_link_assignment_not_found")
  end

  def call(conn, {:error, :scheduled_contact_not_found}) do
    error_response(conn, :not_found, "scheduled_contact_not_found")
  end

  def call(conn, {:error, :realized_contact_not_found}) do
    error_response(conn, :not_found, "realized_contact_not_found")
  end

  def call(conn, {:error, :scheduled_contact_requires_selected_path}) do
    error_response(conn, :unprocessable_entity, "scheduled_contact_requires_selected_path")
  end

  def call(conn, {:error, :scheduled_contact_requires_selected_downlink_path}) do
    error_response(
      conn,
      :unprocessable_entity,
      "scheduled_contact_requires_selected_downlink_path"
    )
  end

  def call(conn, {:error, :scheduled_contact_requires_selected_uplink_path}) do
    error_response(conn, :unprocessable_entity, "scheduled_contact_requires_selected_uplink_path")
  end

  def call(conn, {:error, :realized_contact_requires_selected_path}) do
    error_response(conn, :unprocessable_entity, "realized_contact_requires_selected_path")
  end

  def call(conn, {:error, :realized_contact_requires_selected_downlink_path}) do
    error_response(
      conn,
      :unprocessable_entity,
      "realized_contact_requires_selected_downlink_path"
    )
  end

  def call(conn, {:error, :realized_contact_requires_selected_uplink_path}) do
    error_response(conn, :unprocessable_entity, "realized_contact_requires_selected_uplink_path")
  end

  def call(conn, {:error, :no_active_binding_set}) do
    error_response(conn, :not_found, "no_active_binding_set")
  end

  def call(conn, {:error, :invalid_credentials}) do
    error_response(conn, :unauthorized, "invalid_credentials")
  end

  def call(conn, {:error, :unauthenticated}) do
    error_response(conn, :unauthorized, "unauthenticated")
  end

  def call(conn, {:error, :forbidden}) do
    error_response(conn, :forbidden, "forbidden")
  end

  def call(conn, {:error, :scope_mismatch}) do
    error_response(conn, :forbidden, "scope_mismatch")
  end

  def call(conn, {:error, {:packet_definition_not_found, _ref}}) do
    error_response(conn, :not_found, "packet_definition_not_found")
  end

  def call(conn, {:error, {:invalid_param, field, reason}}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: [%{field: to_string(field), reason: format_reason(reason)}]})
  end

  def call(conn, {:error, %Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: translate_errors(changeset)})
  end

  def call(conn, {:error, reason}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{errors: [%{reason: format_reason(reason)}]})
  end

  defp error_response(conn, status, code) do
    conn
    |> put_status(status)
    |> json(%{errors: [%{reason: code}]})
  end

  defp translate_errors(%Changeset{} = changeset) do
    Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.flat_map(fn {field, messages} ->
      Enum.map(messages, fn message ->
        %{field: to_string(field), reason: message}
      end)
    end)
  end

  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
