defmodule CookingScheduler.Storage do
  @moduledoc """
  Object storage for uploaded files (meal and dish photos). The bucket is private: files are
  read back with `get/1` and served by `PhotoController`.

  The adapter is set per environment: `Storage.Local` (files on disk) in development and
  tests, `Storage.Tigris` (Fly's S3-compatible storage) in production when `BUCKET_NAME` is set.
  """

  @callback put(key :: String.t(), body :: binary(), content_type :: String.t()) ::
              :ok | {:error, term()}
  @callback delete(key :: String.t()) :: :ok | {:error, term()}
  @callback get(key :: String.t()) :: {:ok, binary()} | {:error, term()}

  @doc "Whether an adapter is configured, so the upload UI should be shown."
  def enabled?, do: adapter() != nil

  def put(key, body, content_type), do: adapter().put(key, body, content_type)
  def delete(key), do: adapter().delete(key)
  def get(key), do: adapter().get(key)

  defp adapter, do: Application.get_env(:cooking_scheduler, __MODULE__, [])[:adapter]
end
