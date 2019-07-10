require 'sketchup'

@configKeys = ["cutDiamiter",\
               "cutDepth",\
               "decimalPlaces",\
               "minimumResolution",\
               "units",\
               "closeGaps",\
               "scriptMode",\
               "orientation",\
               "debug"]
@config = {}

# Reset config to default values.
def clearConfig()
  @config.each do |key, value|
    result = Sketchup.write_default('dla_wafer_rb', key,  nil)
    puts("clear: #{key} #{result}")
  end
end

# Save entries in @config to persistent storage.
def saveConfig()
  @config.each do |key, value|
    result = Sketchup.write_default('dla_wafer_rb', key,  value)
    puts("save: #{key}, #{value}, #{result}")
  end
end

# Load configuration from persistent storage into @config hashmap.
def loadConfig()
  defaultValue = {\
                  "cutDiamiter" => "1.0",\
                  "scriptMode" => "Single",\
                  "cutDepth" => "0.5",\
                  "closeGaps" => "0.0",\
                  "orientation" => "Stacked",\
                  "decimalPlaces" => "3",\
                  "minimumResolution" => "0.001",\
                  "units" => "mm",\
                  "debug" => "false"}

  @configKeys.each do | key |
    value = Sketchup.read_default('dla_wafer_rb', key)
    puts("load: #{key}, #{value}")
    if value == nil
      value = defaultValue[key]
    end
    @config[key] = value
  end
end

# Set values in the @config hashmap.
def menu()
  configDescriptions = {\
                        "cutDiamiter" => "Diamiter of cutter? (mm)",\
                        "scriptMode" => "Mode of operation",\
                        "cutDepth" => "Depth of cut? (mm)",\
                        "closeGaps" => "Close gaps in looped paths (mm)",\
                        "orientation" => "Preview orientation",\
                        "decimalPlaces" => "Gcode decimal places",\
                        "minimumResolution" => "Minimum movment size",\
                        "units" => "Units to use in Gcode file",\
                        "debug" => "Enable debug pannel"}
  sizes = "0.0|"\
          "0.01|0.02|0.03|0.04|0.05|0.06|0.07|0.08|0.09|"\
          "0.1|0.2|0.3|0.4|0.5|0.6|0.7|0.8|0.9|"\
          "1.0|1.1|1.2|1.3|1.4|1.5|1.6|1.7|1.8|1.9|"\
          "2.0|2.1|2.2|2.3|2.4|2.5|2.6|2.7|2.8|2.9|"\
          "3.0|3.175|3.5|4.0|4.5|5.0|6.0|6.35|7.0|8.0|9.0|9.525|10.0|"\
          "12.0|12.7|14.0|15.0|16.0|18.0|20.0|"\
          "25.0|30.0|35.0|40.0|50.0|100.0"
  menuOptions = {\
                 "cutDiamiter" => sizes,\
                 "scriptMode" => "Single|Repeated single|Contour",\
                 "cutDepth" => sizes,\
                 "closeGaps" => sizes,\
                 "orientation" => "Spread|Stacked",\
                 "decimalPlaces" => "0|1|2|3|4",\
                 "minimumResolution" => "0.001|0.01|0.1|1|10",\
                 "units" => "mm|inch",\
                 "debug" => "true|false"}
  descriptions = []
  values = []
  options = []
  @configKeys.each do | key |
    descriptions.push(configDescriptions[key])
    values.push(@config[key])
    options.push(menuOptions[key])
  end
  input = UI.inputbox descriptions, values, options, "Gcode options."

  if input
    for x in 0..(input.size - 1)
      key = @configKeys[x]
      @config[key] = input[x]
      puts("menu: #{key} #{input[x]}")
    end
    return true
  end
end 

# Round floats down to a sane number of decimal places.
def roundToPlaces(value, places, units)
  if units == "mm"
    value = value.to_mm
  end
  places = places.to_i
  returnVal = ((value * (10 ** places)).round.to_f / (10 ** places))
  return returnVal
end


