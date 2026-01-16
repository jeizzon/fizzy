class Account::DataTransfer::ActiveStorageBlobRecordSet < Account::DataTransfer::RecordSet
  ATTRIBUTES = %w[
    account_id
    byte_size
    checksum
    content_type
    created_at
    filename
    id
    key
    metadata
    service_name
  ].freeze

  private
    def records
      ActiveStorage::Blob.where(account: account)
    end

    def export_record(blob)
      zip.add_file "data/active_storage_blobs/#{blob.id}.json", blob.as_json.to_json
    end

    def files
      zip.glob("data/active_storage_blobs/*.json")
    end

    def import_batch(files)
      batch_data = files.map do |file|
        data = load(file)
        data.slice(*ATTRIBUTES).merge("account_id" => account.id)
      end

      ActiveStorage::Blob.insert_all!(batch_data)
    end

    def validate_record(file_path)
      data = load(file_path)
      expected_id = File.basename(file_path, ".json")

      unless data["id"].to_s == expected_id
        raise IntegrityError, "ActiveStorageBlob record ID mismatch: expected #{expected_id}, got #{data['id']}"
      end

      missing = ATTRIBUTES - data.keys
      if missing.any?
        raise IntegrityError, "#{file_path} is missing required fields: #{missing.join(', ')}"
      end
    end
end
