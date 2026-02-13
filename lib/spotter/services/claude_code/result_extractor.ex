defmodule Spotter.Services.ClaudeCode.ResultExtractor do
  @moduledoc """
  Pure functions for extracting text, structured output, and metadata
  from `ClaudeAgentSDK.Message` lists (or plain maps shaped like them).
  """

  @doc """
  Extracts the text result from a message list.

  Prefers the `:result` message's `result` field. Falls back to the
  last assistant message's text content.
  """
  @spec extract_text([map()]) :: {:ok, String.t()} | {:error, :no_text_content}
  def extract_text(messages) when is_list(messages) do
    with :not_found <- extract_result_text(messages),
         :not_found <- extract_last_assistant_text(messages) do
      {:error, :no_text_content}
    end
  end

  @doc """
  Extracts structured output (JSON map) from the `:result` message.
  """
  @spec extract_structured_output([map()]) :: {:ok, map()} | {:error, :no_structured_output}
  def extract_structured_output(messages) when is_list(messages) do
    messages
    |> find_result_message()
    |> case do
      %{data: %{structured_output: output}} when is_map(output) -> {:ok, output}
      %{data: data} when is_map(data) -> map_structured_output(data)
      _ -> {:error, :no_structured_output}
    end
  end

  @doc """
  Extracts the model identifier from the system init message.
  """
  @spec extract_model_used([map()]) :: String.t() | nil
  def extract_model_used(messages) when is_list(messages) do
    ClaudeAgentSDK.Session.extract_model(messages)
  end

  # --- private helpers ---

  defp extract_result_text(messages) do
    case find_result_message(messages) do
      %{data: %{result: text}} when is_binary(text) and text != "" -> {:ok, text}
      _ -> :not_found
    end
  end

  defp extract_last_assistant_text(messages) do
    messages
    |> Enum.filter(&assistant?/1)
    |> List.last()
    |> case do
      nil ->
        :not_found

      msg ->
        text = ClaudeAgentSDK.ContentExtractor.extract_text(msg)
        if is_binary(text) and text != "", do: {:ok, text}, else: :not_found
    end
  end

  defp find_result_message(messages) do
    Enum.find(messages, &result?/1)
  end

  defp map_structured_output(data) do
    case Map.get(data, "structured_output") || Map.get(data, :structured_output) do
      output when is_map(output) -> {:ok, output}
      _ -> {:error, :no_structured_output}
    end
  end

  defp result?(%{type: :result}), do: true
  defp result?(%{type: "result"}), do: true
  defp result?(_), do: false

  defp assistant?(%{type: :assistant}), do: true
  defp assistant?(%{type: "assistant"}), do: true
  defp assistant?(_), do: false
end
