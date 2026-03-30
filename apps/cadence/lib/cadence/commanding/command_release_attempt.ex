defmodule Cadence.Commanding.CommandReleaseAttempt do
  @moduledoc """
  Durable operational command release attempt bound to one queued request and a
  concrete realized contact/path/transport target.
  """

  alias Cadence.Ids

  @type lifecycle_state :: :release_pending | :released | :release_failed | :canceled
  @type verification_state :: :not_required | :pending | :satisfied | :failed | :timed_out | nil

  @type t :: %__MODULE__{
          command_release_attempt_id: binary(),
          organization_id: binary() | nil,
          mission_id: binary(),
          command_queue_entry_id: binary(),
          command_request_id: binary(),
          source_endpoint_ref: binary(),
          realized_contact_id: binary(),
          path_id: binary() | nil,
          transport_binding_id: binary() | nil,
          command_snapshot_id: binary(),
          command_id: binary(),
          command_name: binary() | nil,
          layout_kind: atom() | nil,
          preferred_uplink_service: binary() | nil,
          apid: non_neg_integer() | nil,
          service_type: non_neg_integer() | nil,
          service_subtype: non_neg_integer() | nil,
          opcode: term() | nil,
          encoded_binary_base64: binary() | nil,
          encoded_size_bytes: non_neg_integer() | nil,
          lifecycle_state: lifecycle_state(),
          verification_state: verification_state(),
          failure_reason: binary() | nil,
          released_by: map(),
          attempted_at: DateTime.t() | nil,
          released_at: DateTime.t() | nil,
          metadata: map()
        }

  defstruct [
    :command_release_attempt_id,
    :organization_id,
    :mission_id,
    :command_queue_entry_id,
    :command_request_id,
    :source_endpoint_ref,
    :realized_contact_id,
    :path_id,
    :transport_binding_id,
    :command_snapshot_id,
    :command_id,
    :command_name,
    :layout_kind,
    :preferred_uplink_service,
    :apid,
    :service_type,
    :service_subtype,
    :opcode,
    :encoded_binary_base64,
    :encoded_size_bytes,
    :verification_state,
    :failure_reason,
    :attempted_at,
    :released_at,
    released_by: %{},
    lifecycle_state: :release_pending,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      command_release_attempt_id:
        Map.get(
          attrs,
          :command_release_attempt_id,
          Map.get(attrs, "command_release_attempt_id", Ids.new("command_release_attempt"))
        ),
      organization_id: Map.get(attrs, :organization_id, Map.get(attrs, "organization_id")),
      mission_id: Map.fetch!(attrs, :mission_id),
      command_queue_entry_id: Map.fetch!(attrs, :command_queue_entry_id),
      command_request_id: Map.fetch!(attrs, :command_request_id),
      source_endpoint_ref: Map.fetch!(attrs, :source_endpoint_ref),
      realized_contact_id: Map.fetch!(attrs, :realized_contact_id),
      path_id: Map.get(attrs, :path_id, Map.get(attrs, "path_id")),
      transport_binding_id:
        Map.get(attrs, :transport_binding_id, Map.get(attrs, "transport_binding_id")),
      command_snapshot_id: Map.fetch!(attrs, :command_snapshot_id),
      command_id: Map.fetch!(attrs, :command_id),
      command_name: Map.get(attrs, :command_name, Map.get(attrs, "command_name")),
      layout_kind:
        normalize_layout_kind(Map.get(attrs, :layout_kind, Map.get(attrs, "layout_kind"))),
      preferred_uplink_service:
        Map.get(attrs, :preferred_uplink_service, Map.get(attrs, "preferred_uplink_service")),
      apid: Map.get(attrs, :apid, Map.get(attrs, "apid")),
      service_type: Map.get(attrs, :service_type, Map.get(attrs, "service_type")),
      service_subtype: Map.get(attrs, :service_subtype, Map.get(attrs, "service_subtype")),
      opcode: Map.get(attrs, :opcode, Map.get(attrs, "opcode")),
      encoded_binary_base64:
        Map.get(attrs, :encoded_binary_base64, Map.get(attrs, "encoded_binary_base64")),
      encoded_size_bytes:
        Map.get(attrs, :encoded_size_bytes, Map.get(attrs, "encoded_size_bytes")),
      lifecycle_state:
        normalize_lifecycle_state(
          Map.get(attrs, :lifecycle_state, Map.get(attrs, "lifecycle_state", :release_pending))
        ),
      verification_state:
        normalize_verification_state(
          Map.get(attrs, :verification_state, Map.get(attrs, "verification_state"))
        ),
      failure_reason: Map.get(attrs, :failure_reason, Map.get(attrs, "failure_reason")),
      released_by: Map.get(attrs, :released_by, Map.get(attrs, "released_by", %{})),
      attempted_at: Map.get(attrs, :attempted_at, Map.get(attrs, "attempted_at")),
      released_at: Map.get(attrs, :released_at, Map.get(attrs, "released_at")),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end

  defp normalize_lifecycle_state(:release_pending), do: :release_pending
  defp normalize_lifecycle_state("release_pending"), do: :release_pending
  defp normalize_lifecycle_state(:released), do: :released
  defp normalize_lifecycle_state("released"), do: :released
  defp normalize_lifecycle_state(:release_failed), do: :release_failed
  defp normalize_lifecycle_state("release_failed"), do: :release_failed
  defp normalize_lifecycle_state(:canceled), do: :canceled
  defp normalize_lifecycle_state("canceled"), do: :canceled
  defp normalize_lifecycle_state(_other), do: :release_pending

  defp normalize_verification_state(nil), do: nil
  defp normalize_verification_state(:not_required), do: :not_required
  defp normalize_verification_state("not_required"), do: :not_required
  defp normalize_verification_state(:pending), do: :pending
  defp normalize_verification_state("pending"), do: :pending
  defp normalize_verification_state(:satisfied), do: :satisfied
  defp normalize_verification_state("satisfied"), do: :satisfied
  defp normalize_verification_state(:failed), do: :failed
  defp normalize_verification_state("failed"), do: :failed
  defp normalize_verification_state(:timed_out), do: :timed_out
  defp normalize_verification_state("timed_out"), do: :timed_out
  defp normalize_verification_state(_other), do: nil

  defp normalize_layout_kind(nil), do: nil
  defp normalize_layout_kind(layout_kind) when is_atom(layout_kind), do: layout_kind

  defp normalize_layout_kind(layout_kind) when is_binary(layout_kind),
    do: String.to_existing_atom(layout_kind)
end