# Add a menu item to launch our plugin.
UI.menu("PlugIns").add_item("Wafer") {
  Sketchup.set_status_text "Calculating Gcode", SB_VCB_VALUE

  loadConfig()
  if menu()
    saveConfig()

    if @config["debug"] != "false"
      # Show the Ruby Console at startup so we can
      # see any programming errors we may make.
      Sketchup.send_action "showRubyPanel:"
    end

    gcodeFile = UI.savepanel "Save Gcode File", "c:\\", "default.nc"
    puts("Writing to #{gcodeFile}")
    if gcodeFile
      new_wafer = Wafer.new
      if new_wafer.find_bounds == nil
        Sketchup.set_status_text "", SB_VCB_VALUE
        puts("No geometry selected")
        UI.messagebox("No geometry selected", type = MB_OK)
        return
      else
        new_wafer.out_file = gcodeFile
        new_wafer.preview_layout = @config["orientation"]
        new_wafer.height = 0
        new_wafer.cut_depth = @config["cutDepth"]
        new_wafer.mill_diamiter = (@config["cutDiamiter"].to_f)/100
        new_wafer.create_layers
        new_wafer.decimalPlaces = @config["decimalPlaces"]
        new_wafer.minimumResolution = @config["minimumResolution"].to_f
        new_wafer.units = @config["units"]
        new_wafer.closeGaps = @config["closeGaps"]

        new_wafer.header  

        if @config["scriptMode"] == "Single"
          new_wafer.single
        elsif @config["scriptMode"] == "Repeated single"
          new_wafer.repeated_single
        elsif @config["scriptMode"] == "Contour"
          new_wafer.contour
        end

        new_wafer.footer
      end #if new_wafer.find_bounds == nil
    end #if @gcodeFile
  end #if menu()

  #clearConfig()

  Sketchup.set_status_text "", SB_VCB_VALUE
}


