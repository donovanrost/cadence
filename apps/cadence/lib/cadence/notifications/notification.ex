defmodule Cadence.Notifications.Notification do
  @moduledoc """
  Per-user notification record. The `kind` atom identifies the semantic type
  (e.g. `:organization_invitation`); `metadata` carries kind-specific payload.
  """

  alias Cadence.Ids

  @type kind :: atom()

  @type t :: %__MODULE__{
          notification_id: binary(),
          user_id: binary(),
          kind: kind(),
          title: binary(),
          body: binary() | nil,
          action_url: binary() | nil,
          metadata: map(),
          read_at: DateTime.t() | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  defstruct [
    :notification_id,
    :user_id,
    :kind,
    :title,
    :body,
    :action_url,
    :read_at,
    :inserted_at,
    :updated_at,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      notification_id: map_value(attrs, :notification_id, "notification_id") || Ids.new("notif"),
      user_id: map_fetch!(attrs, :user_id, "user_id"),
      kind: normalize_kind(map_fetch!(attrs, :kind, "kind")),
      title: map_fetch!(attrs, :title, "title"),
      body: map_value(attrs, :body, "body"),
      action_url: map_value(attrs, :action_url, "action_url"),
      metadata: map_value(attrs, :metadata, "metadata") || %{},
      read_at: map_value(attrs, :read_at, "read_at")
    }
  end

  @spec unread?(t()) :: boolean()
  def unread?(%__MODULE__{read_at: nil}), do: true
  def unread?(%__MODULE__{}), do: false

  defp normalize_kind(kind) when is_atom(kind), do: kind
  defp normalize_kind(kind) when is_binary(kind), do: String.to_existing_atom(kind)

  defp map_fetch!(attrs, atom_key, string_key) when is_map(attrs) do
    case map_value(attrs, atom_key, string_key) do
      nil -> raise KeyError, key: atom_key, term: attrs
      value -> value
    end
  end

  defp map_value(attrs, atom_key, string_key) when is_map(attrs) do
    Map.get(attrs, atom_key) || Map.get(attrs, string_key)
  end
end
