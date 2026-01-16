class Account::DataTransfer::ActiveStorageAttachmentRecordSet < Account::DataTransfer::RecordSet
  ATTRIBUTES = %w[
    account_id
    blob_id
    created_at
    id
    name
    record_id
    record_type
  ].freeze

  private
    def records
      ActiveStorage::Attachment.where(account: account)
    end

    def export_record(attachment)
      zip.add_file "data/active_storage_attachments/#{attachment.id}.json", attachment.as_json.to_json
    end

    def files
      zip.glob("data/active_storage_attachments/*.json")
    end

    def import_batch(files)
      batch_data = files.map do |file|
        data = load(file)
        data.slice(*ATTRIBUTES).merge("account_id" => account.id)
      end

      ActiveStorage::Attachment.insert_all!(batch_data)
    end

    def validate_record(file_path)
      data = load(file_path)
      expected_id = File.basename(file_path, ".json")

      unless data["id"].to_s == expected_id
        raise IntegrityError, "ActiveStorageAttachment record ID mismatch: expected #{expected_id}, got #{data['id']}"
      end

      missing = ATTRIBUTES - data.keys
      if missing.any?
        raise IntegrityError, "#{file_path} is missing required fields: #{missing.join(', ')}"
      end
    end
end
