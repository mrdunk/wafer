=begin

MIT License

Copyright (c) 2020 The Wafer Authors. (See AUTHORS file.)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

##
## TOOL DESCRIPTION
##
## This tool takes a selected geometry (no group or components yet) and generates Gcode from it.
## Command is in menu "Tools" and is "generate gcode"
## Geometry has to have some thickness for it to work and it will only consider geometry that goes fully through the thickness of the part, anything else will be ignored.
## Option menu is provided at the beginning, not all options have an effect yet.
## Depending on options various Gcode will be generated in header/footer
## Then motion code will be generated, one loop for each independent feature
## the gcode file is stored as an .nc file and it sports the sketchup file name by default.
## It also take on the layer name of the geoometry entities PROVIDED that all the selected one are on the same layer. It will ignore anything that is
## not a face nor an edge (dimension, guide line for example)
## This allows to have several parts in a drawing on different layers and to create a self executing gcode for each part/layer independently
## Just select all geometry that is on a given layer and the file name will be 'sketchupfilename_layername'.nc
## It also allows to create one gcode file for all the parts at once. Select it all and when they are on different layers,
## the gcode file will be 'sketchupfilename'.nc
##
##
## Description of options:
## cutdiameter: Set the tool diameter, and thus the offset; kerf is a tool diameter; If 0 it will machine on the line
## cutDepth: It will set up the default cut depth for multiple pass; At some point it will be interpolated for intermediary faces, not done yet.
## Z tool Offset: not implemented yet, but the plan it to give a tool offset, for example to focus laser, or for he needle to cut below (negative offset), etc..
## scriptmode: machining option; 4 options so far
##      single plane: all the gcode will be conforming to the bottom layer of the geometry, one pass
##      Single plane with bevels: not implemented yet, but will be the same except some edges and maybe lines will be cut as bevels
##      Multiple Depths: It will machine the contour with multiple passes at cut depth (not fully working yet), and intermediary faces (not yet implemented)
##      Contour:
## feedrate: sets the base feed rate, if paramperpath is no, then this feed rate will apply to the whole gcode file, otherwise feedrate per loop (not implemented yet)
## paraperpath: If no the cutting parameters will apply to the whole gcode file. If yes will be able to change cutting parameter (feedrate, depth, tool, spindle) per each feature/loop
## units: It's the unit that you want the gcode file output to be in
## coolant: If yes it will set up both coolant channel in the code (mist and flood)
## climb: not implemented yet
## orientation: "On part" will display the tool path on the part
##      "Spread" will display the tool path next to the part; if multiple they will all be spread on the plane
##      "stacked" will display all the machining path (multiple depths) as a stack offset from the part
## displaytoolwidth, will draw the entire tool width on the tool path, not just the center. It makes the drawing slower
## debug: yes will show the ruby console
##
##
##
## This tool is not designed for professional use.
## Consequently, no liabilty in any form whatsoever can be attributed to the author or his company in case of use
## for doing or making anything. If you as a user choose to use this tool, you implicetly understand that this software
## is provided "as is", does not intend to fit any specific purpose beyond the scope of what it may or may not do.
## You furthermore agree that you are using it at your own risk.
##
## Tool copyright Edge LLC, Michael Vulpillat, 2020
## Edgecons@usa.net
## copyright 2020

Version history:
Based on the original wafer.rb version 0.2.13 made by Duncan Law
Evolution from April 2020 by Michael Vulpillat, EDGE LLC.
Version 0.3 April 2020
Forced edge color display, changed name and menu of command line, nc file bears the file and layer name
Changed spelling of "Diamiter", included coolant channel, feedrate (not fully implemented yet)
Fixed offset bug in which path was not at half mill diameter.
Made displays appear in prompt instead of VCB value
0.3.8 added feedrate per section, not working yet. Feedrate works
added option for climb or conventional milling, not yet implemented in gcode
Added file name in Gcode file comments
Changed displayPath variable name to displayToolwidth
Made it unit independent, based on length object in sketchup
Forced rounding to 3 for mm and 4 for inches, no more ask.
Not displaying outline if path is "On Part"
0.4.1
More dimension independence; Changed the whole structure to more conventional sketchup ruby class and call
Introduced an environment unit flag @envunit, to condition behavior.
0.4.3 Change default config file name (added m) and provided for version on menu window
0.4.4 puts label for each contour; Has G00 for rapid motion to contour.
0.4.5 added tool option.
0.4.6 achieved dimension independence.
      added a suffix to the filee name for tool used
      (L for Laser; R for router; NC for needle cutter; P for Pen)
