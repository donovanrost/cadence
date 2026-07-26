defmodule Cadence.Applications.LifecycleActions do
  @moduledoc "Registry of Cadence-owned standard application lifecycle actions."

  alias Cadence.Applications.{ActionConfirmation, LifecycleActionDefinition}

  @type fetch_error :: :unknown_application_lifecycle_action

  @spec all() :: [LifecycleActionDefinition.t()]
  def all do
    [
      action("install", "Install", "operate_mission", :immediate, :primary),
      upgrade(),
      action("save_configuration", "Save configuration", "operate_mission", :immediate, :primary),
      restore(),
      request_activation(),
      request_deactivation(),
      disable(),
      uninstall()
    ]
  end

  @spec fetch(binary()) ::
          {:ok, LifecycleActionDefinition.t()} | {:error, fetch_error()}
  def fetch(action_id) when is_binary(action_id) do
    case Enum.find(all(), &(&1.action_id == action_id)) do
      %LifecycleActionDefinition{} = action -> {:ok, action}
      nil -> {:error, :unknown_application_lifecycle_action}
    end
  end

  def fetch(_action_id), do: {:error, :unknown_application_lifecycle_action}

  defp upgrade do
    action(
      "upgrade",
      "Upgrade",
      "operate_mission",
      :immediate,
      :secondary,
      confirmation(
        "Upgrade application?",
        "Migrate this installation to the registered application version while retaining its governed configuration.",
        "Upgrade",
        :attention
      )
    )
  end

  defp restore do
    action(
      "restore_configuration",
      "Restore configuration",
      "operate_mission",
      :immediate,
      :secondary,
      confirmation(
        "Restore application configuration?",
        "Create a new governed configuration version from the selected prior version.",
        "Restore configuration",
        :attention
      )
    )
  end

  defp request_activation do
    action(
      "request_activation",
      "Request mission changes",
      "request_activation",
      :approval_required,
      :primary,
      confirmation(
        "Request mission changes?",
        "Submit the current application configuration for governed approval. It will not become live until an authorized approver accepts and executes the request.",
        "Request mission changes",
        :attention
      )
    )
  end

  defp request_deactivation do
    action(
      "request_deactivation",
      "Request deactivation",
      "request_activation",
      :approval_required,
      :secondary,
      confirmation(
        "Request application deactivation?",
        "Submit a governed request to remove this application from the live mission configuration.",
        "Request deactivation",
        :attention
      )
    )
  end

  defp disable do
    action(
      "disable",
      "Disable workspace",
      "operate_mission",
      :immediate,
      :secondary,
      confirmation(
        "Disable application workspace?",
        "Workspace access and configuration editing will stop. Existing configuration is retained, and active runtime state is unchanged until a separately governed mission change is applied.",
        "Disable workspace",
        :attention
      )
    )
  end

  defp uninstall do
    action(
      "uninstall",
      "Uninstall",
      "operate_mission",
      :immediate,
      :danger,
      confirmation(
        "Uninstall host access?",
        "The durable installation record and application configuration will be retained. Active runtime state is unchanged.",
        "Uninstall",
        :danger
      )
    )
  end

  defp action(action_id, label, permission, execution, variant, confirmation \\ nil) do
    %LifecycleActionDefinition{
      action_id: action_id,
      label: label,
      required_permission: permission,
      effect: :durable,
      execution: execution,
      button_variant: variant,
      confirmation: confirmation
    }
  end

  defp confirmation(title, message, confirm_label, tone) do
    %ActionConfirmation{
      title: title,
      message: message,
      confirm_label: confirm_label,
      tone: tone
    }
  end
end
