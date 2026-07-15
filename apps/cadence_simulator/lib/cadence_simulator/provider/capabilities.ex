defmodule CadenceSimulator.Provider.Capabilities do
  @moduledoc "Environment-scoped Simulator Provider Contract capabilities."

  alias CadenceSimulator.Provider.Contract

  @confirmation_modes ["immediate", "asynchronous"]
  @idempotency_modes ["native", "client_reference", "none"]
  @recovery_modes ["client_reference", "none"]
  @event_semantics ["at_least_once", "best_effort"]

  @default_behavior %{
    "confirmation" => "asynchronous",
    "idempotency" => "native",
    "recovery" => "client_reference",
    "event_delivery_semantics" => "at_least_once",
    "spacecraft_batch_limit" => 100,
    "station_batch_limit" => 30,
    "page_size_limit" => 100
  }

  @spec default_behavior() :: map()
  def default_behavior, do: @default_behavior

  @spec normalize_behavior(term()) :: {:ok, map()} | {:error, {:invalid, binary()}}
  def normalize_behavior(attrs) when is_map(attrs) do
    behavior = Map.merge(@default_behavior, Contract.sanitize(attrs))

    with :ok <- validate_member(behavior, "confirmation", @confirmation_modes),
         :ok <- validate_member(behavior, "idempotency", @idempotency_modes),
         :ok <- validate_member(behavior, "recovery", @recovery_modes),
         :ok <- validate_member(behavior, "event_delivery_semantics", @event_semantics),
         :ok <- validate_limit(behavior, "spacecraft_batch_limit", 1, 500),
         :ok <- validate_limit(behavior, "station_batch_limit", 1, 100),
         :ok <- validate_limit(behavior, "page_size_limit", 1, 500) do
      {:ok, behavior}
    end
  end

  def normalize_behavior(_attrs), do: {:error, {:invalid, "provider_behavior must be an object"}}

  @spec for_run(map()) :: map()
  def for_run(run) when is_map(run) do
    scenario = run["scenario_snapshot"]
    behavior = Map.get(scenario, "provider_behavior", @default_behavior)

    %{
      "contract_version" => Contract.version(),
      "provider" => %{
        "type" => "cadence_ground_network_simulator",
        "display_name" => "Cadence Ground Network Simulator",
        "simulated" => true
      },
      "operations" => %{
        "opportunity_search" => true,
        "contact_reservation" => true,
        "contact_modification" => false,
        "contact_cancellation" => true,
        "inventory_discovery" => true,
        "delivery_profile_provisioning" => true
      },
      "reservation" => %{
        "confirmation" => behavior["confirmation"],
        "idempotency" => behavior["idempotency"],
        "recovery" => behavior["recovery"]
      },
      "events" => %{
        "polling" => true,
        "webhooks" => false,
        "delivery_semantics" => behavior["event_delivery_semantics"]
      },
      "search" => %{
        "spacecraft_batch_limit" => behavior["spacecraft_batch_limit"],
        "station_batch_limit" => behavior["station_batch_limit"],
        "page_size_limit" => behavior["page_size_limit"]
      },
      "delivery" => %{
        "kinds" => ["realtime_stream"],
        "protocols" => ["tcp"],
        "directions" => ["downlink"]
      }
    }
  end

  defp validate_member(behavior, key, allowed) do
    if behavior[key] in allowed,
      do: :ok,
      else: {:error, {:invalid, "provider_behavior.#{key} is invalid"}}
  end

  defp validate_limit(behavior, key, minimum, maximum) do
    case behavior[key] do
      value when is_integer(value) and value >= minimum and value <= maximum -> :ok
      _other -> {:error, {:invalid, "provider_behavior.#{key} is invalid"}}
    end
  end
end
