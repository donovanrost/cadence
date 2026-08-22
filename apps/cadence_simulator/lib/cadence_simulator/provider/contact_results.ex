defmodule CadenceSimulator.Provider.ContactResults do
  @moduledoc "Builds bounded provider Contact Result evidence from a telemetry worker snapshot."

  alias CadenceSimulator.Provider.Contacts

  @spec fetch(map(), binary()) :: {:ok, map()} | {:error, :not_found | :not_ready}
  def fetch(run, contact_id) do
    with {:ok, contact} <- Contacts.fetch_internal(contact_id),
         true <- contact["run_id"] == run["id"],
         %{} = result <- contact["result"] do
      {:ok, result}
    else
      false -> {:error, :not_found}
      nil -> {:error, :not_ready}
      error -> error
    end
  end

  @spec build(map(), map(), binary()) :: map()
  def build(contact, stats \\ %{}, outcome \\ "completed") do
    send_buffer_stats = Map.get(stats, :send_buffer_stats, %{})
    actual_acquisition_at = contact["actual_acquisition_at"]

    actual_loss_at =
      contact["actual_loss_at"] || DateTime.utc_now() |> DateTime.to_iso8601()

    %{
      "contact_ref" => contact["id"],
      "outcome" => outcome,
      "planned_acquisition_at" => contact["starts_at"],
      "planned_loss_at" => contact["ends_at"],
      "actual_acquisition_at" => actual_acquisition_at,
      "actual_loss_at" => actual_loss_at,
      "delivered_duration_seconds" => duration(actual_acquisition_at, actual_loss_at),
      "bytes_delivered" => Map.get(send_buffer_stats, :bytes_sent, 0),
      "packets_delivered" => Map.get(send_buffer_stats, :packets_sent, 0),
      "frames_delivered" => Map.get(stats, :packet_count, 0),
      "objects_delivered" => 0,
      "observations" => %{
        "loss" => 0,
        "duplication" => 0,
        "corruption" => 0,
        "disconnects" => disconnect_count(contact)
      },
      "provider_failure_reason" => contact["status_reason"],
      "delivery_failure_reason" => get_in(contact, ["delivery", "reason"]),
      "delivery_profile_ref" => contact["delivery_profile_ref"],
      "delivery_endpoint_ref" => get_in(contact, ["delivery", "endpoint_ref"]),
      "extensions" => %{}
    }
  end

  defp duration(nil, _loss_at), do: 0

  defp duration(acquisition_at, loss_at) do
    with {:ok, acquired, _offset} <- DateTime.from_iso8601(acquisition_at),
         {:ok, lost, _offset} <- DateTime.from_iso8601(loss_at) do
      max(0, DateTime.diff(lost, acquired))
    else
      _error -> 0
    end
  end

  defp disconnect_count(contact) do
    if get_in(contact, ["delivery", "reason"]), do: 1, else: 0
  end
end
