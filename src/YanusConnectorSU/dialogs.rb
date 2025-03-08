# YanusConnectorSU/dialogs.rb
# Dialogs for the YanusConnector plugin

module YanusConnector
  class YanusDialogs
    # Initialize the YanusDialogs class
    def initialize
      @exp    = ExportProfile.new
      @server = nil
      @dialog = nil
      @logindialog = nil
      @token  = nil
      @server_timer = nil
      @tk = APIConnect.new
      @browser = 0
    end

    # Open the login dialog while restricting sketchup.
    def login_dialog
      # Create a new HTMLDialog instance for login.
      @logindialog = UI::HtmlDialog.new(
        dialog_title: "Yanus Login",
        preferences_key: "com.yanus_connector.login",
        scrollable: true,
        resizable: false,
        width: 1200,
        height: 800
      )

      # Set the login URL.
      #@logindialog.set_url('https://app.yanus.ai/version-test/auth?m=sketchup')
      @logindialog.set_url('https://app.yanus.ai/auth?m=sketchup')

      @logindialog.set_on_closed do |_action_context|
        stop_polling_server
      end

      # Start the TCP server on the main thread.
      start_polling_server(52572)

      @tk.set_token(nil)

      # Show the login dialog.
      @logindialog.show

    end

    def start_polling_server(port)
      if @server
        #puts "[INFO] Existing TCP server detected on port #{port}, reusing it."
      else
        #puts '[INFO] Starting TCP server...'
        begin
          @server = TCPServer.new('localhost', port)
          #puts "[INFO] TCP server started on port #{port}"
        rescue StandardError => e
          #puts "[ERROR] Failed to start TCP server: #{e.message}"
          stop_polling_server
          return
        end
      end

      # Start the timer to poll the TCP server if it's not already running.
      unless @server_timer
        @server_timer = UI.start_timer(0.1, true) do
          poll_server
        end
      else
        puts "[INFO] TCP server timer is already running."
      end
    end

    # Poll the server socket for incoming connections.
    def poll_server
      begin
        # Use IO.select with a zero timeout for a non-blocking check.
        ready = IO.select([@server], nil, nil, 0)
        if ready
          client = @server.accept_nonblock rescue @server.accept
          handle_client(client)
        end
      rescue IO::WaitReadable, Errno::EAGAIN
        # No connection available; do nothing.
      rescue StandardError => e
        puts "[ERROR] Polling server error: #{e.message}"
      end
    end

    # Handle an incoming client connection.
    def handle_client(client)
      request_line = client.gets
      if request_line
        method, full_path, _http_version = request_line.split
        if method == 'GET'
          begin
            uri    = URI.parse(full_path)
            params = uri.query ? URI.decode_www_form(uri.query).to_h : {}
            token  = params['token']
            link   = params['link'] || ''
            if token
              @token = token
              #puts "[INFO] Token captured: #{@token}"
              process_token(@token)
              @login_active = false  # Token captured; stop further polling
              close_login_dialog  # Ensure the dialog is closed
              stop_polling_server
            else
              puts '[WARN] No token found in the request.'
            end

            response = "HTTP/1.1 302 Found\r\n" +
                       "Location: #{link.empty? ? 'about:blank' : link}\r\n" +
                       "Content-Length: 0\r\n" +
                       "\r\n"
            client.write(response)
          rescue StandardError => e
            puts "[ERROR] Exception handling request: #{e.message}"
            response = "HTTP/1.1 500 Internal Server Error\r\n" +
                       "Content-Type: text/plain\r\n" +
                       "Content-Length: 0\r\n" +
                       "\r\n"
            client.write(response)
          end
        else
          client.write("HTTP/1.1 405 Method Not Allowed\r\n\r\n")
        end
      end
      client.close
    end

    # Process the captured token.
    def process_token(token_value)
      #puts "Processing token: #{token_value}"
      @tk.set_token(token_value)

      close_login_dialog
      yanus_dialog
    rescue StandardError => e
      puts "[ERROR] Exception processing token: #{e.message}"
    end

    # Update the dialog UI after token capture.
    def close_login_dialog
      @logindialog.close
    end

    # Stop polling and close the TCP server.
    def stop_polling_server
      UI.stop_timer(@server_timer) if @server_timer
      @server_timer = nil
      if @server
        #puts '[INFO] Shutting down TCP server...'
        @server.close rescue nil
        @server = nil
      else
        #puts '[WARN] No active TCP server found.'
      end
    end

    def launch_yanus(state = nil)
      token = @tk.get_token
      if token
        #puts "Token found"
        yanus_dialog
        if state == 1
          capture_regions
        elsif state == 2
          capture
        end
      else
        #puts "Token not found"
        login_dialog
      end

    end

    # Method to create the main Yanus Export dialog
    def yanus_dialog

      @dialog = UI::HtmlDialog.new(
          dialog_title: 'Yanus Connector',
          preferences_key: 'com.yanus_connector.export',
          scrollable: true,
          resizable: true,
          width: 540,
          height: 430,
          style: UI::HtmlDialog::STYLE_DIALOG
        )

        @dialog.set_html(create_html)

        @dialog.add_action_callback('capture') do |_action_context|
          capture
        end


        @dialog.add_action_callback('onload') do |_action_context|
          tok = @tk.get_token
          if tok.nil?
            @dialog.execute_script("updateUser(null)");
          else
            @dialog.execute_script("updateUser('Login')");
          end
        end

        @dialog.add_action_callback('captureRegions') do |_action_context|
          capture_regions
        end


        @dialog.add_action_callback('login') do |_action_context|
          login_dialog
        end

        @dialog.add_action_callback('logout') do |_action_context|
          @dialog.execute_script("updateUser(null)");
          #puts "Logging out..."
          @tk.set_token(nil)
          @dialog.close
          login_dialog
        end

        @dialog.set_on_closed do |_action_context|
          cleanup_temp
        end

        @dialog.set_size(540, 460)
        @dialog.show


    end

    def capture
      UI.start_timer(0.3, false) do
        @dialog.execute_script("addLoading('Capture in progress...')")
        # Create a scan
        scan = @exp.create_scan(true)

        if scan
          # Check if images exist
          if !File.exist?(scan[1]) || !File.exist?(scan[2])
            @dialog.execute_script("addLoading('Capture failed.')")
          else
            tok = @tk.get_token

            # Step 1: Resize the first image (scan[1])
            resize_image_dialog(scan[1]) do |base64_data_1|

              # Step 2: Resize the second image (scan[2])
              resize_image_dialog(scan[2]) do |base64_data_2|

                # Step 3: Create JSON after both images are resized
                json_data = @exp.create_json(scan[0], base64_data_1, tok, base64_data_2)

                json_data = JSON.generate(json_data)

                # Save for dubgging.
                temp_yanus_dir = File.join(Sketchup.temp_dir, "Yanus")
                FileUtils.mkdir_p(temp_yanus_dir) unless Dir.exist?(temp_yanus_dir)
                timestamp = Time.now.strftime("%Y%m%d%H%M%S")
                file_name = "JSON-Data-#{timestamp}.json"
                file_path = File.join(temp_yanus_dir, file_name)
                File.open(file_path, 'w') { |file| file.write(json_data) }

                # Update UI after processing both images
                @dialog.execute_script("updateScanPreview('#{scan[1]}')")
                @dialog.execute_script("addLoading('Exporting to Yanus...')")

                # Add 4 second delay before exporting to API
                UI.start_timer(2, false) do

                  # Step 4: Export to API
                  result = @tk.export_to_api(json_data) do |response|
                    begin
                      if response && !response.empty?
                        parsed_response = response.is_a?(String) ? JSON.parse(response) : response
                        message = parsed_response.dig('response', 'message')
                        link = parsed_response.dig('response', 'link')

                        if message == "Unauthorized"
                          login_dialog
                          @dialog.close
                        elsif link
                          @dialog.execute_script("updateScanPreview('#{scan[2]}')")
                          if @browser == 0
                            UI.openURL(link)
                            @browser = 1
                          end
                          @dialog.execute_script("add_web_link()")
                        end
                      else
                        puts "[YANUS ERROR] No Response from API."
                      end
                    rescue JSON::ParserError => e
                      puts "[YANUS ERROR] JSON Parsing Error: #{e.message}"
                    end
                  end
                end
              end # End second image resize
            end # End first image resize
          end
        end
      end
    end

    def capture_regions
      UI.start_timer(0.3, false) do
        @dialog.execute_script("addLoading('Capture in progress...')")
        # Create a scan
        scan = @exp.create_scan

        if scan
          # Check if image exists
          if !File.exist?(scan[1])
            @dialog.execute_script("addLoading('Capture failed.')")
          else
            tok = @tk.get_token

            @dialog.execute_script("updateScanPreview('#{scan[1]}')")

            # Resize and process the image before creating JSON
            resize_image_dialog(scan[1]) do |base64_data|
              json_data = @exp.create_json(scan[0], base64_data, tok)  # Create JSON after resizing

              json_data = JSON.generate(json_data)

              # Save for dubgging.
              temp_yanus_dir = File.join(Sketchup.temp_dir, "Yanus")
              FileUtils.mkdir_p(temp_yanus_dir) unless Dir.exist?(temp_yanus_dir)
              timestamp = Time.now.strftime("%Y%m%d%H%M%S")
              file_name = "JSON-Data-#{timestamp}.json"
              file_path = File.join(temp_yanus_dir, file_name)
              File.open(file_path, 'w') { |file| file.write(json_data) }

              @dialog.execute_script("addLoading('Exporting to Yanus...')")

              # Add 4 second delay before exporting to API
              UI.start_timer(2, false) do

                # Export to API
                result = @tk.export_to_api(json_data) do |response|
                  begin
                    #puts response
                    parsed_response = response.is_a?(String) ? JSON.parse(response) : response
                    message = parsed_response.dig('response', 'message')
                    link = parsed_response.dig('response', 'link')

                    if message == "Unauthorized"
                      login_dialog
                      @dialog.close
                    elsif link
                      if @browser == 0
                        UI.openURL(link)
                        @browser = 1
                      end
                      @dialog.execute_script("add_web_link()")
                    end
                  rescue JSON::ParserError => e
                    puts "[YANUS ERROR] JSON Parsing Error: #{e.message}"
                  end
                end
              end
            end # End of resize_image_dialog block
          end
        end
      end
    end

    # Cleanup Temporary Files
    def cleanup_temp
      temp_dir = File.join(Sketchup.temp_dir, 'Yanus')

      if Dir.exist?(temp_dir)
        begin
          Dir.foreach(temp_dir) do |file|
            file_path = File.join(temp_dir, file)
            File.delete(file_path) if File.file?(file_path)
          end
          Dir.rmdir(temp_dir) # Remove the directory after clearing its contents
        rescue StandardError => e
          puts "Error cleaning up temporary directory: #{e.message}"
        end
      else
        #puts "Temporary directory '#{temp_dir}' does not exist."
      end
    end

    # Method to create the HTML content for the dialog
    def create_html
      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>Yanus Export</title>
          <style>
            body {
              font-family: Arial, sans-serif;
              margin: 0;
              padding: 0;
              background-color: #000;
              color: #fff;
              text-align: center;
            }
            .top-bar {
              display: flex;
              align-items: center;
              justify-content: space-between;
              padding: 10px 20px;
              background-color: #000;
              border-bottom: 1px solid #515151;
            }
            .logo {
              font-weight: bold;
              padding-top: 5px;
            }
            .logo img {
              height: 40px;
              width: 40px;
            }
            .login-icon {
              cursor: pointer;
              font-size: 1.2em;
              padding: 0px 6px;
            }
            .login-icon img {
              height: 30px;
            }
            /* New center status area in top bar */
            #topbar-status {
              flex: 1;
              display: flex;
              justify-content: center;
              align-items: center;
            }
            .container {
              max-width: 1000px;
              margin: 20px 20px;
            }
            .buttons {
              display: flex;
              justify-content: space-between;
              margin: 20px 0;
              gap: 20px;
            }
            .buttons button {
              flex: 1;
              padding: 10px;
              background-color: #222;
              color: #fff;
              border: 1px solid #444;
              cursor: pointer;
              font-size: 1em;
            }
            .buttons button:hover {
              background-color: #333;
            }

            button {
              background-color: #222;
              color: #fff;
              border: 1px solid #444;
              border-radius: 0px;
              padding: 8px 16px;
            }

            button:hover {
              background-color: #333;
            }

            .image-container {
              width: 100%;
              height: 241.95px;
              background-color: #1a1a1a;
              border: 1px solid #444;
              position: relative;
              display: flex;
              align-items: center;
              justify-content: center;
              overflow: hidden;
            }
            .image-container img {
              width: 100%;
              height: 100%;
              object-fit: cover;
            }
            /* Scrollbar styles */
            ::-webkit-scrollbar-track {
              background: #FFF;
            }
            ::-webkit-scrollbar-thumb {
              background: #1a1a1a;
            }
            ::-webkit-scrollbar-thumb:hover {
              background: #444;
            }
            ::-webkit-scrollbar {
              width: 8px;
              height: 8px;
            }
            /* Spinner styles */
            .spinner {
              width: 20px;
              height: 20px;
              background-color: #fff;
              margin-right: 8px;
              animation: spin 1s linear infinite;
            }
            @keyframes spin {
              0% { transform: rotate(0deg); }
              100% { transform: rotate(360deg); }
            }
            /* Refine button style in the topbar */
            #topbar-status button {
              padding: 5px 10px;
              background-color: #222;
              color: #fff;
              border: 1px solid #fff;
              cursor: pointer;
            }
            #topbar-status button:hover {
              background-color: #333;
            }

            /* General styles for the dropdown */
            #user-dropdown {
              position: absolute;
              background-color: #000;
              min-width: 120px;
              right: 29px;
              box-shadow: 0px 8px 16px 0px rgba(0,0,0,0.2);
              z-index: 1;
              top: 60px;
            }

            #user-dropdown a {
              color: white;
              padding: 8px 12px;
              font-size: 12px;
              text-decoration: none;
              border: 1px solid #7c7c7c;
              display: block;
            }

            #user-dropdown a:hover {
              background-color: #333;
            }

            /* Triangle at the top-right corner */
            #user-dropdown::before {
              content: '';
              position: absolute;
              top: -9px;
              right: 3px;
              border-left: 9px solid transparent;
              border-right: 9px solid transparent;
              border-bottom: 9px solid #7c7c7c;
            }

            #user-dropdown::after {
              content: '';
              position: absolute;
              top: -6px; /* Adjust so it sits inside the border */
              right: 5px; /* Align with triangle */
              border-left: 7px solid transparent;
              border-right: 7px solid transparent;
              border-bottom: 7px solid #000; /* Match dropdown background */
            }

            #logout-dialog {
              position: fixed;
              top: 50%;
              left: 50%;
              transform: translate(-50%, -50%);
              background-color: rgb(0, 0, 0);
              border: 1px solid rgb(124, 124, 124);
              color: white;
              padding: 20px;
              width: 250px;
              text-align: center;
              box-shadow: rgb(0 0 0 / 50%) 0px 4px 10px;
              z-index: 1000;
            }
          </style>
        </head>
        <body>
          <div class="top-bar">
            <div class="logo">
              <img src="#{File.join(__dir__, 'img', 'logo_yanus2.png')}" alt="YanusLogo">
            </div>
            <div id="topbar-status">
              <!-- The spinner is added directly here and hidden by default -->
              <div id="lottie-spinner" style="width:50px; height:50px; display:none;"></div>
              <!-- The loading message is added here, hidden by default -->
              <span id="loading-message" style="margin-left:10px; display:none;"></span>
            </div>
            <div class="login-icon" title="Profile">
              <img src="#{File.join(__dir__, 'img', 'user-square.png')}" alt="User">
            </div>
          </div>
          <div class="container">
            <div class="buttons">
              <button id="captureRegions" onclick="captureRegions()">Capture Regions</button>
              <button id="upload" onclick="capture()">Capture</button>
            </div>
            <div class="image-container" id="scanPreview">
              <!-- Scanned Image will appear here -->
            </div>
          </div>
          <script src="https://cdnjs.cloudflare.com/ajax/libs/lottie-web/5.9.6/lottie.min.js"></script>
          <script>

            document.addEventListener('DOMContentLoaded', function() {
              var scanPreview = document.getElementById('scanPreview');
              if (!scanPreview.querySelector('img')) {
                var tempText = document.createElement('div');
                tempText.textContent = '[Preview Image]';
                tempText.style.color = '#888';
                tempText.style.position = 'absolute';
                tempText.style.top = '50%';
                tempText.style.left = '50%';
                tempText.style.transform = 'translate(-50%, -50%)';
                scanPreview.appendChild(tempText);
              }

              var lottieContainer = document.getElementById('lottie-spinner');
              if (lottieContainer) {
                lottie.loadAnimation({
                  container: lottieContainer,
                  renderer: 'svg',
                  loop: true,
                  autoplay: true,
                  path: '#{File.join(__dir__, "img", "spiner.json")}' // Adjust path as needed
                });
              }

              window.sketchup.onload();
            });

            function captureRegions() {
              window.sketchup.captureRegions();
            }

            function capture() {
              window.sketchup.capture();
            }

            function updateUser(user) {
              //console.log('User:', user);
              createUserDropdown(user);
            }

            function createUserDropdown(user) {
                var loginIcon = document.querySelector('.login-icon');

                if (!loginIcon) return;

                // Remove existing dropdown if it exists
                var existingDropdown = document.getElementById('user-dropdown');
                if (existingDropdown) {
                    existingDropdown.remove();
                }

                // Create new dropdown
                var dropdown = document.createElement('div');
                dropdown.id = 'user-dropdown';
                dropdown.className = 'dropdown-content';

                dropdown.style.display = 'none'; // Hide dropdown by default

                if (user === 'Login') {
                    var logoutLink = document.createElement('a');
                    logoutLink.textContent = 'Logout';
                    logoutLink.onclick = function (event) {
                        event.preventDefault();
                        dropdown.style.display = 'none';
                        showLogoutDialog()
                    };
                    dropdown.appendChild(logoutLink);
                } else {
                    var loginLink = document.createElement('a');
                    loginLink.textContent = 'Login';
                    loginLink.onclick = function (event) {
                        event.preventDefault();
                        window.sketchup.login();
                        dropdown.style.display = 'none'; // Close the dropdown after login
                    };
                    dropdown.appendChild(loginLink);
                }

                // Append the new dropdown to login icon
                loginIcon.appendChild(dropdown);

                // Click event to toggle dropdown visibility
                loginIcon.onclick = function (event) {
                    event.preventDefault();

                    // Toggle dropdown visibility
                    if (dropdown.style.display === 'block') {
                        dropdown.style.display = 'none';
                    } else {
                        dropdown.style.display = 'block';

                        // Close dropdown when clicking outside
                        setTimeout(() => {
                            document.addEventListener('click', function closeDropdown(event) {
                                if (!loginIcon.contains(event.target)) {
                                    dropdown.style.display = 'none';
                                    document.removeEventListener('click', closeDropdown); // Remove event listener after execution
                                }
                            });
                        }, 0);
                    }
                };
            }

            function showLogoutDialog() {
              // Remove existing dialog if any
              var existingDialog = document.getElementById('logout-dialog');
              if (existingDialog) {
                  existingDialog.remove();
              }

              // Create the dialog container
              var dialog = document.createElement('div');
              dialog.id = 'logout-dialog';

              // Close button (X)
              var closeButton = document.createElement('span');
              closeButton.innerHTML = '&times;'; // HTML entity for "×"
              closeButton.style.position = 'absolute';
              closeButton.style.top = '5px';
              closeButton.style.right = '10px';
              closeButton.style.cursor = 'pointer';
              closeButton.style.fontSize = '18px';
              closeButton.style.color = '#7c7c7c';
              closeButton.onclick = function () {
                  dialog.remove(); // Close the dialog
              };

              // Dialog text
              var message = document.createElement('p');
              message.textContent = 'Are you sure you want to logout?';
              message.style.marginBottom = '20px';

              // Buttons container
              var buttonsContainer = document.createElement('div');
              buttonsContainer.style.display = 'flex';
              buttonsContainer.style.justifyContent = 'space-between';

              // "Yes" Button
              var yesButton = document.createElement('button');
              yesButton.textContent = 'Yes';
              yesButton.style.cursor = 'pointer';
              yesButton.style.flex = '1';
              yesButton.style.marginRight = '10px';
              yesButton.onclick = function () {
                  window.sketchup.logout(); // Call SketchUp logout function
                  dialog.remove(); // Close the dialog
              };

              // "No" Button
              var noButton = document.createElement('button');
              noButton.textContent = 'No';
              noButton.style.cursor = 'pointer';
              noButton.style.flex = '1';
              noButton.onclick = function () {
                  dialog.remove(); // Close the dialog
              };

              // Append buttons to container
              buttonsContainer.appendChild(yesButton);
              buttonsContainer.appendChild(noButton);

              // Append everything to dialog
              dialog.appendChild(closeButton);
              dialog.appendChild(message);
              dialog.appendChild(buttonsContainer);

              // Append the dialog to the body
              document.body.appendChild(dialog);
          }



            function updateScanPreview(imageUrl) {
              var scanPreview = document.getElementById('scanPreview');
              scanPreview.innerHTML = ''; // Clear existing image
              scanPreview.style.height = 'auto'; // Reset height

              var img = document.createElement('img');
              img.src = imageUrl;

              scanPreview.appendChild(img);
            }

            function addLoading(message) {
              var topbarStatus = document.getElementById('topbar-status');
              if (!topbarStatus) return; // Ensure the element exists

              // If there are elements like exportedText and refineButton that need to be removed, do so.
              var exportedText = document.getElementById('exported-text');
              var refineButton = document.getElementById('refine-button');
              if (exportedText && refineButton) {
                exportedText.remove();
                refineButton.remove();
              }

              // Get the spinner container which is now added directly in the HTML
              var lottieContainer = document.getElementById('lottie-spinner');
              if (lottieContainer) {
                // Unhide the spinner (it should already have the animation loaded)
                lottieContainer.style.display = 'block';
              }

              // Get the message span element and update its text and make it visible
              var messageSpan = document.getElementById('loading-message');
              if (messageSpan) {
                messageSpan.style.display = 'inline';
                messageSpan.textContent = message;
              }
            }


            // Function to update the top bar: remove loading spinner,
            // display "Exported!" and add a "Refine" button linking to the provided URL.
            function add_web_link() {
              var topbarStatus = document.getElementById('topbar-status');

              // Hide the spinner if it exists.
              var spinner = document.getElementById('lottie-spinner');
              if (spinner) {
                spinner.style.display = 'none';
              }

              // Hide the original loading message element, if it exists.
              var loadingMessage = document.getElementById('loading-message');
              if (loadingMessage) {
                loadingMessage.style.display = 'none';
              }

              // Try to find the success text element; create it if it doesn't exist.
              var successText = document.getElementById('success-text');
              if (!successText) {
                successText = document.createElement('span');
                successText.id = 'success-text';
                topbarStatus.appendChild(successText);
              }

              // Set the success message and make sure it's visible.
              successText.textContent = 'Success!';
              successText.style.opacity = '1';
              successText.style.display = 'inline';

              // Fade out the success message after 5 seconds.
              setTimeout(() => {
                successText.style.transition = 'opacity 1s ease-out';
                successText.style.opacity = '0';
                // After the fade-out, simply hide the element.
                setTimeout(() => {
                  successText.style.display = 'none';
                }, 1000); // Wait for fade-out transition to complete
              }, 5000);
            }



          </script>
        </body>
        </html>
      HTML
    end

    def resize_image_dialog(temp_path, &callback)
      return unless File.exist?(temp_path)

      #puts "Trying to create dialog!"

      @dlg = UI::HtmlDialog.new(
        dialog_title: "Generating Scan",
        width: 500,
        height: 135,
        scrollable: false,
        style: UI::HtmlDialog::STYLE_DIALOG
      )

      html = <<-HTML
        <html>
        <head>
        <style>
          body { font-family: Arial, sans-serif; text-align: center; padding: 20px; background: black; color: white; }

          .loading-bar {
            width: 400px;
            height: 8px;
            background: white;
            overflow: hidden;
            margin: auto;
            position: relative;
          }

          .progress {
            width: 50px;
            height: 100%;
            background: linear-gradient(to right, black, transparent);
            position: absolute;
            animation: progressAnim 1.5s linear infinite;
          }

          @keyframes progressAnim {
            0% { left: -50px; }
            100% { left: 400px; }
          }
        </style>
        </head>
        <body>
          <h4>Processing Image...</h4>
          <div class="loading-bar">
            <div class="progress"></div>
          </div>
          <script>
            let img = new Image();
            img.onload = function() {
              let new_width = img.width;
              let new_height = img.height;

              // Step 1: Check if the total pixels exceed 990,000
              let total_pixels = new_width * new_height;
              if (total_pixels > 990000) {
                let scale_factor = Math.sqrt(990000 / total_pixels); // Calculate scaling factor
                new_width = Math.round(new_width * scale_factor);
                new_height = Math.round(new_height * scale_factor);
              }

              //console.log("Original Size:", img.width, "x", img.height);
              //console.log("Resized Size:", new_width, "x", new_height, "Total Pixels:", new_width * new_height);

              let canvas = document.createElement("canvas");
              let ctx = canvas.getContext("2d");

              // Set canvas dimensions to the resized values
              canvas.width = new_width;
              canvas.height = new_height;

              // Draw the resized image
              ctx.drawImage(img, 0, 0, new_width, new_height);

              // Convert to Base64 and send to SketchUp
              let resizedData = canvas.toDataURL("image/png");
              //console.log("Resized Image Data:", resizedData.substring(0, 50)); // Debugging
              sketchup.returnBase64(resizedData);
            };

            // Force reload to prevent caching issues
            img.src = "file:///" + "#{temp_path}" + "?t=" + new Date().getTime();
          </script>
        </body>
        </html>
      HTML

      @dlg.set_html(html)

      # Callback to receive the resized image from JavaScript
      @dlg.add_action_callback("returnBase64") { |_context, base64_data|
        @dlg.close
        callback.call(base64_data) if callback
      }

      # Set position
      @dlg.set_position(400, 400)

      @dlg.show
    end

  end
end
