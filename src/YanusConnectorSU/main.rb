# TypusConnectorSU/main.rb
# Main entry file for the TypusConnector plugin

module TypusConnector
  Sketchup.require "#{PLUGIN_DIR}/menu"
  Sketchup.require "#{PLUGIN_DIR}/color_profile"
  Sketchup.require "#{PLUGIN_DIR}/export_base64"
  Sketchup.require "#{PLUGIN_DIR}/web_connect"
  Sketchup.require "#{PLUGIN_DIR}/dialogs"

  require 'net/http'
  require 'uri'
  require 'openssl'
  require 'base64'
  require 'digest'
  require 'cgi'

  # License Check (Placeholder)
  def self.check_license
    # Add License Check Logic Here
    true # Placeholder return value
  end

  # Initialize Plugin
  def self.init
    return unless check_license

    # Load UI/Menu
    # Ensure the toolbar is only created once
    unless file_loaded?(__FILE__)
      Toolbar.new
      file_loaded(__FILE__)
    end
  end

  # Reload extension by running this method from the Ruby Console:
  def self.reload
    original_verbose = $VERBOSE
    $VERBOSE = nil
    pattern = File.join(__dir__, '**/*.rb')
    Dir.glob(pattern).each { |file|
      # Cannot use `Sketchup.load` because its an alias for `Sketchup.require`.
      load file
    }.size
  ensure
    $VERBOSE = original_verbose
  end

  # Run Initialization
  init

  class ExportProfile
    def initialize
      # puts 'ExportProfile initialized'
      @color_processor = nil
      @base64_encoder = nil
    end

    # Compile the json data
    def create_json(colormap, tempFile, token = '', secondImg = nil)
      image_data = if tempFile.start_with?("data:image")
                     tempFile.split(",")[1] # Remove data URI prefix
                   elsif File.exist?(tempFile)
                     @base64_encoder.export(tempFile)
                   else
                     ""
                   end

      scImgData = if secondImg
                    if secondImg.start_with?("data:image")
                      secondImg.split(",")[1]
                    elsif File.exist?(secondImg)
                      @base64_encoder.export(secondImg)
                    else
                      ""
                    end
                  end

      # Construct the data hash
      json_data = {
        ImageData: image_data,
        map: colormap,
        token: token
      }
      json_data[:InputImage] = scImgData if secondImg

      json_data # ✅ Return a hash, not JSON
    end



    # Function to create only the png image.
    def create_scan(org = false)
      return unless valid_model?
      @color_processor = TypusConnector::ColorProfile.new
      @base64_encoder = TypusConnector::ExportBase64.new

      Sketchup.active_model.start_operation('Create Scan', true)

      begin
        scene = nil
        scene = capture_scene('Typus_img_preview.png') if org

        # Replace materials with unique colors and get backup + map
        #color_map = @color_processor.getReady
        color_map = @color_processor.replace_colors
        #puts 'Material replacement done.'

        # Capture the color-mapped image
        image_path = capture_scene('Typus_export_preview.png', true)
        # puts "Image Path is: #{image_path}"

        # Restore original materials
        @color_processor.restore_colors

        Sketchup.active_model.commit_operation

        # Return the color map, image path, and scene if not nil
        [color_map, image_path, scene].compact
      rescue StandardError => e
        puts "Error during scan creation: #{e.message}"
        Sketchup.active_model.commit_operation
        nil
      end
    end

    private

    def valid_model?
      model = Sketchup.active_model
      unless model&.materials
        puts 'Invalid model: No active SketchUp model found.'
        return false
      end
      true
    end

    def valid_scene?(scene)
      if scene.nil? || !scene.is_a?(Sketchup::View)
        puts 'Invalid scene: Must be a valid SketchUp View.'
        return false
      end
      true
    end

    def prompt_save_location
      UI.savepanel('Save Exported Profile', Sketchup.active_model.path, 'export_profile.json')
    end

    def capture_scene(filename_prefix, mask = false)
      model       = Sketchup.active_model
      view        = model.active_view
      shadow_info = model.shadow_info
      ro          = model.rendering_options

      # Store originals, so we can restore them:
      original_display_shadows   = nil
      original_light             = nil
      original_dark              = nil
      original_use_sun           = nil
      original_bg_color          = nil
      original_sky_color         = nil
      original_draw_ground       = nil
      original_draw_horizon      = nil

      if mask
        # --- SHADOW SETTINGS ---
        original_display_shadows = shadow_info["DisplayShadows"]
        original_light           = shadow_info["Light"]
        original_dark            = shadow_info["Dark"]
        original_use_sun         = shadow_info["UseSunForAllShading"]

        shadow_info["DisplayShadows"]      = false
        shadow_info["UseSunForAllShading"] = true
        shadow_info["Light"]               = 0
        shadow_info["Dark"]                = 80

        # --- RENDERING OPTIONS ---
        original_bg_color     = ro["BackgroundColor"]
        original_sky_color    = ro["SkyColor"]
        original_draw_ground  = ro["DrawGround"]
        original_draw_horizon = ro["DrawHorizon"]

        ro["BackgroundColor"] = Sketchup::Color.new(0, 0, 0)
        ro["SkyColor"]        = Sketchup::Color.new(0, 0, 0)
        ro["DrawGround"]      = false
        ro["DrawHorizon"]     = false

        view.refresh
      end

      # --- CAPTURE TO IMAGE ---
      width     = view.vpwidth
      height    = view.vpheight
      timestamp = Time.now.strftime('%Y%m%d%H%M%S')
      filename  = "#{filename_prefix}_#{timestamp}.png"

      temp_dir  = File.join(Sketchup.temp_dir, 'Typus')
      Dir.mkdir(temp_dir) unless Dir.exist?(temp_dir)
      temp_path = File.join(temp_dir, filename)

      begin
        view.write_image(temp_path, width, height, 0.9)
      rescue => e
        puts "Error capturing scene: #{e.message}"
        return nil
      ensure
        if mask
          # --- RESTORE SHADOWS ---
          shadow_info["DisplayShadows"]      = original_display_shadows if !original_display_shadows.nil?
          shadow_info["UseSunForAllShading"] = original_use_sun         if !original_use_sun.nil?
          shadow_info["Light"]               = original_light           if !original_light.nil?
          shadow_info["Dark"]                = original_dark            if !original_dark.nil?

          # --- RESTORE RENDERING OPTIONS ---
          if original_bg_color
            ro["BackgroundColor"] = original_bg_color
          else
            ro.delete("BackgroundColor") if ro.respond_to?(:delete)
          end

          if original_sky_color
            ro["SkyColor"] = original_sky_color
          else
            ro.delete("SkyColor") if ro.respond_to?(:delete)
          end

          if original_draw_ground
            ro["DrawGround"] = original_draw_ground
          else
            ro.delete("DrawGround") if ro.respond_to?(:delete)
          end

          if original_draw_horizon
            ro["DrawHorizon"] = original_draw_horizon
          else
            ro.delete("DrawHorizon") if ro.respond_to?(:delete)
          end

          view.refresh
        end
      end

      File.exist?(temp_path) ? temp_path : nil
    end
  end
end
