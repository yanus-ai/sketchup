# TypusConnectorSU/web_connect.rb
# Handle API and Token for the TypusConnector plugin

module TypusConnector
  class APIConnect

    def export_to_api(json_data, &callback)
      #api_endpoint = URI.parse('https://app.yanus.ai/version-test/api/1.1/wf/revitintegration')
      #api_endpoint = URI.parse('https://app.yanus.ai/api/1.1/wf/revitintegration')
      api_endpoint = URI.parse('https://app.typus.ai/api/webhooks/create-input-image')
      #api_endpoint = URI.parse('https://lemon-vans-judge.loca.lt/api/webhooks/create-input-image')
      http = Net::HTTP.new(api_endpoint.host, api_endpoint.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE  # Bypass SSL verification for testing

      request = Net::HTTP::Post.new(api_endpoint.path, { 'Content-Type' => 'application/json' })
      request["Authorization"] = "Bearer #{get_token}" if get_token
      request.body = json_data

      result = nil

      begin
        response = http.request(request)
        result = response.body
        if response.code.to_i != 201
          puts "[Typus ERROR] HTTP Error #{response.code}: #{response.body}" if response.code.to_i >= 400
        end
      rescue StandardError => e
        puts "[Typus ERROR] Request Failed: #{e.message}"
      end

      # Execute the callback with the result if provided
      callback.call(result) if callback
      #result
    end


    # Method to get and set token.
    def get_token
      token = decrypt_token
      token if token
    end

    def set_token(token)
      if token.nil?
        Sketchup.write_default('TypusConnector', 'Typustk', nil)
      else
        store_token(token)
      end
      true
    end

    private

    # Generate a unique encryption key
    def generate_encryption_key
      stored_salt = Sketchup.read_default('TypusConnector', 'encryption_salt', nil)

      unless stored_salt
        random_salt = OpenSSL::Random.random_bytes(16) # Generate a 16-byte random salt
        encoded_salt = Base64.strict_encode64(random_salt) # Encode for safe storage
        Sketchup.write_default('TypusConnector', 'encryption_salt', encoded_salt)
        stored_salt = encoded_salt
      end

      salt = Base64.strict_decode64(stored_salt) # Decode salt back to binary
      OpenSSL::PKCS5.pbkdf2_hmac('TypusSecureKey', salt, 100_000, 32, 'sha256') # Use SHA-256 explicitly
    end

    # Encrypt token using AES-256-CBC
    def encrypt_token(token)
      key = generate_encryption_key
      cipher = OpenSSL::Cipher.new('aes-256-cbc')
      cipher.encrypt
      iv = cipher.random_iv
      cipher.key = key
      encrypted = cipher.update(token) + cipher.final
      Base64.strict_encode64(iv + encrypted) # Store IV with the encrypted token
    end

    # Store encrypted token in SketchUp defaults
    def store_token(token)
      encrypted_token = encrypt_token(token)
      Sketchup.write_default('TypusConnector', 'Typustk', encrypted_token)
    end

    # Decrypt the stored token
    def decrypt_token
      encrypted_token = Sketchup.read_default('TypusConnector', 'Typustk', nil)
      return nil unless encrypted_token

      key = generate_encryption_key
      decoded = Base64.strict_decode64(encrypted_token)
      iv = decoded[0..15] # Extract IV
      encrypted_data = decoded[16..]

      decipher = OpenSSL::Cipher.new('aes-256-cbc')
      decipher.decrypt
      decipher.key = key
      decipher.iv = iv
      decipher.update(encrypted_data) + decipher.final
    rescue StandardError
      nil # Return nil if decryption fails
    end
  end
end
