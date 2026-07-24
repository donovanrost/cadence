defmodule CadenceWeb.API.RuntimeIngressParams do
  @moduledoc "Development data-plane ingress request parsing boundary."

  alias CadenceWeb.ControlPlaneParams, as: LegacyParams

  defdelegate dev_space_packet_ingress(mission_id, params), to: LegacyParams
  defdelegate dev_tm_frame_ingress(mission_id, params), to: LegacyParams
end
