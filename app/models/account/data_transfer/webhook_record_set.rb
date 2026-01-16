class Account::DataTransfer::WebhookRecordSet < Account::DataTransfer::RecordSet
  ATTRIBUTES = %w[
    account_id
    active
    board_id
    created_at
    id
    name
    signing_secret
    subscribed_actions
    updated_at
    url
  ].freeze

  private
    def records
      Webhook.where(account: account)
    end

    def export_record(webhook)
      zip.add_file "data/webhooks/#{webhook.id}.json", webhook.as_json.to_json
    end

    def files
      zip.glob("data/webhooks/*.json")
    end

    def import_batch(files)
      batch_data = files.map do |file|
        data = load(file)
        data.slice(*ATTRIBUTES).merge("account_id" => account.id)
      end

      Webhook.insert_all!(batch_data)
    end

    def validate_record(file_path)
      data = load(file_path)
      expected_id = File.basename(file_path, ".json")

      unless data["id"].to_s == expected_id
        raise IntegrityError, "Webhook record ID mismatch: expected #{expected_id}, got #{data['id']}"
      end

      missing = ATTRIBUTES - data.keys
      if missing.any?
        raise IntegrityError, "#{file_path} is missing required fields: #{missing.join(', ')}"
      end
    end
end
