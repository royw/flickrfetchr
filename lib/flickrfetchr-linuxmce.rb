# == Synopsis
# Encapsulate LinuxMCE specifics as a plugin.
#
# == Details
# The plugin is expected to respond to these messages:
#  new(config)
#  pre_download(filespec)
#  post_download(filespec)
#  on_download_error(filespec)
#  self.finish(config)
# 
class LinuxMCE_Plugin
  LINUXMCE_FLICKR_HOME = '/home/flickr'
  LINUXMCE_FLICKR_SYM_HOME = '/home/public/data/pictures/flickr'
  LINUXMCE_FLICKR_START_FILE = '/var/flickr_start'
  LINUXMCE_MESSAGE_SEND_BINARY = '/usr/pluto/bin/MessageSend'
  PLUTO_MAIN_DB = "DBI:Mysql:pluto_main:localhost"
  PLUTO_MEDIA_DB = "DBI:Mysql:pluto_media:localhost"
  
  # Permit changing by unit tests
  attr_accessor :flickr_home_dir, :flickr_symlinked_dir, :flickr_start_file, 
                :pluto_main_db, :pluto_media_db
  attr_reader :message_send_binary

  # Given the application's configuration Hash (uses :logger, :pretend)
  # config:: is the application's config hash.
  def initialize(config)
    @config = config
    @logger = config[:logger]

    # Set up "constants" that should not be changed in normal usage, but
    # may be changed by unit tests
    @flickr_home_dir = LINUXMCE_FLICKR_HOME
    @flickr_symlinked_dir = LINUXMCE_FLICKR_SYM_HOME
    @flickr_start_file = LINUXMCE_FLICKR_START_FILE
    @pluto_main_db = PLUTO_MAIN_DB
    @pluto_media_db = PLUTO_MEDIA_DB
    @message_send_binary = LINUXMCE_MESSAGE_SEND_BINARY

    # Is_dcerouter means we are running on a dcerouter so have access
    # to the linuxmce databases and /usr/pluto/bin/* utilities.
    @is_dcerouter = File.exists?(@message_send_binary)
  end

  # This should be called immediately prior to downloading the file so
  # we can set up a lock to prevent UpdateMedia from accessing the
  # file until we are ready.
  # filespec:: the destination path for the photo
  def pre_download(filespec)
    @config[:logger].debug {"LinuxMCE_Plugin pre_download(#{filespec})"}
    lock filespec
  end
  
  # This should be called after downloading a photo so for LinuxMCE we can make
  # thumbnail, resize the file, and register it with the database and DCE router.
  # filespec:: the destination path for the photo
  def post_download(filespec)
    @config[:logger].debug {"LinuxMCE_Plugin post_download(#{filespec})"}
    thumbnail filespec
    activate_image filespec
  end
  
  # This should only be called on download error so we can remove the
  # lock.
  # filespec:: the destination path for the photo
  def on_download_error(filespec)
    @config[:logger].debug {"LinuxMCE_Plugin on_download_error(#{filespec})"}
    remove_lock filespec
  end
  
  # This should be called after all photos are downloaded so we can delete
  # any old photos beyond the max_flickr_files limit.
  # config:: is the application's config hash.
  def self.finish(config)
    config[:logger].debug {"LinuxMCE_Plugin.finish"}
    linuxmce = new(config)
    # call protected methods
    linuxmce.send :cleanup_flickr
    linuxmce.send :enable_using_flickr_images
  end
  
