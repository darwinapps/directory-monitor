#!/usr/bin/perl

use strict;
use warnings;

my $notifier = Notifier->new();
   $notifier->start();

package Notifier;

use Getopt::Long;
use IO::Select;

use Errno qw/EWOULDBLOCK/;

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

    warn "No recipient specified, no email alerts will be sent\n" unless $self->{to};
    die "No directory specified\n" unless $self->{directory} && -d $self->{directory};
    die sprintf "inotifywait not found at %s\n", $self->{inotifywait} unless $self->{inotifywait} && -x $self->{inotifywait};
    die sprintf "sendmail not found at %s\n", $self->{sendmail} unless $self->{sendmail} && -x $self->{sendmail};
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
