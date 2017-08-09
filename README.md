# directory-monitor

**directory-monitor** is a boilerplate script, that DarwinApps uses for monitoring filesystem changes. 

It depends on:

* inotifywait (from inotify-tools package)
* sendmail 

Usage:

```sh
$ ./directory-monitor.pl -d /var/www/html
```

Command-line Options:

```
    -d|--directory             required, directory to monitor

    -e|--exclude <pattern>     optional, exclude all events on files matching the
                               perl-compatible regular expression <pattern>
                               multiple excludes allowed

    -i|--interval <interval>   optional, interval, after which all events are reported
                               in a batch useful when notifications are sent by email,
                               default value is 60

    -t|--to <email>            optional, email address to send notifications

    -s|--subject <subject>     optional, subject of the email, default value is
                               sprintf('Filesystem modified at %s', $hostname)

    --inotifywatch <path>      path to binary inotifywatch,
                               if different from /usr/bin/inotifywatch

    --sendmail <path>          path to binary sendmail,
                               if different from /usr/sbin/sendmail

```
