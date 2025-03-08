# YanusConnectorSU/menu.rb
# Handles UI elements for the YanusConnector plugin

module YanusConnector
  class Toolbar
    def initialize
      add_tools
    end

    def add_tools
      # Create the toolbar
      toolbar = UI::Toolbar.new('Yanus Connector')

      # Define toolbar button
      cmd = UI::Command.new('Yanus Dialog') do
        dg = YanusDialogs.new
        dg.launch_yanus
      end
      cmd.tooltip = 'Open Yanus Dialog'
      cmd.large_icon = cmd.small_icon = File.join(__dir__, 'img', 'export_icon.png')
      cmd.status_bar_text = 'Open Yanus Dialog'

      # Add button to toolbar
      toolbar.add_item(cmd)

      # # Define toolbar button
      # cmd = UI::Command.new('Capture') do
      #   dg = YanusDialogs.new
      #   dg.launch_yanus(2)
      # end
      # cmd.tooltip = 'Start Capture'
      # cmd.large_icon = cmd.small_icon = File.join(__dir__, 'img', 'capture_icon.png')
      # cmd.status_bar_text = 'Start Capture'

      # # Add button to toolbar
      # #toolbar.add_item(cmd)

      # # Define toolbar button
      # cmd = UI::Command.new('Capture Regions') do
      #   dg = YanusDialogs.new
      #   dg.launch_yanus(1)
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
