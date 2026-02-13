defmodule Spotter.ProductSpec do
  @moduledoc """
  Public read API for the versioned product specification stored in Dolt.

  All functions return empty results when the product spec feature is disabled.
  """

  import Ecto.Query

  alias Spotter.ProductSpec.Config
  alias Spotter.ProductSpec.Repo

  @doc "Returns whether the product spec feature is enabled."
  @spec enabled?() :: boolean()
  defdelegate enabled?, to: Config

  @doc "Lists all domains for the given project, sorted by name."
  @spec list_domains(String.t()) :: [map()]
  def list_domains(project_id) do
    if Config.enabled?() do
      from(d in "product_domains",
        where: d.project_id == ^project_id,
        order_by: [asc: d.name],
        select: %{
          id: d.id,
          project_id: d.project_id,
          spec_key: d.spec_key,
          name: d.name,
          description: d.description,
          updated_by_git_commit: d.updated_by_git_commit,
          inserted_at: d.inserted_at,
          updated_at: d.updated_at
        }
      )
      |> Repo.all()
    else
      []
    end
  end

  @doc "Lists all features for the given project and domain, sorted by name."
  @spec list_features(String.t(), String.t()) :: [map()]
  def list_features(project_id, domain_id) do
    if Config.enabled?() do
      from(f in "product_features",
        where: f.project_id == ^project_id and f.domain_id == ^domain_id,
        order_by: [asc: f.name],
        select: %{
          id: f.id,
          project_id: f.project_id,
          domain_id: f.domain_id,
          spec_key: f.spec_key,
          name: f.name,
          description: f.description,
          updated_by_git_commit: f.updated_by_git_commit,
          inserted_at: f.inserted_at,
          updated_at: f.updated_at
        }
      )
      |> Repo.all()
    else
      []
    end
  end

  @doc "Lists all requirements for the given project and feature, sorted by spec_key."
  @spec list_requirements(String.t(), String.t()) :: [map()]
  def list_requirements(project_id, feature_id) do
    if Config.enabled?() do
      from(r in "product_requirements",
        where: r.project_id == ^project_id and r.feature_id == ^feature_id,
        order_by: [asc: r.spec_key],
        select: %{
          id: r.id,
          project_id: r.project_id,
          feature_id: r.feature_id,
          spec_key: r.spec_key,
          statement: r.statement,
          rationale: r.rationale,
          acceptance_criteria: r.acceptance_criteria,
          priority: r.priority,
          updated_by_git_commit: r.updated_by_git_commit,
          inserted_at: r.inserted_at,
          updated_at: r.updated_at
        }
      )
      |> Repo.all()
    else
      []
    end
  end

  @doc """
  Returns the full domain -> features -> requirements tree for a project.

  Domains are sorted by name, features by name, requirements by spec_key.
  """
  @spec tree(String.t()) :: [map()]
  def tree(project_id) do
    if Config.enabled?() do
      domains = list_domains(project_id)
      features_by_domain = list_all_features(project_id)
      requirements_by_feature = list_all_requirements(project_id)

      Enum.map(domains, &attach_features(&1, features_by_domain, requirements_by_feature))
    else
      []
    end
  end

  defp attach_features(domain, features_by_domain, requirements_by_feature) do
    features =
      features_by_domain
      |> Map.get(domain.id, [])
      |> Enum.map(&Map.put(&1, :requirements, Map.get(requirements_by_feature, &1.id, [])))

    Map.put(domain, :features, features)
  end

  defp list_all_features(project_id) do
    from(f in "product_features",
      where: f.project_id == ^project_id,
      order_by: [asc: f.name],
      select: %{
        id: f.id,
        project_id: f.project_id,
        domain_id: f.domain_id,
        spec_key: f.spec_key,
        name: f.name,
        description: f.description,
        updated_by_git_commit: f.updated_by_git_commit,
        inserted_at: f.inserted_at,
        updated_at: f.updated_at
      }
    )
    |> Repo.all()
    |> Enum.group_by(& &1.domain_id)
  end

  defp list_all_requirements(project_id) do
    from(r in "product_requirements",
      where: r.project_id == ^project_id,
      order_by: [asc: r.spec_key],
      select: %{
        id: r.id,
        project_id: r.project_id,
        feature_id: r.feature_id,
        spec_key: r.spec_key,
        statement: r.statement,
        rationale: r.rationale,
        acceptance_criteria: r.acceptance_criteria,
        priority: r.priority,
        updated_by_git_commit: r.updated_by_git_commit,
        inserted_at: r.inserted_at,
        updated_at: r.updated_at
      }
    )
    |> Repo.all()
    |> Enum.group_by(& &1.feature_id)
  end
end
