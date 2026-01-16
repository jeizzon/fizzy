class Account::DataTransfer::WebhookDeliveryRecordSet < Account::DataTransfer::RecordSet
  ATTRIBUTES = %w[
    account_id
    created_at
    event_id
    id
    request
    response
    state
    updated_at
    webhook_id
  ].freeze

  private
    def records
      Webhook::Delivery.where(account: account)
    end

    def export_record(delivery)
      zip.add_file "data/webhook_deliveries/#{delivery.id}.json", delivery.as_json.to_json
    end

    def files
      zip.glob("data/webhook_deliveries/*.json")
    end

    def import_batch(files)
      batch_data = files.map do |file|
        data = load(file)
        data.slice(*ATTRIBUTES).merge("account_id" => account.id)
      end

      Webhook::Delivery.insert_all!(batch_data)
    end

    def validate_record(file_path)
      data = load(file_path)
      expected_id = File.basename(file_path, ".json")

      unless data["id"].to_s == expected_id
        raise IntegrityError, "WebhookDelivery record ID mismatch: expected #{expected_id}, got #{data['id']}"
      end

      missing = ATTRIBUTES - data.keys
      if missing.any?
        raise IntegrityError, "#{file_path} is missing required fields: #{missing.join(', ')}"
      end
    end
end
