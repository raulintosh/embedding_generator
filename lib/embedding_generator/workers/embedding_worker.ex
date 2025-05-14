defmodule EmbeddingGenerator.Workers.EmbeddingWorker do
  use Oban.Worker, queue: :embeddings

  alias EmbeddingGenerator.{Repo, S3Service, OllamaService}
  alias EmbeddingGenerator.Schema.Image

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"image_id" => image_id}}) do
    Logger.info("Processing embedding for image #{image_id}")

    # Get image from database
    case Repo.get(Image, image_id) do
      nil ->
        Logger.error("Image not found: #{image_id}")
        {:error, :image_not_found}

      image ->
        try do
          # Download image from S3
          image_binary = S3Service.download_file(image.s3_url)

          # Convert to base64
          image_base64 = Base.encode64(image_binary)

          # Generate embedding using Ollama
          embedding = OllamaService.generate_embedding(image_base64)

          # Update image record with embedding
          case image
               |> Ecto.Changeset.change(%{embedding: embedding})
               |> Repo.update() do
            {:ok, _updated} ->
              Logger.info("Successfully updated embedding for image #{image_id}")
              :ok

            {:error, changeset} ->
              Logger.error("Failed to update image #{image_id}: #{inspect(changeset.errors)}")
              {:error, changeset.errors}
          end
        rescue
          e ->
            Logger.error("Exception while processing image #{image_id}: #{inspect(e)}")
            {:error, Exception.message(e)}
        end
    end
  end
end
