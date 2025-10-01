# TypusConnectorSU.rb

# Project for Han Cheol Yi
# Date: 29th Jan, 2025

# Loader file for the TypusConnector plugin

# Updated to Version 1.0.1 1/13/2025
# Added Login Enhancements

# Updated to Version 1.1.0 1/14/2025
# Enhanced Color Engine
# Updated the Login Enhancements

# Updated to Version 1.1.5 3/4/2025
# Fixed API Connection Issue
# Updated the Color Engine

# Updated to Version 2.0.0 9/23/2025
# Rebranding to Typus

require 'sketchup.rb'
require 'extensions.rb'

module TypusConnector
  # Define the extension
  unless file_loaded?(__FILE__)
    PLUGIN_NAME = "Typus Connector"
    PLUGIN_VERSION = "2.0.0"

    path = __FILE__
    path.force_encoding("UTF-8") if path.respond_to?(:force_encoding)

    FILE_BASENAME = File.basename(path, ".*")
    PLUGIN_DIR = File.join(File.dirname(path), FILE_BASENAME)

    extension = SketchupExtension.new(PLUGIN_NAME, "TypusConnectorSU/main")
    extension.description = "Connects Typus to Sketchup."
    extension.version     = PLUGIN_VERSION
    extension.copyright   = "©2025 Typus"
    extension.creator     = "Typus Group"

    Sketchup.register_extension(extension, true)
    file_loaded(__FILE__)
  end
end
