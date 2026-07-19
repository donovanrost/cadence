defmodule CadenceWeb.OpsDashboardShowLive.OperationalObservableSourceEndpointCommandQueueScenario do
  @moduledoc false

  alias CadenceWeb.OpsDashboardShowLive.{
    OperationalObservableSourceEndpointCommandQueueSetup,
    OperationalObservableSourceEndpointReleaseBackLinks,
    OperationalObservableSourceEndpointReleaseEvidence,
    OperationalObservableSourceEndpointTransportEvidence,
    OperationalObservableSourceEndpointVerifierEvidence
  }

  def run do
    OperationalObservableSourceEndpointCommandQueueSetup.run()
    |> OperationalObservableSourceEndpointReleaseEvidence.run()
    |> OperationalObservableSourceEndpointVerifierEvidence.run()
    |> OperationalObservableSourceEndpointTransportEvidence.run()
    |> OperationalObservableSourceEndpointReleaseBackLinks.run()
  end
end
