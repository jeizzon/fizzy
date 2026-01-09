class ImportAccountDataJob < ApplicationJob
  queue_as :backend

  def perform(import)
    import.perform
  end
end
