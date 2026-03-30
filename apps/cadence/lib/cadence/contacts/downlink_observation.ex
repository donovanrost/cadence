defmodule Cadence.Contacts.DownlinkObservation do
  @moduledoc """
  Canonical contact-level observation contributed by one downlink path.
  """

  alias Cadence.Contacts.Path
  alias Cadence.Ids

  @type t :: %__MODULE__{
          observation_id: binary(),
          mission_id: binary(),
          realized_contact_id: binary(),
          path_id: binary(),
          source_endpoint_ref: binary() | nil,
          observation_key: binary(),
          payload: term(),
          quality_score: integer(),
          observed_at: DateTime.t(),
          metadata: map()
        }

  defstruct [
    :observation_id,
    :mission_id,
    :realized_contact_id,
    :path_id,
    :source_endpoint_ref,
    :observation_key,
    :payload,
    :quality_score,
    :observed_at,
    metadata: %{}
  ]

  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      observation_id:
        Map.get(attrs, :observation_id, Map.get(attrs, "observation_id", Ids.new("observation"))),
      mission_id: Map.fetch!(attrs, :mission_id),
      realized_contact_id: Map.fetch!(attrs, :realized_contact_id),
      path_id: Map.fetch!(attrs, :path_id),
      source_endpoint_ref:
        Map.get(attrs, :source_endpoint_ref, Map.get(attrs, "source_endpoint_ref")),
      observation_key: Map.fetch!(attrs, :observation_key),
      payload: Map.get(attrs, :payload, Map.get(attrs, "payload")),
      quality_score: Map.get(attrs, :quality_score, Map.get(attrs, "quality_score", 0)),
      observed_at: Map.fetch!(attrs, :observed_at),
      metadata: Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    }
  end

  @spec from_transport_event(binary(), binary(), Path.t(), term(), keyword()) ::
          {:ok, t()} | {:error, term()}
  def from_transport_event(
        mission_id,
        realized_contact_id,
        %Path{} = path,
        %__MODULE__{} = observation,
        opts
      )
      when is_binary(mission_id) and is_binary(realized_contact_id) and is_list(opts) do
    observed_at =
      case observation.observed_at do
        %DateTime{} = value -> value
        nil -> Keyword.get(opts, :occurred_at)
      end

    if match?(%DateTime{}, observed_at) do
      {:ok,
       %__MODULE__{
         observation
         | mission_id: mission_id,
           realized_contact_id: realized_contact_id,
           path_id: path.path_id,
           source_endpoint_ref: observation.source_endpoint_ref || path.source_endpoint_ref,
           observed_at: observed_at
       }}
    else
      {:error, {:invalid_downlink_observation_timestamp, observed_at}}
    end
  end

  def from_transport_event(mission_id, realized_contact_id, %Path{} = path, event, opts)
      when is_binary(mission_id) and is_binary(realized_contact_id) and is_map(event) and
             is_list(opts) do
    case event_kind(event) do
      :downlink_observation ->
        observation_key = Map.get(event, :observation_key, Map.get(event, "observation_key"))
        observed_at = Keyword.get(opts, :occurred_at, Map.get(event, :observed_at))

        cond do
          not is_binary(observation_key) ->
            {:error, {:invalid_downlink_observation_key, observation_key}}

          not match?(%DateTime{}, observed_at) ->
            {:error, {:invalid_downlink_observation_timestamp, observed_at}}

          true ->
            {:ok,
             new(%{
               mission_id: mission_id,
               realized_contact_id: realized_contact_id,
               path_id: path.path_id,
               source_endpoint_ref: path.source_endpoint_ref,
               observation_key: observation_key,
               payload: Map.get(event, :payload, Map.get(event, "payload")),
               quality_score: Map.get(event, :quality_score, Map.get(event, "quality_score", 0)),
               observed_at: observed_at,
               metadata: Map.get(event, :metadata, Map.get(event, "metadata", %{}))
             })}
        end

      _other ->
        {:error, :not_downlink_observation}
    end
  end

  def from_transport_event(_mission_id, _realized_contact_id, %Path{}, _event, _opts),
    do: {:error, :not_downlink_observation}

  defp event_kind(event) do
    case Map.get(event, :kind, Map.get(event, "kind")) do
      :downlink_observation -> :downlink_observation
      "downlink_observation" -> :downlink_observation
      _other -> :unknown
    end
  end
end
