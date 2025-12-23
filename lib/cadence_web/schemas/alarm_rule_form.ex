defmodule CadenceWeb.Schemas.AlarmRuleForm do
  @moduledoc """
  Embedded schema for alarm rule forms in LiveView.

  This schema provides form validation without database persistence.
  It's used for creating and editing alarm rules through the web interface.

  ## Severity Levels

  - `info` - Informational alerts, no action required
  - `warning` - Warning conditions, may require attention
  - `critical` - Critical conditions, immediate action required

  ## Event Types

  - `telemetry_limit` - Triggered by limit violations

  ## Usage

      # In LiveView
      def mount(_params, _session, socket) do
        form = AlarmRuleForm.changeset() |> to_form()
        {:ok, assign(socket, form: form)}
      end

      def handle_event("validate", %{"alarm_rule_form" => params}, socket) do
        form =
          AlarmRuleForm.changeset(params)
          |> Map.put(:action, :validate)
          |> to_form()

        {:noreply, assign(socket, form: form)}
      end
  """

  use Ecto.Schema
  import Ecto.Changeset

  @severity_values [:info, :warning, :critical]
  @event_types ["telemetry_limit"]

  @primary_key false
  embedded_schema do
    field :name, :string
    field :description, :string
    field :event_type, :string, default: "telemetry_limit"
    field :severity, Ecto.Enum, values: @severity_values, default: :warning
    field :message_template, :string
    field :enabled, :boolean, default: true

    # Scope - set via assigns, not form input
    field :mission_id, :binary_id
    field :target_id, :binary_id

    # Conditions (stored as JSON)
    field :limit_states, {:array, :string}, default: []
    field :item_name, :string
    field :item_name_pattern, :string

    # Behavior modifiers
    field :auto_acknowledge, :boolean, default: false
    field :auto_shelve_duration_minutes, :integer
    field :cooldown_seconds, :integer

    # Notification routing
    field :notification_channels, {:array, :string}, default: []
  end

  @doc """
  Creates a changeset for the alarm rule form.

  ## Examples

      AlarmRuleForm.changeset(%{
        name: "Battery Critical",
        event_type: "telemetry_limit",
        severity: :critical,
        limit_states: ["red"],
        item_name_pattern: "POWER.battery_*"
      })
  """
  def changeset(form \\ %__MODULE__{}, attrs \\ %{}) do
    form
    |> cast(attrs, [
      :name,
      :description,
      :event_type,
      :severity,
      :message_template,
      :enabled,
      :mission_id,
      :target_id,
      :limit_states,
      :item_name,
      :item_name_pattern,
      :auto_acknowledge,
      :auto_shelve_duration_minutes,
      :cooldown_seconds,
      :notification_channels
    ])
    |> validate_required([:name, :event_type, :severity])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_inclusion(:event_type, @event_types)
    |> validate_at_least_one_condition()
    |> validate_number(:auto_shelve_duration_minutes, greater_than: 0)
    |> validate_number(:cooldown_seconds, greater_than: 0, less_than_or_equal_to: 86_400)
  end

  @doc """
  Converts a form struct to domain attributes for creating/updating an alarm rule.
  """
  def to_domain_attrs(%__MODULE__{} = form) do
    conditions = build_conditions(form)

    %{
      name: form.name,
      description: form.description,
      event_type: form.event_type,
      severity: form.severity,
      message_template: form.message_template,
      enabled: form.enabled,
      mission_id: form.mission_id,
      target_id: form.target_id,
      conditions: conditions,
      auto_acknowledge: form.auto_acknowledge,
      auto_shelve_duration_minutes: form.auto_shelve_duration_minutes,
      cooldown_seconds: form.cooldown_seconds,
      notification_channels: form.notification_channels || []
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Creates a form struct from a domain schema for editing.
  """
  def from_schema(%Cadence.Alarms.AlarmRule{} = rule) do
    conditions = rule.conditions || %{}

    %__MODULE__{
      name: rule.name,
      description: rule.description,
      event_type: rule.event_type,
      severity: rule.severity,
      message_template: rule.message_template,
      enabled: rule.enabled,
      mission_id: rule.mission_id,
      target_id: rule.target_id,
      limit_states: Map.get(conditions, "limit_state", []),
      item_name: Map.get(conditions, "item_name"),
      item_name_pattern: Map.get(conditions, "item_name_pattern"),
      auto_acknowledge: rule.auto_acknowledge,
      auto_shelve_duration_minutes: rule.auto_shelve_duration_minutes,
      cooldown_seconds: rule.cooldown_seconds,
      notification_channels: rule.notification_channels || []
    }
  end

  @doc """
  Returns the list of available severity values.
  """
  def severity_values, do: @severity_values

  @doc """
  Returns the list of available event types.
  """
  def event_types, do: @event_types

  @doc """
  Returns a human-readable label for a severity level.
  """
  def severity_label(:info), do: "Info"
  def severity_label(:warning), do: "Warning"
  def severity_label(:critical), do: "Critical"
  def severity_label(_), do: "Unknown"

  # Private helpers

  defp build_conditions(form) do
    conditions = %{}

    conditions =
      if form.limit_states && form.limit_states != [] do
        Map.put(conditions, "limit_state", form.limit_states)
      else
        conditions
      end

    conditions =
      if form.item_name && form.item_name != "" do
        Map.put(conditions, "item_name", form.item_name)
      else
        conditions
      end

    conditions =
      if form.item_name_pattern && form.item_name_pattern != "" do
        Map.put(conditions, "item_name_pattern", form.item_name_pattern)
      else
        conditions
      end

    conditions
  end

  defp validate_at_least_one_condition(changeset) do
    limit_states = get_field(changeset, :limit_states)
    item_name = get_field(changeset, :item_name)
    item_name_pattern = get_field(changeset, :item_name_pattern)

    has_limit_states = limit_states && limit_states != []
    has_item_name = item_name && item_name != ""
    has_pattern = item_name_pattern && item_name_pattern != ""

    if has_limit_states || has_item_name || has_pattern do
      changeset
    else
      add_error(changeset, :limit_states, "at least one condition is required (limit states, item name, or pattern)")
    end
  end
end
