# TypusConnectorSU/export_base64.rb
# Handles encoding an image file to Base64 format

module TypusConnector
  class ExportBase64
    def export(image_path)
      return nil unless valid_image?(image_path)

      encode_base64(image_path)
    end

    private

    def valid_image?(image_path)
      if image_path.nil? || image_path.empty? || !File.exist?(image_path)
        puts 'Invalid image path: File does not exist or path is empty.'
        return false
      end
      true
    end

    def encode_base64(image_path)
      File.open(image_path, 'rb') { |file| Base64.strict_encode64(file.read) }
    rescue StandardError => e
      puts "Error encoding Base64: #{e.message}"
      nil
    end
  end
end
