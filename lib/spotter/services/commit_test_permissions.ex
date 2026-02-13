defmodule Spotter.Services.CommitTestPermissions do
  @moduledoc """
  Permission callback for the commit test agent.

  Deny-by-default: only allows tools from the spotter-tests MCP server.
  """

  alias ClaudeAgentSDK.Permission.Result
  alias Spotter.Agents.TestToolServer

  @doc "Permission callback for `can_use_tool` option."
  def can_use_tool(%{tool_name: tool_name}) do
    if tool_name in TestToolServer.allowed_tools() do
      Result.allow()
    else
      Result.deny("Tool #{tool_name} is not allowed for commit test analysis")
    end
  rescue
    _ -> Result.deny("Permission check failed")
  end

  def can_use_tool(_), do: Result.deny("Invalid permission context")
end
