# btrfs_snapshot_rotate
Take btrfs snapshots and rotate them out based on a retention policy.

![example output](http://markmcb.com/wp-content/uploads/2015/08/btrfs_rotate.png)

This is a lightweight alternative to [tools like snapper](http://snapper.io/). It was built with a simple use case in mind: run the script with a daily cron job, and let the script evaluate what needs to be done.

## Install

Copy the ``btrfs_snapshot_rotate.rb`` file to your preferred location. You will need ruby to run it. You can either do this by calling ``ruby /your/path/to/btrfs_snapshot_rotate.rb`` or make it executable ``chmod +x /your/path/to/btrfs_snapshot_rotate.rb`` and execute it directly.

Script requires ruby gem 'colorize', install with:

``gem install colorize``

## Configure

There are a few configuration lines you should edit. Use your favorite text editor to open and edit ``btrfs_snapshot_rotate.rb``. 

	BtrfsCommand = '/usr/sbin/btrfs'
	SnapshotConfigurations = [
		{
			full_paths_to_mount: ['/mnt/btrfs-store-root'],
			full_path_of_source_subvolume: '/mnt/btrfs-store-root/store',
			full_path_of_snapshot_directory: '/mnt/btrfs-store-root',
			snapshot_filename_prefix: 'store-snapshot',
			keep: { days: 14, weeks: 10, day_of_week: "Monday", months: 12, years: 5 }
		}
	]

1. **BtrfsCommand**: this is where the btrfs executable is installed on your system. If you don't know, type ``which btrfs`` and copy the result
2. **SnapshotConfigurations**: this contains one or more sets of attributes about your snapshots
  * *full_paths_to_mount*: if any path isn't normally mounted, you can note the path(s) and it will be mounted before started and dismounted after. An empty array ``[]`` will skip all mount/umount operations
  * *full_path_of_source_subvolume*: the subvolume you want to snapshot
  * *full_path_of_snapshot_directory*: where you store your snapshots
  * *snapshot_filename_prefix*: this string will be the filename prefix. A value of 'mysnapshot' will result in files that looks like 'mysnapshot-YYYY-MM-DD' (where YYYY-MM-DD is the date of the snapshot).
  * *keep*: number of days, weeks, months, and years of snapshots to keep. For weeks, you need to specify a day of the week to keep, e.g., "Monday"

You can add as many snapshot configurations as you'd like, for example, to snapshot two separate subvolumes:

	BtrfsCommand = '/usr/sbin/btrfs'
	SnapshotConfigurations = [
		{
			full_paths_to_mount: ['/mnt/btrfs-store-root'],
			full_path_of_source_subvolume: '/mnt/btrfs-store-root/store',
			full_path_of_snapshot_directory: '/mnt/btrfs-store-root',
			snapshot_filename_prefix: 'store-snapshot',
			keep: { days: 14, weeks: 10, day_of_week: "Monday", months: 12, years: 5 }
		},
		{
			full_paths_to_mount: [],
			full_path_of_source_subvolume: '/',
			full_path_of_snapshot_directory: '/.root-snapshots',
			snapshot_filename_prefix: 'root-snapshot',
			keep: { days: 7, weeks: 8, day_of_week: "Monday", months: 4, years: 0 }
		}
	]

## Cron

This is an example cron setup to have the root user run the script nightly at 2am:

``crontab -e``

And add the following line:

``0 2 * * * ruby /root/btrfs_snapshot_rotate.rb -y > /dev/null 2>&1``
