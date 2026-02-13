defmodule Spotter.Transcripts.ProjectIngestState do
  @moduledoc "Rate-limiting state for commit ingestion per project."

  use Ash.Resource,
    domain: Spotter.Transcripts,
    data_layer: AshSqlite.DataLayer

  sqlite do
    table "project_ingest_states"
    repo Spotter.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:project_id, :last_commit_ingest_at]

      upsert? true
      upsert_identity :unique_project
      upsert_fields [:last_commit_ingest_at]
    end

    update :update do
      primary? true
      accept [:last_commit_ingest_at]
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :last_commit_ingest_at, :utc_datetime_usec

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :project, Spotter.Transcripts.Project do
      allow_nil? false
    end
  end

  identities do
    identity :unique_project, [:project_id]
  end
end
