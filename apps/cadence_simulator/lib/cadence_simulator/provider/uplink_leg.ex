defmodule CadenceSimulator.Provider.UplinkLeg do
  @moduledoc """
  The optional uplink leg of a contact request (#44, DECISIONS #46).

  A request may carry `"uplink" => %{"service_profile_ref", "delivery_profile_ref"}`. A booked
  contact then reports the leg as `"included"` (the uplink session opens with the pass) or
  `"rejected"` with a `status_reason`, so a client can tell "uplink booked" from "uplink not
  booked". A malformed leg rejects the whole request; an uplink delivery that isn't ready only
  rejects the leg.
  """

  alias CadenceSimulator.Provider.{DeliveryProfiles, ServiceProfiles}

  @uplink_directions ["uplink", "bidirectional"]

  @spec normalize(map()) :: {:ok, map() | nil} | {:error, {:invalid, binary()}}
  def normalize(%{"uplink" => nil}), do: {:ok, nil}

  def normalize(%{"uplink" => %{} = leg}) do
    if Enum.all?(
         ["service_profile_ref", "delivery_profile_ref"],
         &(is_binary(leg[&1]) and leg[&1] != "")
       ),
       do: {:ok, Map.take(leg, ["service_profile_ref", "delivery_profile_ref"])},
       else: {:error, {:invalid, "uplink needs service_profile_ref and delivery_profile_ref"}}
  end

  def normalize(%{"uplink" => _other}), do: {:error, {:invalid, "uplink must be an object"}}
  def normalize(_attrs), do: {:ok, nil}

  @doc "Resolves a normalized leg against the run's profiles."
  @spec resolve(map(), map() | nil) :: {:ok, map() | nil} | {:error, {:invalid, binary()}}
  def resolve(_run, nil), do: {:ok, nil}

  def resolve(run, leg) do
    with {:ok, service} <- service(run, leg["service_profile_ref"]),
         {:ok, delivery} <- delivery(run, leg["delivery_profile_ref"], service) do
      {status, reason} =
        if delivery["state"] == "ready",
          do: {"included", nil},
          else: {"rejected", "uplink delivery profile is not ready"}

      {:ok, %{leg: leg, delivery: delivery, status: status, reason: reason}}
    end
  end

  @doc "Contact fields for a resolved leg; the leg is rejected with the contact."
  @spec contact_fields(map() | nil, boolean(), binary() | nil) :: map()
  def contact_fields(nil, _rejected?, _reason), do: %{}

  def contact_fields(resolved, rejected?, contact_reason) do
    {status, reason} =
      if rejected?, do: {"rejected", contact_reason}, else: {resolved.status, resolved.reason}

    %{
      "uplink" =>
        Map.merge(resolved.leg, %{
          "status" => status,
          "status_reason" => reason,
          "framing" => resolved.delivery["framing"] || %{}
        }),
      "uplink_delivery_profile_snapshot" => resolved.delivery
    }
  end

  @doc "The uplink delivery target of a contact whose leg is included, else nil."
  @spec target(map()) :: map() | nil
  def target(%{"uplink" => %{"status" => "included"}} = contact) do
    profile = contact["uplink_delivery_profile_snapshot"] || %{}

    case profile do
      %{"target" => %{"host" => host, "port" => port}, "framing" => %{"frame_bytes" => size}} ->
        %{host: host, port: port, tc_frame_size: size}

      _other ->
        nil
    end
  end

  def target(_contact), do: nil

  defp service(run, id) do
    case Enum.find(ServiceProfiles.for_run(run), &(&1["id"] == id)) do
      %{"state" => "active", "direction" => direction} = service
      when direction in @uplink_directions ->
        {:ok, service}

      _other ->
        {:error, {:invalid, "uplink.service_profile_ref is not an active uplink service"}}
    end
  end

  defp delivery(run, id, service) do
    case DeliveryProfiles.fetch_internal(run, id) do
      {:ok, %{"direction" => direction} = profile}
      when direction in @uplink_directions ->
        cond do
          service["id"] not in (profile["supported_service_profile_refs"] || []) ->
            {:error, {:invalid, "uplink delivery profile does not support the uplink service"}}

          get_in(profile, ["target", "protocol"]) != "tcp" ->
            {:error, {:invalid, "uplink delivery profile has no executable TCP target"}}

          true ->
            {:ok, profile}
        end

      _other ->
        {:error, {:invalid, "uplink.delivery_profile_ref is not an uplink delivery profile"}}
    end
  end
end