0.4.8 Cleaned up all unecessary variables manipulation.
0.4.9 Cleaned up class structure. Made attributes instance variables.

TODO:
#### finish implementing feedrate
#### finish different tools (only Laser and Routing are set)
#### finish parameters per section
#### implement climbing/conventional
#### implement which plane and bevels
=end


@@version = "v0.4.9"
@@config_file = 'wafer_rb.config'

require 'sketchup'
class Wafer

  def initialize
    @model = Sketchup.active_model
    @selection = @model.selection
    # UnitsOptions: 0="; 1='; 2=mm; 3=cm; 4=m
    @envunit = Sketchup.active_model.options["UnitsOptions"]["LengthUnit"]
  end #initialize

  # Reset config to default values.
  def clearConfig()
    @config.each do |key, value|
      result = Sketchup.write_default(@@config_file, key,  nil)
      puts("clear: #{key} #{result}")
    end
  end #clearConfig

  # Save entries in @config to persistent storage.
  def saveConfig()
    @config.each do |key, value|
      result = Sketchup.write_default(@@config_file, key,  value)
      puts("save: #{key}, #{value}, #{result}")
    end
  end #saveConfig

  # Load configuration from persistent storage into @config hashmap.
  def loadConfig()
    feeddef = "500" if [2, 3, 4].include? @envunit
    feeddef = "20" if [0, 1].include? @envunit
    defaultValue = {\
                    "scriptMode" => "Single Plane",\
                    "toolref" => "Router",\
                    #"cutDiameter" => "2.0 mm",\
                    #"cutDepth" => "0.5 mm",\
                    "feedrate" => feeddef,\
                    "paramperpath" => "No",\
                    "closeGaps" => "1.0 mm",\
                    "orientation" => "Stacked",\
                    "minimumResolution" => "0.01 mm",\
                    "units" => "mm",\
                    "displayToolwidth" => "No",\
                    "coolant" => "No",\
                    "climb" => "Climb",\
                    "debug" => "No"}

    @configKeys.each do | key |
      value = Sketchup.read_default(@@config_file, key)
      puts("load: #{key}, #{value}")
      if value.nil?
        value = defaultValue[key]
      end
      @config[key] = value
    end
  end #loadConfig

  # Set values in the @config hashmap.
  def menu()
    feedtext = "Base Feed Rate (mm/mn)" if [2, 3, 4].include? @envunit
    feedtext = "Base Feed Rate (ipm)" if [0, 1].include? @envunit
    configDescriptions = {\
                          "scriptMode" => "Machining Options",\
                          "cutDiameter" => "Tool Diameter",\
                          "cutDepth" => "Depth of Cut",\
                          "toolref" => "Tool Used",\
                          "feedrate" => feedtext,\
                          "paramperpath" => "Cutting Parameters/Loop",\
                          "climb" => "Type of Milling:",\
                          "closeGaps" => "Close gaps, looped paths",\
                          "orientation" => "Preview Path Position",\
                          "minimumResolution" => "Minimum resolution",\
                          "units" => "Units to use in Gcode file",\
                          "displayToolwidth" => "Display tool path width (slower)",\
                          "coolant" => "Trigger ''Coolant''",\
                          "debug" => "Show Ruby Console"}
    # TODO(dunk): `sizes` is only used by `closeGaps` now and i think even that could
    # use Michael's simplified units.
    # If we can't make `closeGaps` go away entirely, let's replace this with a
    # simple input field.
    sizes = "0.0|"\
      "0.01|0.02|0.03|0.04|0.05|0.06|0.07|0.08|0.09|"\
      "0.1|0.2|0.3|0.4|0.5|0.6|0.7|0.8|0.9|"\
      "1.0|1.1|1.2|1.3|1.4|1.5|1.6|1.7|1.8|1.9|"\
      "2.0|2.1|2.2|2.3|2.4|2.5|2.6|2.7|2.8|2.9|"\
      "3.0|3.175|3.5|4.0|4.5|5.0|6.0|6.35|7.0|8.0|9.0|9.525|10.0|"\
      "12.0|12.7|14.0|15.0|16.0|18.0|20.0|"\
      "25.0|30.0|35.0|40.0|50.0|100.0"
    menuOptions = {\
                   "scriptMode" => "Single Plane|Single with Bevels|Multiple Depths|Contour",\
                   "toolref" => "Router|Laser|Needle Cutter|Pen",\
                   "paramperpath" => "Yes|No",\
                   "climb" => "Climb|Conventional",\
                   "closeGaps" => sizes,\
                   "orientation" => "On Part|Spread|Stacked",\
                   "minimumResolution" => "0.001|0.01|0.1|1|2|5|10",\
                   "units" => "mm|inches",\
                   "displayToolwidth" => "Yes|No",\
                   "coolant" => "Yes|No",\
                   "debug" => "Yes|No"}
    descriptions = []
    values = []
    options = []
    @configKeys.each do | key |
      descriptions.push(configDescriptions[key])
      values.push(@config[key])
      options.push(menuOptions[key])
    end
    input = UI.inputbox descriptions, values, options, "Gcode parameters     #{@@version}"

    if input
      for x in 0..(input.size - 1)
        key = @configKeys[x]
        @config[key] = input[x]
        puts("menu: #{key} #{input[x]}")
      end
      return true
    end
  end # menu

  # Round floats down to a sane number of decimal places.
  def roundToPlaces(value, units)
    value = value.to_l
    if units == "mm"
      value = value.to_mm
      returnVal = ((value * (10 ** 3)).round.to_f / (10 ** 3))
      return returnVal
    elsif units == "inches"
      value = value.to_inch
      returnVal = ((value * (10 ** 4)).round.to_f / (10 ** 4))
      return returnVal
    end
    raise ("Invalid units: " + units.to_s)
  end # roundToPlaces

  # Add a menu item to launch our plugin.
  def activate()
    @configKeys = ["cutDiameter",\
                   "toolref",\
                   "cutDepth",\
                   "units",\
                   "feedrate",\
                   "paramperpath",\
                   "scriptMode",\
                   "orientation",\
                   "displayToolwidth",\
                   "minimumResolution",\
                   "closeGaps",\
                   "coolant",\
                   "climb",\
                   "debug"]
    @config = {}

    Sketchup.set_status_text "Calculating Gcode", SB_PROMPT

    loadConfig()
    if menu()
      saveConfig()

      if @config["debug"] != "No"
        # Show the Ruby Console at startup so we can
        # see any programming errors we may make.
        Sketchup.send_action "showRubyPanel:"
      end # Ruby Console

      # Generate file with name
      @toolref = @config["toolref"]
      modelPath = Sketchup.active_model.path
      if File.exists?(modelPath)
        @namef = File.basename(modelPath, '.*')
      else
        @namef = "untitled"
      end

      # Get the name of selected layer.
      alayer = "empty"
      it = @selection.count - 1
      for i in 0..it do
        if (@selection[i].typename  == "Edge" || @selection[i].typename  == "Face")
          alayer = @selection[i].layer.name if alayer == "empty"
          if @selection[i].layer.name != alayer
            alayer = ""
            break
          end
        end
      end # for i--defining layer name for file
      @namef = @namef +"_"+ alayer if alayer != ""

      # generates the suffix for filename depending on tooling
      fnsfx = ""
      fnsfx = "_L" if @toolref == "Laser"
      fnsfx = "_P" if @toolref == "Pen"
      fnsfx = "_NC" if @toolref == "Needle Cutter"
      fnsfx = "_R" if @toolref == "Router"
      @namef = @namef + fnsfx

      gcodeFile = UI.savepanel "Save Gcode File", "c:\\", @namef+".nc"
      puts("Writing to #{gcodeFile}")
      if gcodeFile
        if find_bounds.nil?
          Sketchup.set_status_text "Select Geometry!", SB_PROMPT
          puts("No geometry selected")
          UI.messagebox("No geometry selected", type = MB_OK)
          return
        else
          @out_file = gcodeFile
          @preview_layout = @config["orientation"]
          @height = 0
          @cutDepth = @config["cutDepth"].to_l
          @cutDiameter = @config["cutDiameter"].to_l
          @feedrate = @config["feedrate"].to_l
          @paramperpath = @config["paramperpath"]
          @coolant = @config["coolant"]
          @climb = @config["climb"]
          @minimumResolution = @config["minimumResolution"].to_l
          @units = @config["units"]
          @closeGaps = @config["closeGaps"].to_l
          @displayToolwidth = @config["displayToolwidth"]
          create_layers
          header

          if @config["scriptMode"] == "Single Plane"
            single
            @bevelflag = false
          elsif @config["scriptMode"] == "Multiple Depths"
            repeated_single
            @bevelflag = false
          elsif @config["scriptMode"] == "Contour"
            contour
            @bevelflag = false
          elsif @config["scriptMode"] == "Single with Bevels"
            single
            @bevelflag = true
          end  # @config -> scriptMode

          footer
        end #if find_bounds == nil
      end #if gcodeFile
    end #if menu()

    # MV Turns on edges color by material display
    Sketchup.active_model.rendering_options["EdgeColorMode"]=0
  end #activate

  def writeGcode(line, flush=false)
    if @outputfile.nil?
      if @out_file.nil? || @out_file.empty?
        raise ("Missing filename in variable @out_file")
      end

      puts("Opening file: #{@out_file}")
      @outputfile = File.new( @out_file , "w" )
      @gcodeContent = String.new("")
    end
    @gcodeContent.concat(line).concat("\n")

    if flush or @gcodeContent.length > 10000
      @outputfile.puts(@gcodeContent)
      @gcodeContent = String.new("")
    end
  end # writeGcode

  # Populate output file with gcode header.
  def header
    @pos_x = 0
    @pos_y = 0
    @safeheight = @corner_rbt.z + 1
    @pos_z = @safeheight

    writeGcode("( Gcode for Machining of " + @namef + " )")
    writeGcode("")
    writeGcode("( Tool used: " + @toolref + " )")
    tooldia = roundToPlaces(@cutDiameter, @units)
    passdepth = roundToPlaces(@cutDepth, @units)
    writeGcode("( Tool Diameter " +tooldia.to_s + " " + @units + " )")
    writeGcode("( Depth of Pass " + passdepth.to_s + " " + @units + " )")
    writeGcode("G21 ( Unit of measure: mm )") if @units == "mm"
    writeGcode("G20 ( Unit of measure: inches )") if @units == "inches"
    writeGcode("G90 ( Absolute programming )")
    writeGcode("M03 ( Spindle on clockwise )")
    writeGcode("M7 (turn on mist coolant)") if @coolant == "Yes"
    writeGcode("M8 (turn on flood coolant)") if @coolant == "Yes"
    writeGcode("G00 Z#{roundToPlaces(@pos_z, @units)} \
               ( Rapid positioning to highest point + safety )") if @toolref != "Laser"
    if @paramperpath == "No"  #If per section it will be written in the loop
      feedr = roundToPlaces (@feedrate, @units)
      writeGcode("F" + feedr.to_s + "  (Feed Rate in mm/mn)") if @units == "mm"
      writeGcode("F" + feedr.to_s + "  (Feed Rate in ipm)") if @units == "inches"
    end #if @paramperpath
  end # header

  # Populate output file with gcode footer.
  def footer
    @pos_z = @safeheight

    writeGcode("")
    writeGcode("M9 (turn off all coolant)") if @coolant == "Yes"
    writeGcode("G00 Z#{roundToPlaces(@pos_z, @units)} \
               ( Rapid positioning to highest point + safety )") if @toolref != "Laser"
    writeGcode("M05 ( Spindle stop )")
    writeGcode("M02 ( End of program )")

    writeGcode("")
    writeGcode("( end )", true)

    @outputfile.close()
  end # footer

  def create_layers
    # here we create some separate layers to display our router paths on.
    # happily it does not seem to matter if we try to create a layer that already exists.
    layers = @model.layers
    outline_layer = layers.add "outline"
    path_layer = layers.add "path"
    loops_layer = layers.add "Contour ID"  # to put the loop labels into
  end #create_layers

  def single
    @height = @corner_lfb.z
    timeBegin = Time.now
    trace_outline      #    puts(trace_outline)
    timeOutline = Time.now
    isolate_part      #puts(isolate_part)
    timeIsolate = Time.now
    router_path        #    puts(router_path)
    timeRoute = Time.now
    draw_part          #    puts(draw_part)
    timeEnd = Time.now

    puts("Outline:\t#{timeOutline - timeBegin}\n"\
         "Isolate:\t#{timeIsolate - timeOutline}\n"\
         "Route:  \t#{timeRoute - timeIsolate}\n"\
         "Gcode:  \t#{timeEnd - timeRoute}\n"\
         "Total:  \t#{timeEnd - timeBegin} seconds")

    puts("toolref : #{@toolref}\n"\
         "cutDiameter: #{@cutDiameter.to_mm}mm\n"\
         "cutDepth: #{@cutDepth.to_mm}mm\n"\
         "feedrate #{@feedrate.to_mm}mm/mn\n"\
         "paramperpath: #{@paramperpath}\n"\
         "minimumResolution: #{@minimumResolution.to_mm}mm\n"\
         "units: #{@units}\n"\
         "closeGaps: #{@closeGaps.to_mm}mm\n"\
         "displayToolwidth: #{@displayToolwidth}\n"\
         "coolant: #{@coolant}\n"\
         "climb: #{@climb}\n"\
         "version: #{@@version}")
    return
  end #def Single

  def repeated_single
    trace_outline
    isolate_part
    router_path

    @height = @corner_rbt.z
    thickness = @scalez

    while thickness > 0
      thickness -= @cutDepth
      @height -= @cutDepth
      draw_part
    end

  end #def repeated_single

  def contour
    @height = @corner_rbt.z
    puts("@height: #{@height}")
    while @height > 0
      @height -= @cutDepth
      puts("@height: #{@height}")
      trace_outline
      isolate_part
      router_path
      draw_part
    end

  end #contour

  def find_bounds
    if @selection.nil? or @selection[0].nil?
      return
    end

    # boundary of whole model
    @model_lfb = @model.bounds.corner(0)
    @model_rbt = @model.bounds.corner(7)

    # boundary of selection
    @corner_lfb = @selection[0].bounds.corner(0)
    @corner_rbt = @selection[0].bounds.corner(0)
    @selection.each do |entity|
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
    end # @selection.each do
    modelysize = @corner_rbt.y - @corner_lfb.y
    modelxsize = @corner_rbt.x - @corner_lfb.x
    modelzsize = @corner_rbt.z - @corner_lfb.z
    # Use @scaley to get a sense of size of model in Y; used in sizing the label letters.
    @scaley = modelysize.abs    
    @scalex = modelxsize.abs
    @scalez = modelzsize.abs

    return true
  end #find_bounds



  def trace_outline
    Sketchup.set_status_text " Drawing Outline", SB_PROMPT
    # Get "handles" to our model and the Entities collection it contains.
    entities = @model.entities

    p1 = nil
    p2 = nil
    @lines = []

    temparyGroup = entities.add_group
    entities2 = temparyGroup.entities

    # Make a face parallel to the ground to check for intersections with models faces.
    new_face = entities2.add_face [@corner_lfb[0]-0.1, @corner_lfb[1]-0.1, @height],\
      [@corner_rbt[0]+0.1, @corner_lfb[1]-0.1, @height],\
      [@corner_rbt[0]+0.1, @corner_rbt[1]+0.1, @height],\
      [@corner_lfb[0]-0.1, @corner_rbt[1]+0.1, @height]

    @selection.each do |entity|
      if entity.typename == "Face"
        face = entity
        face.edges.each do |edge|
          point = Geom.intersect_line_plane(edge.line, new_face.plane)
          if point and\
              (face.classify_point(point) == Sketchup::Face::PointOnVertex or\
               face.classify_point(point) == Sketchup::Face::PointOnEdge or\
               face.classify_point(point) == Sketchup::Face::PointInside)
          if p1.nil?
              p1 = point
            elsif point != p1
              p2 = point
              break
            end
          end
        end

        if p1 and p2
          @lines.push [p1, p2]
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
    #MV    Sketchup.set_status_text "Isolate", SB_VCB_VALUE
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

  # Draw a movement of the cutting head to gcode file.
  def draw_path_gcode(point, rapid)
    @pos_x = point.x
    @pos_y = point.y
    if rapid
      gcommand = "G00"
    else
      gcommand = "G01"
    end #if speed
    writeGcode("#{gcommand} X#{roundToPlaces(@pos_x, @units)} Y#{roundToPlaces(@pos_y, @units)}")
    if (@height != @pos_z)
      @pos_z = @height
      writeGcode("G01 Z#{roundToPlaces(@pos_z, @units)}") if @toolref != "Laser"
    end #if
  end #draw_path_gcode

  # Draw a movement of the cutting head to screen.
  def draw_path_screen(entities, path_layer, start, finish, colour="green")
    if @displayToolwidth == "Yes" and @cutDiameter > 0
      draw_path_screen_complex(entities, path_layer, start, finish, colour)
    else
      draw_path_screen_simple(entities, path_layer, start, finish, colour)
    end
  end #draw_path_screen

  def draw_path_screen_simple(entities, path_layer, start, finish, colour)
    new_line = entities.add_line [start.x + @offset_x,\
                                  start.y + @offset_y,\
                                  @height + @offset_z + 0.001],\
                                  [finish.x + @offset_x,\
                                   finish.y + @offset_y,\
                                   @height + @offset_z + 0.001]
    if new_line
      new_line.material = colour
      new_line.layer = path_layer
    end
  end #draw_path_screen_simple

  def draw_path_screen_complex(entities, path_layer, start, finish, colour)
    if start == finish
      return
    end

    start = [start.x + @offset_x,\
             start.y + @offset_y,\
             @height + @offset_z + 0.001]
    finish = [finish.x + @offset_x,\
              finish.y + @offset_y,\
              @height + @offset_z + 0.001]

    vector = Geom::Vector3d.new(0, 0, 1).normalize!
    new_edges = entities.add_circle start, vector, @cutDiameter / 2
    new_face = entities.add_face(new_edges)
    if new_face
      new_face.layer = path_layer
      new_face.material = colour
      new_face.back_material = colour

      # move circles to path layer.
      new_edges.each do |edge|
        edge.layer = path_layer
      end #new_edges.each

      new_face.all_connected.each do |edge|
        edge.layer = path_layer
      end #new_face.all_connected.each
    end # if new_face

    xv = start.x - finish.x
    yv = start.y - finish.y
    lenv = Math.sqrt((xv * xv) + (yv * yv))
    if lenv > @cutDiameter / 2
      # Only bother with this if it's longer than the cutter radius circle.
      xoffset =  - (yv * @cutDiameter / lenv / 2)
      yoffset =  + (xv * @cutDiameter / lenv / 2)
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
      new_face.material = colour
      new_face.back_material = colour

      # move rectangles to path layer.
      new_face.all_connected.each do |edge|
        edge.layer = path_layer
      end #new_face.all_connected.each
    end #lenv > @cutDiameter / 2
  end # draw_path_screen_complex

  def draw_part
    # This draws out the outline of the identified objects.
    Sketchup.set_status_text "Writing gcode", SB_PROMPT

    if @preview_layout == "Stacked"
      unless @offset_y
        @offset_x = 0
        @offset_y = @model_rbt[1]
        @offset_z = 0
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
    elsif @preview_layout == "On Part"
      # unless @y_flat_spacing
      @offset_x = 0
      @offset_y = 0
      @offset_z = 0
    else
      puts("Invalid value for @preview_layout: #{@preview_layout}")
    end #if @preview_layout

    entities = @model.entities
    layers = @model.layers
    outline_layer = layers["outline"]
    path_layer = layers["path"]
    loops_layer = layers["Contour ID"]

    puts("Drawing #{@wafer_objects.size} objects")

    # make sure we are not cutting below the bottom of the selected object.
    if @height < @corner_lfb.z
      @height = @corner_lfb.z
    end #if

    # draw outline of shape to be cut, only if path is not drawn "on Part"
    if @preview_layout != "On Part"
      puts("Draw shape outline to screen in red")
      count = 1
      @wafer_objects.each do |object|
        Sketchup.set_status_text "Showing outline: #{count}/#{@wafer_objects.length}", SB_PROMPT
        count += 1

        point_previous = [nil, nil, nil]
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
    end #if @preview_layout

    # draw router path.
    puts("Draw router path to screen in green and write gcode")
    count = 1
    @wafer_paths.each do |path|
      Sketchup.set_status_text "Writing gcode: #{count}/#{@wafer_paths.length}", SB_PROMPT
      writeGcode ("")
      loopheight = roundToPlaces(@height, @units)
      writeGcode("( Contour #{count} Path #{loopheight} )")
      loopname = "Contour #{count} Z #{loopheight}"

      #MV here I would ask for change in parameters, if paramperpath == "Yes"; make sure it does it for the first loop as well.

      if path.length == 0  #&& @cutDiameter != 0  # MV is this where we reject non closed loops?
        puts("Path #{count} is not a loop. Try increasing closeGaps value.")
        next
      end
      count += 1

      previous_point = path.last

      if @pos_x != previous_point.x or @pos_y != previous_point.y
        # Move spindle to safe height.
        @pos_z = @safeheight
        writeGcode("G00 Z#{roundToPlaces(@pos_z, @units)}") if @toolref != "Laser"
      end #if

      draw_path_gcode(previous_point, true)

      path.each do |point|
        # Make sure there has been at least some movement.

        # MV 4/26/20 that is the only way minimum res is used. since the data is set to a given res
        # which is 0.001 for mm and 0.0001 for inches then all it needs is x-x>0 or y-y>0 ?
        if previous_point and ((point.x - previous_point.x).abs > @minimumResolution or (point.y - previous_point.y).abs > @minimumResolution)
          draw_path_gcode(point, false)
          draw_path_screen(entities, path_layer, previous_point, point)
          if point == path.first
            draw_label(entities, point, @height, loopname, "Contour ID", "green")
          end
          previous_point = point
        end #if previous_point and...
      end #@path.each do |point|
    end #@wafer_paths.each do |path|

    return "done draw_part"
  end #draw_part

  def draw_label(entities, position, height, name, layer, material="green", letter_height=nil)
    # Puts text "name" at "position" and in layer "layer" for
    # entities/path "entities", paint with material "mat")
    # letter_height is 1/25 of the total size in y of the model.

    _position = position.clone + [@offset_x, @offset_y, @offset_z]
    
    if letter_height.nil?
      letter_height = Math.sqrt(@scaley * @scalex)/27
    end
    
    labelgroup = entities.add_group
    labelgroup.layer = layer
    labelgroup.material = material
    label = labelgroup.entities

    label.add_3d_text(name,
                      TextAlignLeft,
                      "Arial",
                      is_bold = true,
                      is_italic = false,
                      letter_height,
                      tolerance = 0.5,
                      z = height,
                      is_filled = true,
                      extrusion = 0.0)
    t = Geom::Transformation.translation(_position)
    labelgroup.move! t
  end #def draw_label

  def router_path
    Sketchup.set_status_text "Machining", SB_PROMPT

    entities = @model.entities

    @wafer_paths=[]

    if @cutDiameter == 0
      @wafer_objects.each do |object|
        @wafer_paths.push(object)
      end
      return
    end

    @wafer_objects.each do |object|
      wafer_path=[]
      firstLine = nil
      lastLine = nil

      Sketchup.set_status_text "Machining: #{@wafer_paths.length}/#{@wafer_objects.length}", SB_PROMPT

      # This logic only works for loops.
      # ie, when the line starts and finishes in the same place.
      loop = (object[0] == object.last)
      if loop
        puts("Loop #{@wafer_paths.length}")
      else
        puts("Not loop. Starts: #{object[0].inspect} Ends: #{object.last.inspect}")
        # Push empty path and skip to next object.
        @wafer_paths.push(wafer_path)
        next
      end #if

      # Work out which side of the edge the endmill should gut on.
      # Since the method used is prone to false positives/negatives, take the
      # average result for every edge in the shape.
      outsideInsideTotal = 0.0
      lastPoint = nil
      object.each do |point|
        if lastPoint != nil
          pathVect = Geom::Vector3d.new(lastPoint.x - point.x,
                                        lastPoint.y - point.y,
                                        0)
          # Right angles to pathVect, length of @cutDiameter / 2 (radius).
          offsetVect = Geom::Vector3d.new(pathVect.y, -pathVect.x, 0)
          if offsetVect.length == 0
            puts("offsetVect.length == 0")
            next
          end
          offsetVect.length = @cutDiameter / 2

          # Get a point on the cutting path.
          midPoint = Geom::Point3d.linear_combination(0.5, lastPoint, 0.5, point)
          midPath = midPoint.offset(offsetVect)
          midPath.z = @height

          # Check if the cutting path should be inside or outside the current
          # geometry for this point by seing how many shapes it is inside.
          # Nested shapes will alter the result once for each shape.
          oi = 1
          @wafer_objects.each do |object2|
            if Geom.point_in_polygon_2D(midPath, object2, false)
              oi *= -1
            end #if
          end
          outsideInsideTotal += oi
        end #lastPoint != nil
        lastPoint = point
      end
      outsideInside = outsideInsideTotal / object.length

      # MV to correct offset bug; Eventually may use a if >0 then 1, if <0 then -1
      outsideInside = outsideInside.round()

      lastPoint = nil
      object.each do |point|
        if lastPoint != nil
          pathVect = Geom::Vector3d.new(lastPoint.x - point.x,
                                        lastPoint.y - point.y,
                                        0)

          # Right angles to pathVect, length of @cutDiameter / 2 (radius).
          offsetVect = Geom::Vector3d.new(pathVect.y, -pathVect.x, 0)
          if offsetVect.length == 0
            puts("offsetVect.length == 0")
            next
          end
          offsetVect.length = @cutDiameter / 2

          # Get a point on the cutting path.
          offsetVect.length *= outsideInside
          pathPoint = point.offset(offsetVect)
          pathPoint.z = @height

          line = [pathPoint, pathVect]

          if firstLine.nil?
            firstLine = line
          else
            centerpoint = Geom.intersect_line_line(lastLine, line)
            if centerpoint
              wafer_path.push(centerpoint)
            else
              puts("Could not find intersection between #{lastLine} and #{line}")
            end #if centerpoint
          end #if firstLine == nil

          lastLine = line
        end #if lastPoint
        lastPoint = point
      end #@point.each

      centerpoint = Geom.intersect_line_line(lastLine, firstLine)
      if centerpoint
        wafer_path.push(centerpoint)
      else
        puts("Could not find intersection between #{firstLine} and #{lastLine}")
      end #if centerpoint

      if wafer_path[0] != wafer_path.last
        wafer_path.push(wafer_path[0])
      end

      @wafer_paths.push(wafer_path)
    end #@wafer_objects.each
  end #router_path

  def deactivate(view)
    Sketchup::set_status_text("",SB_PROMPT)
    Sketchup::set_status_text("",SB_VCB_LABEL)
    Sketchup::set_status_text("",SB_VCB_VALUE)
  end #deactivate

end #class Wafer

unless file_loaded?(__FILE__)
  menu = UI.menu('Tools')
  menu.add_item('Generate Gcode') { Sketchup.active_model.select_tool Wafer.new }
  file_loaded(__FILE__)
end
