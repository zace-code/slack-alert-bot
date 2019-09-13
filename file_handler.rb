require 'yaml'
require 'google_drive'

# our drive filename
FileName = 'Slack Bright Ideas'

# our config filenames
BotConf = ARGV.first || 'config.yml'
DriveConf = 'google-drive-credentials.json'

GDrive = GoogleDrive::Session.from_config(DriveConf)
GDFile = GDrive.file_by_title(FileName)
IdeaTemplate = %(----------------------------------------
%s: %s
(permalink: %s))

GDFile.download_to_file("./#{FileName}.txt") unless File.exists? "#{FileName}.txt"

# appends our new idea to our google doc
def add_to_doc idea
  GDFile.update_from_string(
    append_idea(IdeaTemplate % [idea[:user],
                                idea[:message],
                                idea[:link]] ))
end

# appends our new idea to our local file
def append_idea idea
  open("#{FileName}.txt", 'a') do |file|
    file.puts idea
  end

  File.read("#{FileName}.txt")
end

# load our config 
def load_config
  YAML.load(File.read(BotConf)) if File.exists? BotConf
end