class Wafer

  def height=(z)
    @height = z
  end
  def height
    @height
  end
  def mill_diamiter=(d)
    @mill_diamiter = d
  end
  def mill_diamiter
    @mill_diamiter
  end
  def decimalPlaces=(dp)
    @decimalPlaces = dp
  end
  def decimalPlaces
    @decimalPlaces
  end
  def minimumResolution=(mr)
    @minimumResolution = mr
  end
  def minimumResolution
    @minimumResolution
  end
  def units=(units)
    @units = units
  end
  def units
    @units
  end
  def out_file=(o)
    @out_file = o
  end
  def out_file
    @out_file 
  end
  def closeGaps=(cg)
    @closeGaps = cg.to_f
  end

  attr_accessor :preview_layout
  attr_accessor :cut_depth

  def writeGcode(line, flush=false)
    if @outputfile == nil
      puts("Opening file: #{@out_file}")
      @outputfile = File.new( @out_file , "w" )
      @gcodeContent = String.new("")
    end
    @gcodeContent.concat(line).concat("\n")

    if flush or @gcodeContent.length > 10000
      @outputfile.puts(@gcodeContent)
    end
  end

  # Populate output file with gcode header.
  def header
    @pos_x = 0
    @pos_y = 0
    @pos_z = @corner_rbt.z + 1 

    if @units == "mm"
      writeGcode("G21 ( Unit of measure: mm )")
    else
      writeGcode("G20 ( Unit of measure: inches )")
    end
    writeGcode("G90 ( Absolute programming )")
    writeGcode("M03 ( Spindle on [clockwise] )")
    writeGcode("G00 Z#{roundToPlaces(@pos_z, @decimalPlaces, @units)} "\
               "( Rapid positioning to highest point +1 )")
  end #header

  # Populate output file with gcode footer.
  def footer
    @pos_z = @corner_rbt.z + 1

    writeGcode("")
    writeGcode("G00 Z#{roundToPlaces(@pos_z, @decimalPlaces, @units)} "\
                     "( Rapid positioning to highest point +1 )")
    writeGcode("M05 ( Spindle stop )")
    writeGcode("M02 ( End of program )")

    writeGcode("")
    writeGcode("( end )", true)
    
    @outputfile.close()
  end #footer

  def create_layers
    # here we create some separate layers to display our router paths on.
    model = Sketchup.active_model
    layers = model.layers
    # happily it does not seem to matter if we try to create a layer that already exists.
    outline_layer = layers.add "outline"
    path_layer = layers.add "path"
    test_layer = layers.add "test"
  end #create_layers

  def single
    @height = @corner_lfb.z
    puts(trace_outline)
    puts(isolate_part)
    puts(router_path)
    puts(draw_part)

    return
  end #def Single

  def repeated_single
    puts(trace_outline)
    puts(isolate_part)
    puts(router_path)

    @height = @corner_rbt.z
    thickness = (@corner_rbt.z - @corner_lfb.z).to_mm

    while thickness > 0
      thickness -= @cut_depth.to_f
      @height -= @cut_depth.to_f.mm

      puts(draw_part)
    end
  
  end #def repeated_single
  
  def contour
    @height = @corner_rbt.z
    thickness = (@corner_rbt.z - @corner_lfb.z).to_mm
    while thickness >= 0
      thickness -= @cut_depth.to_f
      @height -= @cut_depth.to_f.mm
      # make sure we are not cutting below the bottom of the selected object.
      if @height < @corner_lfb.z
        #puts("h#{@height.mm}  c#{@corner_lfb.z}")
        @height = @corner_lfb.z.to_mm
      end #if
      puts(trace_outline)
      puts(isolate_part)
      puts(router_path)
      puts(draw_part)
    end
  
  end #contor

  def find_bounds
    # Get "handles" to our model and the Entities collection it contains.
    model = Sketchup.active_model
    selection = model.selection

    if selection == nil or selection[0] == nil
      return
    end

    # boundry of whole model
    @model_lfb = model.bounds.corner(0)
    @model_rbt = model.bounds.corner(7)

    # boundry of selection
    @corner_lfb = selection[0].bounds.corner(0)
    @corner_rbt = selection[0].bounds.corner(0)
    selection.each do |entity| 
      if entity.bounds.corner(0).x < @corner_lfb.x
        @corner_lfb.x = entity.bounds.corner(0).x
      end
      if entity.bounds.corner(0).y < @corner_lfb.y
        @corner_lfb.y = entity.bounds.corner(0).y
      end
      if entity.bounds.corner(0).z < @corner_lfb.z
        @corner_lfb.z = entity.bounds.corner(0).z
      end
      if entity.bounds.corner(7).x > @corner_rbt.x
        @corner_rbt.x = entity.bounds.corner(7).x
      end
      if entity.bounds.corner(7).y > @corner_rbt.y
        @corner_rbt.y = entity.bounds.corner(7).y
      end
      if entity.bounds.corner(7).z > @corner_rbt.z
        @corner_rbt.z = entity.bounds.corner(7).z
      end
    end # selection.each do

    return true
  end

  def trace_outline
    Sketchup.set_status_text "Calculating Gcode: Finding faces", SB_VCB_VALUE
    # Get "handles" to our model and the Entities collection it contains.
    model = Sketchup.active_model
    selection = model.selection
    entities = model.entities
    layers = model.layers
    test_layer = layers["test"]

    p1=nil
    p2=nil
    @lines = []

    temparyGroup = entities.add_group
    entities2 = temparyGroup.entities

    # Make a face parallel to the ground to check for intersections with models faces.
    new_face = entities2.add_face [@corner_lfb[0]-0.1, @corner_lfb[1]-0.1, @height.mm],\
                                  [@corner_rbt[0]+0.1, @corner_lfb[1]-0.1, @height.mm],\
                                  [@corner_rbt[0]+0.1, @corner_rbt[1]+0.1, @height.mm],\
                                  [@corner_lfb[0]-0.1, @corner_rbt[1]+0.1, @height.mm]

    selection.each do |entity| 
      if entity.typename == "Face"
        entity.edges.each do |edge|
          intersect = Geom.intersect_line_plane(edge.line, new_face.plane)
          if intersect
            if p1 == nil
              p1 = intersect
            elsif intersect != p1
              p2 = intersect
              break
            end
          end
        end

        if p1 and p2 and p1 != p2
          @lines.push [p1, p2]
          new_line = entities.add_line p1, p2
          new_line.layer = test_layer
        end
        p1 = nil
        p2 = nil
      end #entity.typename == "Face"
    end
    temparyGroup.erase!

    return "done trace_outline"
  end #trace_outline
  
  def isolate_part
    # Here we iterate through all points on a slice and make sure they are in
    # consecutive order.
    # At the end of this function @wafer_objects will contain an array of
    # @wafer_object.
    # Each @wafer_object will contain a point which together makes up one
    # continuous line to be milled.
    # The code is quicker if the @wafer_object is a loop (ie, finishes at the
    # same physical point it starts at)
    # but the code will work if you only run it on single faces as well.
    Sketchup.set_status_text "Calculating Gcode: Sanitizing shapes", SB_VCB_VALUE
    @wafer_objects = []
    wafer_object = []

    while @lines.size > 0
      line = @lines.shift
      head = line[0]
      tail = line[1]
      wafer_object = [tail, head]

      loop do
        adjacent = @lines.select{ |nextLine| nextLine[0] == head or\
                                             nextLine[0] == tail or\
                                             nextLine[1] == head or\
                                             nextLine[1] == tail}
        if adjacent.size == 0
          break
        end

        adjacent.each do |nextLine|
          if nextLine[0] == head
            head = nextLine[1]
            wafer_object.push(nextLine[1])
            @lines.delete(nextLine)
          elsif nextLine[1] == head
            head = nextLine[0]
            wafer_object.push(nextLine[0])
            @lines.delete(nextLine)
          elsif nextLine[0] == tail
            tail = nextLine[1]
            wafer_object.unshift(nextLine[1])
            @lines.delete(nextLine)
          elsif nextLine[1] == tail
            tail = nextLine[0]
            wafer_object.unshift(nextLine[0])
            @lines.delete(nextLine)
          else
            puts("Could not append line: #{nextLine}")
          end
        end
      end  # loop do

      if wafer_object[0] != wafer_object.last
        if wafer_object[0].distance(wafer_object.last) < @closeGaps
          puts("Closing loop in shape #{@wafer_objects.size + 1}")
          wafer_object.push(Geom::Point3d.new(wafer_object[0].x,\
                                              wafer_object[0].y,\
                                              wafer_object[0].z))
        end
      end
      @wafer_objects.push wafer_object
    end  # while @lines.size > 0

    return "done isolate_part"
  end #isolate_part
 
  # Draw a movement of the cutting head to screen. 
  def draw_path_line(entities, path_layer, start, finish)
    start = [start.x + @offset_x,\
             start.y + @offset_y,\
             @height.to_mm + @offset_z + 0.001]
    finish = [finish.x + @offset_x,\
             finish.y + @offset_y,\
             @height.to_mm + @offset_z + 0.001]
    
    vector = Geom::Vector3d.new(0,0,1).normalize!
    new_edges = entities.add_circle start, vector, @mill_diamiter
    new_face = entities.add_face(new_edges)
    if new_face
      new_face.layer = path_layer
      new_face.material = "green"

      # move circles to path layer.
      new_edges.each do |edge|
        edge.layer = path_layer
      end #new_edges.each

      new_face.all_connected.each do |edge|
        edge.layer = path_layer
      end #new_face.all_connected.each
    end

    xv = start.x - finish.x
    yv = start.y - finish.y
    lenv = Math.sqrt((xv*xv)+(yv*yv))
    xoffset =  - (yv*@mill_diamiter/lenv)
    yoffset =  + (xv*@mill_diamiter/lenv)
    new_face = entities.add_face [start.x + xoffset,\
                                  start.y + yoffset,\
                                  @height + 0.001],\
                                  [start.x - xoffset,\
                                   start.y - yoffset,\
                                   @height + 0.001],\
                                   [finish.x - xoffset,\
                                    finish.y - yoffset,\
                                    @height + 0.001],\
                                    [finish.x + xoffset,\
                                     finish.y + yoffset,\
                                     @height + 0.001]
    new_face.material = "green"

    # move rectangles to path layer.
    new_face.all_connected.each do |edge|
      edge.layer = path_layer
    end #new_face.all_connected.each
  end

  def draw_part
    # This draws out the outline of the identified objects.
    Sketchup.set_status_text "Calculating Gcode: Drawing output", SB_VCB_VALUE
  
    writeGcode("")
  
    if @preview_layout == "Stacked"
    unless @offset_y
      @offset_x = 0
      @offset_y = @model_rbt[1]
      @offset_z = 0
    else
      #@offset_z += @height
    end #unless @offset_y
    
    elsif @preview_layout == "Spread"
    unless @y_flat_spacing
      @y_flat_spacing = @model_rbt[1]
      @offset_x = 0
      @offset_y = @model_rbt[1]
      @offset_z = 0
    else
      @offset_y += @model_rbt[1]
    end #unless

    end #if @preview_layout

    # Get "handles" to our model and the Entities collection it contains.
    model = Sketchup.active_model
    entities = model.entities
    layers = model.layers
    outline_layer = layers["outline"]
    path_layer = layers["path"]

    puts("Drawing #{@wafer_objects.size} objects")
  
    # make sure we are not cutting below the bottom of the selected object.
    if @height.mm < @corner_lfb.z
      @height = @corner_lfb.z.to_mm
    end #if
  
  
    # draw outline of shape to be cut.  
    puts("Draw shape outline to screen in red")
    @wafer_objects.each do |object|
      point_previous = [nil,nil,nil]
      object.each do |point|

        if point_previous[0]
          new_line = entities.add_line [point_previous[0] + @offset_x,\
                                        point_previous[1] + @offset_y,\
                                        @height + @offset_z],\
                                       [point[0] + @offset_x,\
                                        point[1] + @offset_y,\
                                        @height + @offset_z]
          new_line.material = "red"
          new_line.layer = outline_layer
        end #if
        point_previous = point
      end #@point.each
    end #@wafer_objects.each
  
    # draw router path.
    puts("Draw router path to screen in green and write gcode")
    @wafer_paths.each do |path|
      if path[0] != path.last
        path.push path[0]
      end #if

      if path.length > 1
        # Move spindle to safe height.
        @pos_z = @corner_rbt.z + 1
        writeGcode("G01 Z#{roundToPlaces(@pos_z, @decimalPlaces, @units)}")
      end #if

      previous_point = nil
      path.each do |point|
        # Make sure there has been at least some movement.
        if previous_point and\
            ((point.x - previous_point.x).abs > @minimumResolution or\
             (point.y - previous_point.y).abs > @minimumResolution)
          @pos_x = point.x
          @pos_y = point.y
          writeGcode("G01 X#{roundToPlaces(@pos_x, @decimalPlaces, @units)} "\
                           "Y#{roundToPlaces(@pos_y, @decimalPlaces, @units)}")
          if (@height != @pos_z)
            @pos_z = @height
            writeGcode("G01 Z#{roundToPlaces(@pos_z, @decimalPlaces, @units)}")
          end #if

          draw_path_line(entities, path_layer, point, previous_point)
          previous_point = point
        end #if (point.x - previous_point.x).abs > 0.01....
        if previous_point == nil
          # First time through this loop.
          previous_point = point
        end
      end #@path.each do |point|

    end #@wafer_paths.each do |path|

    return "done draw_part"
  end #draw_part
  
  
  def router_path
    Sketchup.set_status_text "Calculating Gcode: Calculating router offset", SB_VCB_VALUE

    # Get "handles" to our model and the Entities collection it contains.
    model = Sketchup.active_model
    entities = model.entities

    @wafer_paths=[]

    @wafer_objects.each do |object|
      wafer_path=[]

      loop = (object[0] == object.last)
      if loop
        puts("Loop")
      else
        puts("Not loop. Starts: #{object[0]} Ends: #{object.last}")
      end #if

      line2 = nil
      last = (object.length) -1

      # This logic only works for loops.
      # ie, when the line starts and finishes in the same place.
      if loop
        object.each do |point|
          pos = object.index(point)
          if pos < last
            xv = point[0] - object[pos+1][0]
            yv = point[1] - object[pos+1][1]

            xcenter = point[0] - xv/2
            ycenter = point[1] - yv/2
            lenv = Math.sqrt((xv*xv)+(yv*yv))

            outside_inside = 1
            xoffset = -(yv * @mill_diamiter/lenv) 
            yoffset = +(xv * @mill_diamiter/lenv) 
            x = xcenter + xoffset
            y = ycenter + yoffset      

            @wafer_objects.each do |object2|
              if Geom.point_in_polygon_2D([x,y,@height.mm], object2, true)
                outside_inside *= -1
              end #if
            end

            xoffset = -(yv * @mill_diamiter/lenv) * outside_inside
            yoffset = +(xv * @mill_diamiter/lenv) * outside_inside
            x = xcenter + xoffset
            y = ycenter + yoffset      

            line1 = line2
            line2 = [Geom::Point3d.new(x, y, @height), Geom::Vector3d.new(xv, yv, 0)]

            if line1
              centerpoint = Geom.intersect_line_line(line1, line2)
              if centerpoint
                wafer_path.push(centerpoint)
              end #if centerpoint
            end #if line1

          end #if pos < last
        end #@point.each
      end #if loop

      @wafer_paths.push(wafer_path)
    end #@wafer_objects.each  
  end #router_path
  
end
