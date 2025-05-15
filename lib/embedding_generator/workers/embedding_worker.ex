defmodule EmbeddingGenerator.Workers.EmbeddingWorker do
  @moduledoc """
  Oban worker for processing individual images to generate embeddings.

  This worker:
  1. Takes a single image ID
  2. Downloads the image from Digital Ocean Spaces
  3. Generates an embedding using Ollama
  4. Updates the database with the embedding

  This worker is useful for processing individual images on-demand,
  while BatchEmbeddingWorker is better for processing multiple images.
  """

  use Oban.Worker, queue: :embeddings, max_attempts: 3

  alias EmbeddingGenerator.{Repo, S3Service, OllamaService}
  alias EmbeddingGenerator.Schema.Image

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"image_id" => image_id}, attempt: attempt}) do
    start_time = System.monotonic_time(:millisecond)
    Logger.info("Starting embedding generation for image #{image_id} (attempt #{attempt})")

    # Get image from database
    db_start_time = System.monotonic_time(:millisecond)
    Logger.debug("Fetching image #{image_id} from database")

    result =
      case Repo.get(Image, image_id) do
        nil ->
          db_duration = System.monotonic_time(:millisecond) - db_start_time
          Logger.error("Image not found in database: #{image_id} (query took #{db_duration}ms)")
          {:error, :image_not_found}

        image ->
          db_duration = System.monotonic_time(:millisecond) - db_start_time

          Logger.debug(
            "Found image in database in #{db_duration}ms: #{inspect(Map.take(image, [:id, :s3_url]))}"
          )

          process_single_image(image, image_id, start_time)
      end

    # Log final result
    total_duration = System.monotonic_time(:millisecond) - start_time

    case result do
      :ok ->
        Logger.info("Successfully processed image #{image_id} in #{total_duration}ms")
        :ok

      {:error, reason} ->
        Logger.error(
          "Failed to process image #{image_id} after #{total_duration}ms: #{inspect(reason)}"
        )

        # Return error to allow Oban to retry if needed
        {:error, reason}
    end
  end

  # Processes a single image by downloading it, generating an embedding, and updating the database.
  defp process_single_image(image, image_id, start_time) do
    try do
      # Download image from S3
      Logger.debug("Downloading image from S3: #{image.s3_url}")
      download_start = System.monotonic_time(:millisecond)
      image_binary = S3Service.download_file(image.s3_url)
      download_duration = System.monotonic_time(:millisecond) - download_start

      binary_size = byte_size(image_binary)
      Logger.debug("Downloaded image (#{binary_size} bytes) in #{download_duration}ms")

      if binary_size == 0 do
        Logger.error("Downloaded image is empty (0 bytes)")
        {:error, :empty_image}
      end

      # Convert to base64
      Logger.debug("Converting image to base64")
      encode_start = System.monotonic_time(:millisecond)
      image_base64 = Base.encode64(image_binary)
      encode_duration = System.monotonic_time(:millisecond) - encode_start

      base64_size = byte_size(image_base64)
      Logger.debug("Converted image to base64 (#{base64_size} bytes) in #{encode_duration}ms")

      # Generate embedding using Ollama
      Logger.debug("Generating embedding using Ollama")
      embedding_start = System.monotonic_time(:millisecond)
      embedding = OllamaService.generate_embedding(image_base64)
      embedding_duration = System.monotonic_time(:millisecond) - embedding_start

      embedding_size = length(embedding)

      Logger.debug(
        "Generated embedding (#{embedding_size} dimensions) in #{embedding_duration}ms"
      )

      if embedding_size == 0 do
        Logger.error("Generated embedding is empty (0 dimensions)")
        {:error, :empty_embedding}
      end

      # Update image record with embedding
      Logger.debug("Updating image record with embedding")
      update_start = System.monotonic_time(:millisecond)

      result =
        image
        |> Ecto.Changeset.change(%{embedding: embedding})
        |> Repo.update()

      update_duration = System.monotonic_time(:millisecond) - update_start

      case result do
        {:ok, _updated} ->
          Logger.debug("Updated image record in #{update_duration}ms")

          # Log performance metrics
          processing_time = System.monotonic_time(:millisecond) - start_time
          Logger.info("Image processing breakdown for #{image_id}:")

          Logger.info(
            "  - Download: #{download_duration}ms (#{Float.round(download_duration / processing_time * 100, 1)}%)"
          )

          Logger.info(
            "  - Base64 encoding: #{encode_duration}ms (#{Float.round(encode_duration / processing_time * 100, 1)}%)"
          )

          Logger.info(
            "  - Embedding generation: #{embedding_duration}ms (#{Float.round(embedding_duration / processing_time * 100, 1)}%)"
          )

          Logger.info(
            "  - Database update: #{update_duration}ms (#{Float.round(update_duration / processing_time * 100, 1)}%)"
          )

          :ok

        {:error, changeset} ->
          errors = changeset.errors
          Logger.error("Failed to update image record: #{inspect(errors)}")
          {:error, {:update_failed, errors}}
      end
    rescue
      e ->
        Logger.error("Exception while processing image #{image_id}: #{Exception.message(e)}")
        Logger.debug("Exception details: #{inspect(e)}")
        Logger.debug("Stacktrace: #{inspect(__STACKTRACE__)}")
        {:error, {:exception, Exception.message(e)}}
    end
  end
end
