defmodule CadenceWeb.SpacecraftApplicationSummary do
  @moduledoc "Host-facing aggregate status for spacecraft application inventory surfaces."

  alias Cadence.Applications.Status
  alias Cadence.Reads.Applications.Inventory
  alias Cadence.Reads.Applications.InventoryItem

  @type t :: %{
          status: Status.t(),
          description: binary(),
          action_label: binary(),
          ready?: boolean()
        }

  @spec build(map() | nil, [InventoryItem.t()]) :: t()
  def build(nil, []) do
    status = %Status{state: :profile_required, label: "Profile required", tone: :blocked}

    %{
      status: status,
      description: "Select a spacecraft profile before installing product applications.",
      action_label: "Review applications",
      ready?: false
    }
  end

  def build(nil, applications) when is_list(applications) do
    status = Inventory.summary(applications)

    %{
      status: status,
      description:
        "Retained installations remain available; select a spacecraft profile to restore desired application declarations.",
      action_label: "Review applications",
      ready?: false
    }
  end

  def build(_type_binding, applications) when is_list(applications) do
    status = Inventory.summary(applications)

    %{
      status: status,
      description: description(applications, status),
      action_label: "Review applications",
      ready?: status.tone == :ready
    }
  end

  defp description([], %Status{}) do
    "This spacecraft profile does not declare any product applications."
  end

  defp description([%InventoryItem{} = application], %Status{} = status) do
    "#{application.display_name}: #{status.label}."
  end

  defp description(applications, %Status{} = status) do
    "#{status.label} across #{length(applications)} profile applications."
  end
end
