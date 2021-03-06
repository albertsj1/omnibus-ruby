#
# Copyright 2014 Chef Software, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

module Omnibus
  class Packager::MacDmg < Packager::Base
    attr_reader :packager

    validate do
      assert_presence!(resource('background.png'))
      assert_presence!(resource('icon.png'))
    end

    setup do
      create_directory(dmg_stage)
      purge_directory(staging_resources_path)
      copy_directory(resources_path, staging_resources_path)

      remove_file(writable_dmg)
      clean_disks
    end

    build do
      copy_assets_to_dmg
      create_writable_dmg
      attach_dmg
      # Give some time to the system so attached dmg shows up in Finder
      sleep 5
      set_volume_icon
      prettify_dmg
      compress_dmg
      set_dmg_icon
    end

    clean do
      remove_file("#{staging_dir}/tmp.icns")
      remove_file("#{staging_dir}/tmp.rsrc")
    end

    #
    # Create a new DMG packager.
    #
    # @param [Packager::MacPkg] mac_packager
    #
    def initialize(mac_packager)
      @packager = mac_packager
      super(mac_packager.project)
    end

    #
    # Cleans any previously left over mounted disks
    #
    def clean_disks
      # We're trying to detach disks that look like below:
      # /dev/disk1s1 on /Volumes/chef (hfs, local, nodev, nosuid, read-only, noowners, quarantine, mounted by serdar)
      # /dev/disk2s1 on /Volumes/chef 1 (hfs, local, nodev, nosuid, read-only, noowners, quarantine, mounted by serdar)
      existing_disks = execute "mount | grep /Volumes/#{project.name} | awk '{print $1}'"
      existing_disks.stdout.lines.each do |existing_disk|
        existing_disk.chomp!
        Omnibus.logger.debug { "Detaching disk '#{existing_disk}' before starting dmg packaging." }
        execute "hdiutil detach #{existing_disk}"
      end
    end

    #
    # Copy the assets in the local omnibus project into a staging folder that
    # will soon become our writable dmg.
    #
    def copy_assets_to_dmg
      # Copy the compiled pkg into the dmg
      copy_file(packager.final_pkg, "#{dmg_stage}/#{project.name}.pkg")

      # Copy support files
      support = create_directory("#{dmg_stage}/.support")
      copy_file(resource('background.png'), "#{support}/background.png")
    end

    #
    # Create a writable dmg we can put assets on.
    #
    def create_writable_dmg
      execute <<-EOH.gsub(/^ {8}/, '')
        hdiutil create \\
          -srcfolder "#{dmg_stage}" \\
          -volname "#{project.name}" \\
          -fs HFS+ \\
          -fsargs "-c c=64,a=16,e=16" \\
          -format UDRW \\
          -size 512000k \\
          "#{writable_dmg}"
      EOH
    end

    #
    # Attach the dmg, storing a reference to the device for later use.
    #
    def attach_dmg
      @device = execute(<<-EOH.gsub(/^ {8}/, '')).stdout.strip
        hdiutil attach \\
          -readwrite \\
          -noverify \\
          -noautoopen \\
          "#{writable_dmg}" | egrep '^/dev/' | sed 1q | awk '{print $1}'
      EOH
    end

    #
    # Create the icon for the volume using sips.
    #
    def set_volume_icon
      execute <<-EOH.gsub(/^ {8}/, '')
        # Generate the icns
        mkdir tmp.iconset
        sips -z 16 16     #{resource('icon.png')} --out tmp.iconset/icon_16x16.png
        sips -z 32 32     #{resource('icon.png')} --out tmp.iconset/icon_16x16@2x.png
        sips -z 32 32     #{resource('icon.png')} --out tmp.iconset/icon_32x32.png
        sips -z 64 64     #{resource('icon.png')} --out tmp.iconset/icon_32x32@2x.png
        sips -z 128 128   #{resource('icon.png')} --out tmp.iconset/icon_128x128.png
        sips -z 256 256   #{resource('icon.png')} --out tmp.iconset/icon_128x128@2x.png
        sips -z 256 256   #{resource('icon.png')} --out tmp.iconset/icon_256x256.png
        sips -z 512 512   #{resource('icon.png')} --out tmp.iconset/icon_256x256@2x.png
        sips -z 512 512   #{resource('icon.png')} --out tmp.iconset/icon_512x512.png
        sips -z 1024 1024 #{resource('icon.png')} --out tmp.iconset/icon_512x512@2x.png
        iconutil -c icns tmp.iconset

        # Copy it over
        cp tmp.icns "/Volumes/#{project.name}/.VolumeIcon.icns"

        # Source the icon
        SetFile -a C "/Volumes/#{project.name}"
      EOH
    end

    #
    # Use Applescript to setup the DMG with pretty logos and colors.
    #
    def prettify_dmg
      execute <<-EOH.gsub(/ ^{8}/, '')
        echo '
           tell application "Finder"
             tell disk "'#{project.name}'"
               open
               set current view of container window to icon view
               set toolbar visible of container window to false
               set statusbar visible of container window to false
               set the bounds of container window to {#{Config[:dmg_window_bounds]}}
               set theViewOptions to the icon view options of container window
               set arrangement of theViewOptions to not arranged
               set icon size of theViewOptions to 72
               set background picture of theViewOptions to file ".support:'background.png'"
               delay 5
               set position of item "'#{project.name}.pkg'" of container window to {#{Config[:dmg_pkg_position]}}
               update without registering applications
               delay 5
             end tell
           end tell
        ' | osascript
      EOH
    end

    #
    # Compress the dmg using hdiutil and zlib.
    #
    def compress_dmg
      execute <<-EOH.gsub(/ ^{8}/, '')
        chmod -Rf go-w /Volumes/#{project.name}
        sync
        hdiutil detach "#{@device}"
        hdiutil convert \\
          "#{writable_dmg}" \\
          -format UDZO \\
          -imagekey zlib-level=9 \\
          -o "#{final_dmg}"
        rm -rf "#{writable_dmg}"
      EOH
    end

    #
    # Set the dmg icon to our custom icon.
    #
    def set_dmg_icon
      execute <<-EOH.gsub(/^ {8}/, '')
        # Convert the png to an icon
        sips -i "#{resource('icon.png')}"

        # Extract the icon into its own resource
        DeRez -only icns "#{resource('icon.png')}" > tmp.rsrc

        # Append the icon reosurce to the DMG
        Rez -append tmp.rsrc -o "#{final_dmg}"

        # Source the icon
        SetFile -a C "#{final_dmg}"
      EOH
    end

    # @see Base#package_name
    def package_name
      "#{project.name}-#{project.build_version}-#{project.iteration}.dmg"
    end

    # The path to the folder that we should stage.
    #
    # @return [String]
    def dmg_stage
      File.expand_path("#{staging_dir}/dmg")
    end

    # The path to the writable dmg on disk.
    #
    # @return [String]
    def writable_dmg
      File.expand_path("#{staging_dir}/#{project.name}-writable.dmg")
    end

    # The path where the final dmg will be produced.
    #
    # @return [String]
    def final_dmg
      File.expand_path("#{Config.package_dir}/#{project.name}-#{project.build_version}-#{project.iteration}.dmg")
    end
  end
end
