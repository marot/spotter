defmodule Spotter.Services.ClaudeCode.ModelTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.ClaudeCode.Model

  describe "normalize/1" do
    test "returns nil for nil" do
      assert Model.normalize(nil) == nil
    end

    test "returns nil for blank string" do
      assert Model.normalize("") == nil
      assert Model.normalize("   ") == nil
    end

    test "maps claude-3-5-haiku-latest to haiku" do
      assert Model.normalize("claude-3-5-haiku-latest") == "haiku"
    end

    test "maps claude-3-5-sonnet-latest to sonnet" do
      assert Model.normalize("claude-3-5-sonnet-latest") == "sonnet"
    end

    test "maps claude-opus-4-6 to opus" do
      assert Model.normalize("claude-opus-4-6") == "opus"
    end

    test "passes through short aliases unchanged" do
      assert Model.normalize("haiku") == "haiku"
      assert Model.normalize("sonnet") == "sonnet"
      assert Model.normalize("opus") == "opus"
    end

    test "passes through full model IDs unchanged" do
      assert Model.normalize("claude-haiku-4-5-20251001") == "claude-haiku-4-5-20251001"
      assert Model.normalize("claude-sonnet-4-5-20250929") == "claude-sonnet-4-5-20250929"
    end
  end
end
