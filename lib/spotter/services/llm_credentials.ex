defmodule Spotter.Services.LlmCredentials do
  @moduledoc "Shared credential resolution for LLM services."

  @doc """
  Resolves the Anthropic API key from LangChain app config or environment.

  Returns `{:ok, key}` when a non-blank key is found,
  or `{:error, :missing_api_key}` otherwise.
  """
  @spec anthropic_api_key() :: {:ok, String.t()} | {:error, :missing_api_key}
  def anthropic_api_key do
    candidates = [
      Application.get_env(:langchain, :anthropic_key),
      System.get_env("ANTHROPIC_API_KEY")
    ]

    case Enum.find(candidates, &present?/1) do
      nil -> {:error, :missing_api_key}
      key -> {:ok, key}
    end
  end

  defp present?(nil), do: false
  defp present?(s) when is_binary(s), do: String.trim(s) != ""
  defp present?(_), do: false
end
