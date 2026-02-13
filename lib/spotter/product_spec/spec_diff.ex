defmodule Spotter.ProductSpec.SpecDiff do
  @moduledoc """
  Pure semantic diff engine for product specification trees.

  Compares two domain -> features -> requirements trees and produces
  a structured diff with added, removed, and changed entries.
  """

  @type change :: %{
          level: :domain | :feature | :requirement,
          key: tuple(),
          before: map(),
          after: map(),
          changed_fields: [atom()]
        }

  @type diff_result :: %{
          added: [map()],
          removed: [map()],
          changed: [change()]
        }

  @domain_fields [:name, :description]
  @feature_fields [:name, :description]
  @requirement_fields [:statement, :rationale, :acceptance_criteria, :priority]

  @doc """
  Computes a semantic diff between two product spec trees.

  Identity keys:
  - domain: `spec_key`
  - feature: `{domain_spec_key, feature_spec_key}`
  - requirement: `{domain_spec_key, feature_spec_key, req_spec_key}`

  Returns a map with `:added`, `:removed`, and `:changed` lists.
  """
  @spec diff(list(), list()) :: diff_result()
  def diff(from_tree, to_tree) do
    from_index = index_tree(from_tree)
    to_index = index_tree(to_tree)

    from_keys = MapSet.new(Map.keys(from_index))
    to_keys = MapSet.new(Map.keys(to_index))

    added =
      to_keys
      |> MapSet.difference(from_keys)
      |> Enum.map(&Map.get(to_index, &1))
      |> Enum.sort_by(& &1.key)

    removed =
      from_keys
      |> MapSet.difference(to_keys)
      |> Enum.map(&Map.get(from_index, &1))
      |> Enum.sort_by(& &1.key)

    changed =
      from_keys
      |> MapSet.intersection(to_keys)
      |> Enum.reduce([], fn key, acc ->
        from_entry = Map.get(from_index, key)
        to_entry = Map.get(to_index, key)
        fields = compared_fields(from_entry.level)

        changed_fields =
          Enum.filter(fields, fn field ->
            Map.get(from_entry.data, field) != Map.get(to_entry.data, field)
          end)

        if changed_fields == [] do
          acc
        else
          [
            %{
              level: from_entry.level,
              key: key,
              before: Map.take(from_entry.data, fields),
              after: Map.take(to_entry.data, fields),
              changed_fields: changed_fields
            }
            | acc
          ]
        end
      end)
      |> Enum.sort_by(& &1.key)

    %{added: added, removed: removed, changed: changed}
  end

  defp index_tree(tree) do
    Enum.reduce(tree, %{}, fn domain, acc ->
      domain_key = {domain.spec_key}

      acc
      |> Map.put(domain_key, %{level: :domain, key: domain_key, data: domain})
      |> index_features(domain)
    end)
  end

  defp index_features(acc, domain) do
    Enum.reduce(domain.features, acc, fn feature, acc ->
      feature_key = {domain.spec_key, feature.spec_key}

      acc
      |> Map.put(feature_key, %{level: :feature, key: feature_key, data: feature})
      |> index_requirements(domain.spec_key, feature)
    end)
  end

  defp index_requirements(acc, domain_spec_key, feature) do
    Enum.reduce(feature.requirements, acc, fn req, acc ->
      req_key = {domain_spec_key, feature.spec_key, req.spec_key}
      Map.put(acc, req_key, %{level: :requirement, key: req_key, data: req})
    end)
  end

  defp compared_fields(:domain), do: @domain_fields
  defp compared_fields(:feature), do: @feature_fields
  defp compared_fields(:requirement), do: @requirement_fields
end
