if Application.get_env(:claude_agent_sdk, :use_mock, false) do
  {:ok, _pid} = ClaudeAgentSDK.Mock.start_link()
end

ExUnit.start(exclude: [:live_dolt, :live_api])
