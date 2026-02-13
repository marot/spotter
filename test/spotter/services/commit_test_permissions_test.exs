defmodule Spotter.Services.CommitTestPermissionsTest do
  use ExUnit.Case, async: true

  alias Spotter.Agents.TestToolServer
  alias Spotter.Services.CommitTestPermissions

  describe "can_use_tool/1" do
    test "allows all spotter-tests tools" do
      for tool <- TestToolServer.allowed_tools() do
        result = CommitTestPermissions.can_use_tool(%{tool_name: tool})
        assert result.behavior == :allow, "Expected #{tool} to be allowed"
      end
    end

    test "denies unknown tools" do
      result = CommitTestPermissions.can_use_tool(%{tool_name: "Bash"})
      assert result.behavior == :deny
    end

    test "denies built-in tools" do
      for tool <- ["Read", "Edit", "Write", "Bash", "Glob", "Grep"] do
        result = CommitTestPermissions.can_use_tool(%{tool_name: tool})
        assert result.behavior == :deny
      end
    end

    test "never raises on bad input" do
      result = CommitTestPermissions.can_use_tool(%{})
      assert result.behavior == :deny

      result = CommitTestPermissions.can_use_tool(nil)
      assert result.behavior == :deny
    end
  end
end