protected

  # Set the message_send_binary file.  This is used by unit tests
  # to mock running on a DCErouter.
  # filespec:: the path to the message send program
  # Returns:: true if the given file exists
  def message_send_binary=(filespec)
    @message_send_binary = filespec
    @is_dcerouter = File.exists?(@message_send_binary)
  end

  # Lock the given file on a DCE router by creating a filespec.lock file
  # filespec:: the path to the file to lock
  def lock(filespec)
    if @is_dcerouter
      run("touch \"#{filespec}.lock\"")
    end
  end

  # Remove the lock on the given file by deleting the filespec.lock file
  # filespec:: the path to the file to unlock
  def remove_lock(filespec)
    File.delete "#{filespec}.lock" if File.exists? "#{filespec}.lock"
  end

  # Create a thumbnail for the given image file
  # filespec:: the path to the file to create a thumbnail of.
  def thumbnail(filespec)
    if @is_dcerouter
      cmd = "convert \"#{filespec}\" -sample \"75x75\" \"jpeg:#{filespec}.tnj\""
      run(cmd)
    end
  end

  # Register the given image file with the DCE router.
  # filespec:: the path to the image file to activate with the DCE router.
  #
  # WARNING: there is a loop that requires a response from the DCE router
  # to exit and there is not a watch dog on the loop.
  def activate_image(filespec)
    if @is_dcerouter
      # change filespec path from /home/flickr/* to /home/public/data/pictures/flickr/*
      destination = filespec.gsub(/^#{@flickr_home_dir}/, @flickr_symlinked_dir)
      cmd = "/usr/pluto/bin/MessageSend dcerouter -targetType template -r -o 0 2 1 819 13 \"#{destination}\""
      sleep 1
      res = run(cmd)
      while(res =~ /Cannot communicate with router/) do
        @logger.info {"Waiting for router to come up"}
        sleep 10
        res = run(cmd)
      end
      remove_lock filespec

      res.gsub!(/\n/, '')
      out = res.split(/:/)

      # second message send
      run("/usr/pluto/bin/MessageSend dcerouter -targetType template -r -o 0 2 1 391 145 \"#{out[2]}\" 122 30 5 \"*\"")
    end
  end

  # Retrieve the mysql database user name and password from the ~/.my.cnf file if it exists.
  # home_dir:: the user's home directory, defaults to ENV['HOME']
  #
  # Note, on a LinuxMCE system, the database user is "root" and a password is not used.  
  # This is here mainly to support my development workstation which does require a password.
  def credentials(home_dir=ENV['HOME'])
    password = nil
    credential_filename = File.join(home_dir, '.my.cnf')
    if File.exists? credential_filename
      IO.foreach(credential_filename) {|line| password = $1 if line =~ /^password=(\S+)/}
    end
    ['root', password].compact
  end
  
  # Find existing flickr image files.  Used by delete_old_images.
  # Returns:: Array of [filename String, last modified Time]
  def find_existing_images
    images = []
    Dir.glob(File.join(@flickr_home_dir, '**/*.jpg')).each do |filename|
      images << [filename, File.mtime(filename)]
    end
    images
  end
  
  # Delete the eldest images that exist beyond the max_files limit.  For example,
  # if there are 123 images and max_files is 100, then delete the oldest 23 files.
  # dbh:: open database handle
  # images:: Array of [filename String, last modified Time] (output of find_existing_images)
  # max_files:: the maximum number of images to keep on the system.
  def delete_old_images(dbh, images, max_files)
    # sort by date then reverse and grab the oldest max_files images to delete
    images.sort{|a,b| a[1] <=> b[1]}.reverse[max_files..-1].each do |img|
      filespec = img[0]
      id3_filespec = filespec + '.id3'
      @logger.debug {"deleting eldest file: #{filespec} #{img[1].to_s}"}
      unless @config[:pretend]
        File.delete filespec if File.exists? filespec
        mark_file_as_deleted(dbh, filespec)
        File.delete id3_filespec if File.exists? id3_filespec
      end
    end
  end
  
  # Linuxmce has a finite limit on the number of flickr images, so
  # let's find the oldest images beyond the max # of images limit
  # and delete them
  def cleanup_flickr
    if @is_dcerouter
      # remove any excess flickr image files from the linuxmce system
      @logger.info {"Cleanup LinuxMCE flickr images"}
      begin
        dbh = DBI.connect(@pluto_media_db, *credentials)
        images = find_existing_images()
        max_files = max_flickr_files()
        @logger.info {"Limiting to #{max_files} flickr images"}
        if images.length > max_files
          delete_old_images(dbh, images, max_files)
        end
      rescue Exception => eMsg
        @logger.error {eMsg.to_s}
        @logger.debug {eMsg.backtrace.join("\n")}
      ensure
        dbh.disconnect if dbh
      end
      sleep 1
      run("/usr/pluto/bin/MessageSend dcerouter -targetType template 0 1825 1 606")
      @logger.info {"Cleanup completed"}
    end
  end
  
  # Inform the database that we deleted an image file
  # dbh:: open database handle
  # filespec:: deleted image path
  def mark_file_as_deleted(dbh, filespec)
    if @is_dcerouter
      begin
        statement = "UPDATE File SET Missing = 1 WHERE Filename='#{File.basename(filespec)}'"
        dbh.execute(statement)
      rescue => eMsg
        @logger.error {eMsg.to_s}
        @logger.debug {eMsg.backtrace.join("\n")}
      end
    end
  end
  
  # Find the maximum number of flickr images we should keep on the system.
  # Returns:: the maximum number of images to keep on the system.
  def max_flickr_files
    max_files = 100 # sane default
    if @is_dcerouter
      begin
        dbh = DBI.connect(@pluto_main_db, *credentials)
        statement = %w(
          SELECT  IK_DeviceData
          FROM    Device_DeviceData
                  INNER JOIN Device ON Device_DeviceData.FK_Device = Device.PK_Device
          WHERE   Device_DeviceData.FK_DeviceData=177
                  AND
                  Device.FK_DeviceTemplate = 12
        ).join(' ')
        sth = dbh.execute(statement)
        row = sth.fetch
        max_files = row['IK_DeviceData'].to_i
      rescue => eMsg
        @logger.error {eMsg.to_s}
        @logger.debug {eMsg.backtrace.join("\n")}
      end
    end
    max_files
  end

  # If we have at least 20% of max_flickr_files downloaded, then indicate so in
  # the /var/flickr_start file by writing 'Pictures downloaded' into it.
  def enable_using_flickr_images
    if @is_dcerouter
      if Dir.glob(File.join(@flickr_home_dir,'**/*.jpg')).length >= ((20 * max_flickr_files) / 100).floor
        File.open(@flickr_start_file, "w") {|file| file.print 'Pictures downloaded' }
      end
    end
  end

private

  # Run the given command line.  Handles debug logging and pretending.
  def run(cmd)
    res = ''
    @logger.debug {cmd}
    unless @config[:pretend]
      res = `#{cmd}`
      @logger.debug {res}
    end
    res
  end

end

