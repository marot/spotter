defmodule Spotter.Services.ClaudeCode.Model do
  @moduledoc """
  Normalizes model name strings for the Claude Code CLI.

  Maps legacy/full model identifiers to short CLI aliases where possible,
  and passes through everything else unchanged.
  """

  @exact_mappings %{
    "claude-3-5-haiku-latest" => "haiku",
    "claude-3-5-sonnet-latest" => "sonnet",
    "claude-opus-4-6" => "opus"
  }

  @doc """
  Normalizes a raw model string to its CLI alias.

  Returns `nil` for nil/blank input (caller omits model, CLI picks default).
  Returns a short alias for known full names, or passes through as-is.
  """
  @spec normalize(String.t() | nil) :: String.t() | nil
  def normalize(nil), do: nil

  def normalize(raw) when is_binary(raw) do
    trimmed = String.trim(raw)
    if trimmed == "", do: nil, else: Map.get(@exact_mappings, trimmed, trimmed)
  end
end
