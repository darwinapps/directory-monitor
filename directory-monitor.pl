#!/usr/bin/perl

use strict;
use warnings;


my $notifier = Notifier->new();
   $notifier->start();

package Notifier;

use Getopt::Long;
use IO::Select;
use Pod::Usage;

use Errno qw/EWOULDBLOCK/;

=pod

=head1 NAME

    ./directory-monitor.pl

=head1 SYNOPSIS

    ./directory-monitor.pl -d /var/www/html/

        -d|--directory             required, directory to monitor

        -e|--exclude <pattern>     optional, exclude all events on files
                                   matching the perl-compatible regular
                                   expression <pattern>, multiple excludes
                                   allowed

        -i|--interval <interval>   optional, interval, after which all events
                                   are reported in a batch useful when
                                   notifications are sent by email,
                                   default value is 60

        -t|--to <email>            optional, email address to send
                                   notifications

        -s|--subject <subject>     optional, subject of the email, default value
                                   is 'Filesystem modified at ' . hostname

        --inotifywatch <path>      optional, path to binary inotifywatch,
                                   if different from /usr/bin/inotifywatch

        --sendmail <path>          optional, path to binary sendmail,
                                   if different from /usr/sbin/sendmail

=head1 DESCRIPTION

    directory-monitor is a boilerplate script, that DarwinApps uses for monitoring filesystem changes.

=head1 AUTHOR

    Aleksandr Guidrevitch <aguidrevitch@darwinapps.com>

=head1 SEE ALSO

    inotifywait (from inotify-tools), sendmail

=cut

sub new {
    my $class = shift;
    chomp(my $hostname = `hostname -f`);

    return bless {
        'interval' => 60,
        'subject' => sprintf('Filesystem modified at %s', $hostname),
        'to' => undef,
        'directory' => undef,
        'inotifywait' => '/usr/bin/inotifywait',
        'exclude' => [],
        'sendmail' => '/usr/sbin/sendmail',
        'collected' => '',
        'partial' => ''
    }, $class;
}

sub usage {
    my $self = shift;
    my $warning = sprintf shift, @_;
    warn $warning;
    pod2usage(
        -verbose => 1,
        -exitval => 1
    );
}

sub getopts {
    my $self = shift;

    GetOptions(
        "t|to=s" => \$self->{to},
        "d|directory=s" => \$self->{directory},
        "e|exclude=s@" => \$self->{exclude},
        "i|interval=i"  => \$self->{interval},
        "s|subject=s" => \$self->{subject},
        "inotifywait=s" => \$self->{inotifywait},
        "sendmail=s" => \$self->{sendmail},
    );

    warn $self->stamp("No recipient specified, no email alerts will be sent\n") unless $self->{to};
    $self->usage("No directory specified\n") unless $self->{directory} && -d $self->{directory};
    $self->usage("inotifywait not found at %s\n", $self->{inotifywait}) unless $self->{inotifywait} && -x $self->{inotifywait};
    $self->usage("sendmail not found at %s\n", $self->{sendmail}) unless $self->{sendmail} && -x $self->{sendmail};
}

sub stamp {
    my $self = shift;
    my $format = shift || '';
    return sprintf "[%s] " . $format, scalar localtime, @_;
}

sub flush {
    my $self = shift;
    my $signal = shift;

    return unless $signal || $self->{collected};

    my ($out, $err) = ('', '');

    if ($signal) {
        my @err;
        push @err, $self->stamp("Got %s", $signal);
        push @err, map { $self->stamp($_) } @_ if @_;
        $err = join "\n", @err, '' if @err;
    }

    if ($self->{collected}) {
        $out = $self->{collected};
        $self->{collected} = '' ;
    }

    if ($self->{partial}) {
        $out .= $self->stamp($self->{partial}) . " -- \n";
        $self->{partial} = '' ;
    }

    warn $err if $err;
    print $out if $out;

    if ($self->{to}) {
        open my $mail, sprintf("| %s -t", $self->{sendmail}) or die $!;
        printf $mail "To: %s\n", $self->{to};
        printf $mail "Subject: %s\n\n", $self->{subject};
        printf $mail $err if $err;
        printf $mail $out if $out;
        close $mail;
    }
}

sub filter {
    my $self = shift;
    my @filtered;
    foreach my $line (@_) {
        push @filtered, $line unless grep { $line =~ qr($_) } @{ $self->{exclude} };
    }
    return @filtered;
}

sub start {
    my $self = shift;

    $| = 1;

    $self->getopts();

    $SIG{USR1} = $SIG{HUP} = sub {
        $self->flush(@_);
    };

    $SIG{INT} = $SIG{TERM} = $SIG{__DIE__} = sub {
        $self->flush(@_);
        exit;
    };

    (my $directory = $self->{directory}) =~ s/\"/\\\"/g;

    my $cmd = sprintf '%s -q -m -r -e modify -e create -e moved_to -e close_write --format "%%:e %%w%%f" "%s" |', $self->{inotifywait}, $directory;
    open my $in, $cmd or die $!;

    my $s= IO::Select->new();
    $s->add(\*$in);

    warn $self->stamp("Monitoring of %s started\n", $self->{directory});

    my $last_received_time = time();
    while (1) {
        if ($s->can_read(.01)) {
            my $data;
            my $rc = sysread($in, $data, 8192);
            if ($rc > 0) {
                my @lines = split /\n/, $self->{partial} . $data;
                $self->{partial} = $data =~ /\n$/ ? '' : pop @lines;
                @lines = $self->filter(@lines);
                $self->{collected} .= join "\n", map ($self->stamp($_), @lines), "" if @lines;
                #warn $self->{collected} . ":" . $self->{partial};
                $last_received_time = time();
            } elsif ($! == EWOULDBLOCK) {
                next;
            } elsif ($!) {
                die $!;
            }
        } elsif ($last_received_time + $self->{interval} < time()) {
            $self->flush();
        }
    }
}

