# YanusConnectorSU/color_profile.rb
# Handles replacing materials with unique colors and restoring them

module YanusConnector
  class ColorProfile
    def initialize
      @model = Sketchup.active_model
      # Walk the entity tree once and cache all faces, groups, and component instances.
      @faces = []
      @groups = []
      @components = []
      @materials = []

      #puts "Total entities: #{@faces.size + @groups.size + @components.size}"
      #puts "Total materials: #{@materials.size}"

      @color_map = []
      @new_to_old_map = {}
      @used_colors = {}
    end

    def getReady
        @model = Sketchup.active_model
        @faces, @groups, @components, @materials = collect_entities(@model.entities)
    end

    # Replace materials with unique solid colors and return the color_map.
    # Processes materials in batches of 15.
    def replace_colors
      @model = Sketchup.active_model
      @faces, @groups, @components, @materials = collect_entities(@model.entities)

      return unless valid_model?

      begin
        # Process materials in batches of 15.
        @materials.each_slice(15) do |batch|
          process_materials(batch)
          #puts "Batch Processed!"
        end


        #puts @color_map
        # Replace the materials on faces, groups, and components.
        apply_solid_colors_to_faces
        #puts "Material Map Done."

        @color_map
      rescue StandardError => e
        puts "Error in replace_colors: #{e.message}"
        puts e.backtrace
        nil
      end
    end

    # Restore original materials using the provided new_to_old_map.
    def restore_colors
      return unless valid_model? && @new_to_old_map.is_a?(Hash)
      begin
        #@model.start_operation("Restore Colors", true)
        restore_original_materials
        cleanup_solid_materials
        #@model.commit_operation
      rescue StandardError => e
        puts "Error in restore_colors: #{e.message}"
        puts e.backtrace
      end
    end

    private

    # Validate that there is an active model with at least one material.
    def valid_model?
      if @model.nil? || @model.materials.count == 0
        puts "Invalid model: No active SketchUp model or no materials found."
        return false
      end
      true
    end

    # Walk through the entity tree once to collect faces, groups, and component instances.
    # Returns four arrays: [faces, groups, components, unique_materials]
    def collect_entities(entities)
      faces     = []
      groups    = []
      comps     = []
      materials = []

      entities.each do |entity|
        # If it's a face, collect it and its materials.
        if entity.is_a?(Sketchup::Face)
          faces << entity
          materials << entity.material if entity.material
          materials << entity.back_material if entity.back_material
        end

        # If it's a group, collect the group, its material override, and recurse into its entities.
        if entity.is_a?(Sketchup::Group)
          groups << entity
          materials << entity.material if entity.material  # Added: collect group override
          sub_faces, sub_groups, sub_comps, sub_materials = collect_entities(entity.entities)
          faces.concat(sub_faces)
          groups.concat(sub_groups)
          comps.concat(sub_comps)
          materials.concat(sub_materials)
        end

        # If it's a component instance (but not a group), collect it, its material override, and recurse into its definition.
        if entity.is_a?(Sketchup::ComponentInstance) && !entity.is_a?(Sketchup::Group)
          comps << entity
          materials << entity.material if entity.material  # Added: collect component override
          sub_faces, sub_groups, sub_comps, sub_materials = collect_entities(entity.definition.entities)
          faces.concat(sub_faces)
          groups.concat(sub_groups)
          comps.concat(sub_comps)
          materials.concat(sub_materials)
        end

        # Additionally, if the entity responds to entities and hasn't been handled above, recurse into it.
        if entity.respond_to?(:entities) && !(entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance))
          sub_faces, sub_groups, sub_comps, sub_materials = collect_entities(entity.entities)
          faces.concat(sub_faces)
          groups.concat(sub_groups)
          comps.concat(sub_comps)
          materials.concat(sub_materials)
        end
      end

      [faces, groups, comps, materials.uniq]
    end

    # Process the given materials (in the current batch) by creating new solid materials.
    def process_materials(materials, apply_changes = true)
      materials.each_with_index do |old_mat, index|
        next unless old_mat.valid?
        if apply_changes
          unique_color = generate_unique_color(index)
          @used_colors[unique_color.to_a] = true
          color_string = "(#{unique_color.red},#{unique_color.green},#{unique_color.blue})"
          new_mat_name = "#{old_mat.display_name}_solid_#{Time.now.to_i}_#{index}"
          new_mat = @model.materials.add(new_mat_name)
          next unless new_mat

          new_mat.color   = unique_color
          new_mat.texture = nil

          # Map the new material to the original material.
          @new_to_old_map[new_mat] = old_mat
          @color_map << { MaterialName: old_mat.display_name, Color: color_string }
        end
      end
      @model.active_view.invalidate
    end

    # Replace materials on cached faces, groups, and component instances with the new solid materials.
    def apply_solid_colors_to_faces
      return unless @new_to_old_map.is_a?(Hash) && !@new_to_old_map.empty?

      # Invert the map: original material => new solid material.
      old_to_new = {}
      @new_to_old_map.each { |new_mat, old_mat| old_to_new[old_mat] = new_mat }

      #puts "Applying solid colors to faces, groups, and components..."

      @faces.each do |face|
        if face.valid? && face.material && old_to_new.key?(face.material)
          face.material = old_to_new[face.material]
        end
        if face.valid? && face.back_material && old_to_new.key?(face.back_material)
          face.back_material = old_to_new[face.back_material]
        end
      end

      @groups.each do |group|
        if group.valid? && group.material && old_to_new.key?(group.material)
          group.material = old_to_new[group.material]
        end
      end

      @components.each do |component|
        if component.valid? && component.material && old_to_new.key?(component.material)
          component.material = old_to_new[component.material]
        end
      end
    end

    # Restore original materials on cached faces, groups, and component instances.
    def restore_original_materials
      return unless @new_to_old_map.is_a?(Hash) && !@new_to_old_map.empty?

      #puts "Restoring solid colors to faces, groups, and components..."

      @faces.each do |face|
        if face.valid? && face.material && @new_to_old_map.key?(face.material)
          face.material = @new_to_old_map[face.material]
        end
        if face.valid? && face.back_material && @new_to_old_map.key?(face.back_material)
          face.back_material = @new_to_old_map[face.back_material]
        end
      end

      @groups.each do |group|
        if group.valid? && group.material && @new_to_old_map.key?(group.material)
          group.material = @new_to_old_map[group.material]
        end
      end

      @components.each do |component|
        if component.valid? && component.material && @new_to_old_map.key?(component.material)
          component.material = @new_to_old_map[component.material]
        end
      end
    end

    # Remove any solid materials created during replacement.
    def cleanup_solid_materials
      solid_mats = Sketchup.active_model.materials.select { |mat| mat.display_name.include?("_solid_") }
      solid_mats.each { |solid_mat| Sketchup.active_model.materials.remove(solid_mat) }
    end

    def generate_unique_color(index)
      loop do
        # Generate a random color
        red   = rand(256)
        green = rand(256)
        blue  = rand(256)
        color = Sketchup::Color.new(red, green, blue, 255)

        # Ensure the color is not black or white
        unless is_black_or_white?([red, green, blue])
          # Check if the color is unique
          unless @used_colors[color.to_a]
            @used_colors[color.to_a] = true
            return color
          end
        end

        # Increment the index to ensure progress
        index += 1
      end
    rescue StandardError => e
      puts "Error in generate_unique_color: #{e.message}"
      puts e.backtrace
      Sketchup::Color.new(255, 255, 255)
    end

    # Helper method to check if a color is too close to black or white
    def is_black_or_white?(rgb)
      threshold = 10  # Tolerance for considering a color black or white
      (rgb[0] < threshold && rgb[1] < threshold && rgb[2] < threshold) || # Black
        (rgb[0] > 255 - threshold && rgb[1] > 255 - threshold && rgb[2] > 255 - threshold) # White
    end

  end
end
