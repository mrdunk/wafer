require 'sketchup'

@configKeys = ["cutDiamiter",\
               "cutDepth",\
               "decimalPlaces",\
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
def roundToPlaces(value, places)
  return (value * (10 ** places.to_i)).round.to_f / (10 ** places.to_i)
end

def roundPointToPlaces(point, places)
  return Geom::Point3d.new(roundToPlaces(point.x, places),\
                           roundToPlaces(point.y, places),\
                           roundToPlaces(point.z, places))
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
      new_wafer.out_file = gcodeFile
      new_wafer.preview_layout = @config["orientation"]
      new_wafer.height = 0
      new_wafer.cut_depth = @config["cutDepth"]
      new_wafer.mill_diamiter = (@config["cutDiamiter"].to_f)/100
      new_wafer.find_bounds
      new_wafer.header  
      new_wafer.create_layers
      new_wafer.decimalPlaces = @config["decimalPlaces"]
      new_wafer.closeGaps = @config["closeGaps"]

      if @config["scriptMode"] == "Single"
        new_wafer.single
      elsif @config["scriptMode"] == "Repeated single"
        new_wafer.repeated_single
      elsif @config["scriptMode"] == "Contour"
        new_wafer.contour
      end

      new_wafer.footer
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

  # Populate output file with gcode header.
  def header
    @pos_x = 0
    @pos_y = 0
    @pos_z = @corner_rbt.z.to_mm + 1 

    @outputfile = File.new( @out_file , "w" )
    @outputfile.puts("G21 ( Unit of measure: mm )")
    @outputfile.puts("G90 ( Absolute programming )")
    @outputfile.puts("M03 ( Spindle on [clockwise] )")
    @outputfile.puts("G00 Z#{@pos_z} ( Rapid positioning to highest point )")

  end #header

  # Populate output file with gcode footer.
  def footer
    @pos_z = @corner_rbt[2].to_mm + 1

    @outputfile.puts("")
    @outputfile.puts("G00 Z#{@pos_z} ( Rapid positioning to highest point +1mm )")
    @outputfile.puts("M05 ( Spindle stop )")
    @outputfile.puts("M02 ( End of program )")

    @outputfile.puts("")
    @outputfile.puts("( end )")
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
    @height = @corner_lfb.z.to_mm
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

    @height = @corner_rbt.z.to_mm
    thickness = (@corner_rbt.z - @corner_lfb.z).to_mm

    while thickness > 0
      thickness -= @cut_depth.to_f
      @height -= @cut_depth.to_f

      puts(draw_part)
      #puts(@height)
    end
  
  end #def repeated_single
  
  def contour
    @height = @corner_rbt.z.to_mm
    thickness = (@corner_rbt.z - @corner_lfb.z).to_mm
    while thickness >= 0
      #puts(@height)
      thickness -= @cut_depth.to_f
      @height -= @cut_depth.to_f
      # make sure we are not cutting below the bottom of the selected object.
      if @height.mm < @corner_lfb.z
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
            else
              p2 = intersect
            end
          end
        end

        if p1 and p2
          @lines.push [roundPointToPlaces(p1, @decimalPlaces),
                       roundPointToPlaces(p2, @decimalPlaces)]
          new_line = entities.add_line p1, p2
          new_line.layer = test_layer
        end
        p1 = nil
        p2 = nil
      end #entity.typename == "Face"
    end
    temparyGroup.erase!

    #new_face=nil
    #puts(@lines.length)  
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
  
  
  def draw_part
    # This draws out the outline of the identified objects.
    Sketchup.set_status_text "Calculating Gcode: Drawing output", SB_VCB_VALUE
  
    @outputfile.puts()
  
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
    vector = Geom::Vector3d.new 0,0,1
    vector2 = vector.normalize!

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
        #puts(@point)

        if point_previous[0]
          new_line = entities.add_line [point_previous[0]+@offset_x,\
                                        point_previous[1]+@offset_y,\
                                        @height.mm+@offset_z],\
                                       [point[0]+@offset_x,\
                                        point[1]+@offset_y,\
                                        @height.mm+@offset_z]
          new_line.material = "red"
          new_line.layer = outline_layer
        end #if
        point_previous = point
      end #@point.each

    end #@wafer_objects.each
  
    # draw router path.
    puts("Draw router path to screen in green and write gcode")
    @wafer_paths.each do |path|
      previous_point = nil
      if path[0] != path.last
        path.push path[0]
      end #if

      if path.length > 1
        @pos_z = @corner_rbt[2].to_mm + 1
      end #if

      path.each do |point|
        if point
          if (@height != @pos_z)
            if (point.x.to_mm != @pos_x) || (point.y.to_mm != @pos_y)
              @pos_z = @corner_rbt[2].to_mm + 1
              @outputfile.puts(
                "G00 Z#{roundToPlaces(@pos_z, @decimalPlaces)} "\
                "( Rapid positioning to highest point +1mm )")
            end #if point.x != @pos_x
            @pos_x = point.x.to_mm
            @pos_y = point.y.to_mm
            @outputfile.puts(
              "G01 X#{roundToPlaces(@pos_x, @decimalPlaces)} "\
              "Y#{roundToPlaces(@pos_y, @decimalPlaces)}")
            @pos_z = @height
            @outputfile.puts("G01 Z#{roundToPlaces(@pos_z, @decimalPlaces)}")
          else
            @pos_x = point.x.to_mm
            @pos_y = point.y.to_mm
            @outputfile.puts(
              "G01 X#{roundToPlaces(@pos_x, @decimalPlaces)} "\
              "Y#{roundToPlaces(@pos_y, @decimalPlaces)}")
          end #if

          point = [point[0]+@offset_x,point[1]+@offset_y,@height.mm+@offset_z + 0.001]
          new_edges = entities.add_circle point, vector2, @mill_diamiter
          new_face = entities.add_face(new_edges)
          if new_face
            new_face.layer = path_layer
            new_face.material = "green"

            # move circles to path layer.
            new_edges.each do |edge|
              edge.layer = path_layer
            end #new_edges.all_connected.each

            new_face.all_connected.each do |edge|
              edge.layer = path_layer
            end #new_face.all_connected.each
          end

          if previous_point
            xv = point[0] - previous_point[0]
            yv = point[1] - previous_point[1]
            lenv = Math.sqrt((xv*xv)+(yv*yv))
            xoffset =  - (yv*@mill_diamiter/lenv)
            yoffset =  + (xv*@mill_diamiter/lenv)
            new_face = entities.add_face [point[0]+xoffset,\
                                          point[1]+yoffset,\
                                          @height.mm + 0.001],\
                                         [point[0]-xoffset,\
                                          point[1]-yoffset,\
                                          @height.mm + 0.001],\
                                         [previous_point[0]-xoffset,\
                                          previous_point[1]-yoffset,\
                                          @height.mm + 0.001],\
                                         [previous_point[0]+xoffset,\
                                          previous_point[1]+yoffset,\
                                          @height.mm + 0.001]
            new_face.material = "green"

            # move rectangles to path layer.
            new_face.all_connected.each do |edge|
              edge.layer = path_layer
            end #new_face.all_connected.each

          end #if previous_point
          previous_point = point
        end #if point
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

      loop=nil
      if object[0] == object.last
        loop=1
      else
        puts("Not loop #{object[0]} #{object.last}")
      end #if

      point_previous = [nil,nil,nil]
      line2 = [nil,nil]

      last = (object.length) -1

      object.each do |point|
        if loop
          pos = object.index(point)
          if pos < last
            xv = point[0] - object[pos+1][0]
            yv = point[1] - object[pos+1][1]

            xcenter = point[0] - xv/2
            ycenter = point[1] - yv/2
            lenv = Math.sqrt((xv*xv)+(yv*yv))

            outside_inside = 1
            xoffset =  - (yv*@mill_diamiter/lenv) 
            yoffset =  + (xv*@mill_diamiter/lenv) 
            x = xcenter + xoffset
            y = ycenter + yoffset      

            @wafer_objects.each do |object2|
              if Geom.point_in_polygon_2D([x,y,@height.mm], object2, true)
                outside_inside *= -1
              end #if
            end

            xoffset =  - (yv*@mill_diamiter/lenv) * outside_inside
            yoffset =  + (xv*@mill_diamiter/lenv) * outside_inside
            x = xcenter + xoffset
            y = ycenter + yoffset      

            line1 = line2
            line2 = [Geom::Point3d.new(x, y, @height.mm), Geom::Vector3d.new(xv,yv,0)]

            if point_previous[0] 
              centerpoint = Geom.intersect_line_line(line1,line2)

              if centerpoint
                wafer_path.push(centerpoint)
              end #if centerpoint
            end #if @point_previous[0]
          end #if pos < last
        end #if loop
        point_previous = point
      end #@point.each

      @wafer_paths.push(wafer_path)
    end #@wafer_objects.each  
  end #router_path
  
end
