#!/usr/bin/ruby
# Rolling btrfs backup and analysis. 
# Tested with Ruby 2.2

require 'date'
require 'optparse'
require 'colorize' 

# Snapshot configuration sets. An array of hashed information describing different 
# subvolumes to snapshot.
SnapshotConfigurations = [
	{
		# array of mount points. Path must be in /etc/fstab with mount options.
		# All mounts listed will be unmounted when the script completes.
		# If everything is already mounted, leave an empty array, i.e, []
		full_paths_to_mount: ['/mnt/btrfs-store-root'],
		full_path_of_source_subvolume: '/mnt/btrfs-store-root/store',
		full_path_of_snapshot_directory: '/mnt/btrfs-store-root',
		snapshot_filename_prefix: 'store-snapshot',
		# Define how many snapshots to keep in different time aggregations
		keep: { days: 14, weeks: 10, day_of_week: "Monday", months: 12, years: 5 }
	}
]
ActionCreate 	= 'create'
ActionReplace   = 'replace'
ActionNotFound 	= '{}'
ActionKeep 		= 'keep'
ActionDelete 	= 'delete'

def prepare_desination(options={})
	mount_points = options[:snapshot_config][:full_paths_to_mount]
	mount_points.each do |mp|
		%x`mount #{mp}`
		if $?.exitstatus == 0
			puts "Mounted #{mp}"
		else
			puts "ERROR: Unable to mount #{mp}. Check /etc/fstab and user permissions. -- Exiting."
			exit
		end
	end
	dest = options[:snapshot_config][:full_path_of_snapshot_directory]
	unless File.exist?(File.expand_path(dest))
		puts "ERROR: The snapshot destination does not exist: #{dest} -- Exiting."
		exit
	end
	unless File.writable?(File.expand_path(dest))
		puts "ERROR: The snapshot destination is not writable by the user executing this process -- Exiting."
		exit
	end
end

def umount_if_needed(options={})
	mount_points = options[:snapshot_config][:full_paths_to_mount]
	mount_points.each do |mp|
		%x`umount #{mp}`
		if $?.exitstatus == 0
			puts "Un-mounted #{mp}"
		else
			puts "ERROR: Unable to umount #{mp} -- Exiting."
			exit
		end
	end
end

def calculate_snapshot_dates_to_keep(options={})
	ssdtk = {}
	date=options[:date]

	# Days
	0.upto(options[:snapshot_config][:keep][:days]-1){|i| ssdtk[(date-i).to_s] = :day unless !ssdtk[(date-i).to_s].nil?}

	# Weeks
	most_recent_weekly_keep_date = nil
	0.upto(6){|d| (most_recent_weekly_keep_date = date-d) if (date-d).send(options[:snapshot_config][:keep][:day_of_week].downcase+'?') }
    ssdtk[most_recent_weekly_keep_date.to_s] = :week unless !ssdtk[most_recent_weekly_keep_date.to_s].nil?
	1.upto(options[:snapshot_config][:keep][:weeks]-1){|d| ssdtk[(most_recent_weekly_keep_date - (d*7)).to_s]=:week unless !ssdtk[(most_recent_weekly_keep_date - (d*7)).to_s].nil?}

	#Months
	first_of_this_month = Date.new(date.year, date.month, 1)
	0.upto(options[:snapshot_config][:keep][:months]-1){|i| ssdtk[(first_of_this_month << i).to_s]=:month unless !ssdtk[(first_of_this_month << i).to_s].nil? }

	#Years
	first_of_this_year = Date.new(date.year, 1, 1)
	0.upto(options[:snapshot_config][:keep][:years]-1){|i| ssdtk[(first_of_this_year << (i*12)).to_s]=:year unless !ssdtk[(first_of_this_year << (i*12)).to_s].nil? }

	puts "Subvolume to snapshot:              #{options[:snapshot_config][:full_path_of_source_subvolume]}"
	puts "Snapshot will be stored in:         #{options[:snapshot_config][:full_path_of_snapshot_directory]}"
	to_keep = (options[:snapshot_config][:keep][:days].to_s+' days,').colorize(color: :red)
	to_keep += ' '+(options[:snapshot_config][:keep][:weeks].to_s+' weeks,').colorize(color: :yellow)
	to_keep += ' '+(options[:snapshot_config][:keep][:months].to_s+' months,').colorize(color: :green)
	to_keep += ' '+(options[:snapshot_config][:keep][:years].to_s+' years').colorize(color: :blue)
	puts "Keep one snapshot for each of last: #{to_keep}"
	return ssdtk
end

