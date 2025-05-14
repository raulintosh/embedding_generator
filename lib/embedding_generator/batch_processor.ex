defmodule EmbeddingGenerator.BatchProcessor do
  alias EmbeddingGenerator.{Repo, Workers.BatchEmbeddingWorker}
  alias EmbeddingGenerator.Schema.Image
  import Ecto.Query

  require Logger

  @doc """
  Get the configured batch size from the application environment.
  Defaults to 5 if not configured.
  """
  def get_batch_size do
    Application.get_env(:embedding_generator, __MODULE__, [])
    |> Keyword.get(:batch_size, 5)
  end

  @doc """
  Schedule embedding generation for a batch of images with null embeddings.

  ## Parameters

  - batch_size: Optional. The number of images to process in a batch.
               Defaults to the configured batch size.

  ## Returns

  - `{:ok, count}` where count is the number of images scheduled for processing.
  - `{:error, reason}` if there was an error scheduling the jobs.
  """
  def schedule_pending_embeddings(batch_size \\ nil) do
    batch_size = batch_size || get_batch_size()

    Logger.info("Scheduling embedding generation with batch size: #{batch_size}")

    # Query for images with null embeddings
    query =
      from i in Image,
        where: is_nil(i.embedding),
        select: i.id,
        limit: ^batch_size

    image_ids = Repo.all(query)

    if Enum.empty?(image_ids) do
      Logger.info("No images found with null embeddings")
      {:ok, 0}
    else
      Logger.info("Found #{length(image_ids)} images with null embeddings")

      # Schedule a batch job
      %{image_ids: image_ids}
      |> BatchEmbeddingWorker.new()
      |> Oban.insert()
      |> case do
        {:ok, _job} ->
          {:ok, length(image_ids)}

        error ->
          Logger.error("Failed to schedule batch job: #{inspect(error)}")
          error
      end
    end
  end
end
