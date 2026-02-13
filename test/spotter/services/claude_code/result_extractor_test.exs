defmodule Spotter.Services.ClaudeCode.ResultExtractorTest do
  use ExUnit.Case, async: true

  alias Spotter.Services.ClaudeCode.ResultExtractor

  defp system_msg(attrs \\ %{}) do
    %ClaudeAgentSDK.Message{
      type: :system,
      subtype: :init,
      data: Map.merge(%{session_id: "sess-1", model: "sonnet"}, attrs),
      raw: %{}
    }
  end

  defp assistant_msg(text) do
    %ClaudeAgentSDK.Message{
      type: :assistant,
      subtype: nil,
      data: %{message: %{"content" => text}, session_id: "sess-1"},
      raw: %{}
    }
  end

  defp result_msg(attrs \\ %{}) do
    %ClaudeAgentSDK.Message{
      type: :result,
      subtype: :success,
      data: Map.merge(%{result: "Final answer", session_id: "sess-1"}, attrs),
      raw: %{}
    }
  end

  describe "extract_text/1" do
    test "extracts text from result message" do
      messages = [system_msg(), assistant_msg("intermediate"), result_msg()]
      assert {:ok, "Final answer"} = ResultExtractor.extract_text(messages)
    end

    test "falls back to last assistant message when result has no text" do
      messages = [system_msg(), assistant_msg("fallback text"), result_msg(%{result: nil})]
      assert {:ok, "fallback text"} = ResultExtractor.extract_text(messages)
    end

    test "returns error when no text content exists" do
      messages = [system_msg()]
      assert {:error, :no_text_content} = ResultExtractor.extract_text(messages)
    end

    test "returns error for empty list" do
      assert {:error, :no_text_content} = ResultExtractor.extract_text([])
    end
  end

  describe "extract_structured_output/1" do
    test "extracts structured output map from result message" do
      output = %{"summary" => "hello", "score" => 42}
      messages = [system_msg(), result_msg(%{structured_output: output})]
      assert {:ok, ^output} = ResultExtractor.extract_structured_output(messages)
    end

    test "returns error when no structured output" do
      messages = [system_msg(), result_msg()]
      assert {:error, :no_structured_output} = ResultExtractor.extract_structured_output(messages)
    end
  end

  describe "extract_model_used/1" do
    test "extracts model from system message" do
      messages = [system_msg(%{model: "opus"}), assistant_msg("hi")]
      assert "opus" == ResultExtractor.extract_model_used(messages)
    end

    test "returns nil when no system message" do
      messages = [assistant_msg("hi")]
      assert is_nil(ResultExtractor.extract_model_used(messages))
    end
  end
end