def generate_action_list(options={})
	action_list = {}
	# start with snapshots you hope exist, but assume they don't
	options[:unique_snapshot_dates].keys.each{|s| action_list[s]=ActionNotFound}
	# next, note the snapshot we're about to create
	action_list[options[:today].to_s]=ActionCreate
	# last, find existing snapshots and determine if they're to keep or discard
	existing_snapshots = []
	Dir.foreach(File.expand_path(options[:snapshot_config][:full_path_of_snapshot_directory])) do |file|
		existing_snapshots << file if (file =~ /^#{options[:snapshot_config][:snapshot_filename_prefix]}-\d\d\d\d-\d\d-\d\d$/)
	end
	existing_snapshots.each do |es|
		this_es = es[-10,10]
		action_list[this_es] = if options[:unique_snapshot_dates].keys.index(this_es).nil?
			ActionDelete
		elsif this_es == options[:today].to_s
			ActionReplace
		else
			ActionKeep
		end
	end
	columns = 4
	segment_length = (action_list.length.to_f/columns.to_f).ceil
	seg_src = action_list.keys.sort.reverse
	segments = []
	1.upto(columns){|i| segments << seg_src.shift(segment_length)}
	puts "\nSnapshot plan (create/replace/keep/delete/{would keep but doesn't exist}):"
	0.upto(segment_length-1) do |i|
		line = ''
		0.upto(columns-1) do |x| 
			color = case options[:unique_snapshot_dates][segments[x][i]]
			when :day
				:red
			when :week
				:yellow
			when :month
				:green
			when :year
				:blue
			else
				:light_black
			end
			line += segments[x][i].nil? ? '' : (segments[x][i].colorize(color)+': '+action_list[segments[x][i]].colorize(color))
			(line += ' '*(8-action_list[segments[x][i]].length)) unless action_list[segments[x][i]].nil?
		end
		puts '  '+line
	end
 	return action_list
end

def process_action_list(options={})
	keeps = 1
	snaps = options[:action_list].length
	dry_run = options[:process_as].nil? ? true : ((options[:process_as]==:execute) ? false : true)
	dry_run ? (puts "\nThe following commands will be executed:") : (puts "\nExecuting the following commands:")
	options[:action_list].keys.sort.reverse.each do |k| 
		case options[:action_list][k]
		when ActionCreate
			command = "btrfs subvolume snapshot -r #{options[:snapshot_config][:full_path_of_source_subvolume]} #{options[:snapshot_config][:full_path_of_snapshot_directory]}/#{options[:snapshot_config][:snapshot_filename_prefix]}-#{options[:today].to_s}"
			dry_run ? (puts 'CREATE: '+command) : (puts "#{command}"; %x`#{command}`)
		when ActionReplace
			command = "btrfs subvolume delete --commit-after #{options[:snapshot_config][:full_path_of_snapshot_directory]}/#{options[:snapshot_config][:snapshot_filename_prefix]}-#{options[:today].to_s}"
			dry_run ? (puts 'REPLC1: '+command) : (puts "#{command}"; %x`#{command}`)
			command = "btrfs subvolume snapshot -r #{options[:snapshot_config][:full_path_of_source_subvolume]} #{options[:snapshot_config][:full_path_of_snapshot_directory]}/#{options[:snapshot_config][:snapshot_filename_prefix]}-#{options[:today].to_s}"
			dry_run ? (puts 'REPLC2: '+command) : (puts "#{command}"; %x`#{command}`)
		when ActionDelete
			command = "btrfs subvolume delete --commit-after #{options[:snapshot_config][:full_path_of_snapshot_directory]}/#{options[:snapshot_config][:snapshot_filename_prefix]}-#{k}"
			dry_run ? (puts 'DELETE: '+command) : (puts "#{command}"; %x`#{command}`)
			snaps-=1
		when ActionKeep
			keeps+=1
		end
	end
	return ((keeps.to_f / snaps.to_f) * 100.0).round
end

def ask(*args)
    print(*args)
    gets
end

# Main thread

today = Date.today
cli_options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: btrfs_snapshot_rotate.rb [options]"

  opts.on("-v", "--verbose", "Run verbosely") do |v|
    cli_options[:verbose] = v
  end
  opts.on("-y", "--yes", "Execute snapshot plan without confirmation") do |y|
    cli_options[:yes] = y
  end
  opts.on("--no-color", "Do not colorize output") do |c|
    cli_options[:colorize] = false
    class String
      def colorize(x)
         self
      end
    end
  end
  opts.on("-h", "--help", "Prints this help") do
    puts opts
    exit
  end
end.parse!

SnapshotConfigurations.each do |snapshot_config|
	prepare_desination(snapshot_config: snapshot_config)
	unique_snapshot_dates = calculate_snapshot_dates_to_keep(snapshot_config: snapshot_config, date: today)
	action_list = generate_action_list(snapshot_config: snapshot_config, today: today, unique_snapshot_dates: unique_snapshot_dates)
	process_action_list(process_as: :dry_run, snapshot_config: snapshot_config, action_list: action_list, today: today)
	unless cli_options[:yes]
        	response = ask "\nProceed? Y[n] "
	end
	if (cli_options[:yes]) || (response.chomp == "Y")
		percentage_complete = process_action_list(process_as: :execute, snapshot_config: snapshot_config, action_list: action_list, today: today)
		puts "#{percentage_complete}% of desired snapshots exist."
	else
		puts "No actions taken. Exiting."
	end
	umount_if_needed(snapshot_config: snapshot_config)
        puts "Complete!\n\n"
end
