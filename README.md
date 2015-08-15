# btrfs_snapshot_rotate
Take btrfs snapshots and rotate them out based on a retention policy.

![example output](http://markmcb.com/wp-content/uploads/2015/08/btrfs_rotate.png)

This is a lightweight alternative to [tools like snapper](http://snapper.io/). It was built with a simple use case in mind: run the script with a daily cron job, and let the script evaluate what needs to be done.

Script requires ruby gem 'colorize', install with:

``gem install colorize``

Example cron setup to run the script nightly at 2am:

``0 2 * * * ruby /root/btrfs_snapshot_rotate.rb -y > /dev/null 2>&1``
