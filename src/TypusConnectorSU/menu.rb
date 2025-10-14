# TypusConnectorSU/menu.rb
# Handles UI elements for the TypusConnector plugin

module TypusConnector
  class Toolbar
    def initialize
      add_tools
    end

    def add_tools
      # Create the toolbar
      toolbar = UI::Toolbar.new('Typus Connector')

      # Define toolbar button
      cmd = UI::Command.new('Typus Dialog') do
        dg = TypusDialogs.new
        dg.launch_Typus
      end
      cmd.tooltip = 'Open Typus Dialog'
      cmd.large_icon = cmd.small_icon = File.join(__dir__, 'img', 'logo_typus.png')
      cmd.status_bar_text = 'Open Typus Dialog'

      # Add button to toolbar
      toolbar.add_item(cmd)

      # # Define toolbar button
      # cmd = UI::Command.new('Capture') do
      #   dg = TypusDialogs.new
      #   dg.launch_Typus(2)
      # end
      # cmd.tooltip = 'Start Capture'
      # cmd.large_icon = cmd.small_icon = File.join(__dir__, 'img', 'capture_icon.png')
      # cmd.status_bar_text = 'Start Capture'

      # # Add button to toolbar
      # #toolbar.add_item(cmd)

      # # Define toolbar button
      # cmd = UI::Command.new('Capture Regions') do
      #   dg = TypusDialogs.new
      #   dg.launch_Typus(1)
      # end
      # cmd.tooltip = 'Start Capture Regions'
      # cmd.large_icon = cmd.small_icon = File.join(__dir__, 'img', 'regions_icon.png')
      # cmd.status_bar_text = 'Start Capture Regions'

      # # Add button to toolbar
      # #toolbar.add_item(cmd)
      toolbar.show
    end
  end
end
