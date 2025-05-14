defmodule EmbeddingGenerator.Repo do
  use Ecto.Repo,
    otp_app: :embedding_generator,
    adapter: Ecto.Adapters.Postgres
end
