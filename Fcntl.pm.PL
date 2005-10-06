use ExtUtils::CBuilder 0.07;

my $builder = ExtUtils::CBuilder->new() or die "Can't create an Extutils::CBuilder\n";
my $obj_file = $builder->compile(source => 'lockdefs.c') or die "Can't compile lockdefs\n";
my $exe_file = $builder->link_executable(objects => $obj_file) or die "Can't link lockdefs\n";
$exe_file = "./$exe_file" unless $exe_file =~ m|^/|;

open(STDIN, "<", $0) or die "Can't open $0: $!\n";
open(STDOUT, ">,Fcntl.pm") or die "Can't write temp file: $!\n";
print STDERR "$exe_file\n";
system("$exe_file") and die "Can't run lockdefs: $!\n";
rename(",Fcntl.pm", "Fcntl.pm");
exit 0;

__DATA__
#   -*- Perl -*-
#   Proc::PID::File::Fcntl - pidfile manager
#   Copyright (C) 2005 Proofpoint, Inc.
#
#   This program is free software; you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program; if not, write to the Free Software
#   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
#

package Proc::PID::File::Fcntl;

=head1 NAME

Proc::PID::File::Fcntl - Manage PID files using fcntl() locks

=head1 SYNOPSIS

  use Proc::PID::File::Fcntl;
  my $pidfile = new Proc::PID::File::Fcntl;

=head1 DESCRIPTION

This Perl module permits callers to prevent multiple simultaneous
instantiations of themselves.  The module accomplishes this using a
I<pidfile>, which is used to obtain a lock.

Unlike the traditional I<pidfile> locking protocol, which uses the
existence and content of the file to indicate the lock, this module
uses fcntl() locking of the file.  This locking protocol is free of
races and, assuming the lock file is not in a networked filesystem, is
safe across OS crashes.

=head1 METHODS

=cut

use strict;
use warnings;
use POSIX qw(F_SETLK F_GETLK O_RDWR O_CREAT);

our $VERSION = "0.01";

FLOCK_DEFS

=head2 $pidfile = Proc::PID::File::Fcntl->new( { opt => val, ... } )

Creates and locks a new I<pidfile>, returning an object holding the
lock.  When the returned object goes out of scope, the lock is
released.

Calls C<die> if the file cannot be opened or is locked by another process.

Must not be called when the calling process already has a lock on the
I<pidfile>, otherwise that lock will be released.

The options available include the following:

=over

=item I<path>

Specifies the path name of the I<pidfile>.  Defaults to I<$0>.  If the
value does not start with F</> then F</var/run/> is prepended.  If the
value does not end with F<.pid> then F<.pid> is appended.

=back

=cut

sub new ($) {
    my $self = bless({}, shift);
    %$self = @_;

    $self->{path} = $0 unless defined($self->{path});
    $self->{path} = "/var/run/".$self->{path} unless $self->{path} =~ m|^/|;
    $self->{path} .= '.pid' unless $self->{path} =~ /\.pid$/;
    
    my $fd;

    do {
	sysopen($fd, $self->{path}, O_RDWR|O_CREAT)
	    || die "Cannot open pid file $self->{path}: $!\n";

	my $flock = $_flock_init;
	fcntl($fd, F_SETLK, $flock) || die "pidfile ".$self->{path}." already locked\n";
    } while ( (stat($self->{path}))[1] != (stat $fd)[1] );

    my $data = "$$\n";
    syswrite $fd, $data, length($data);

    $self->{fd} = $fd;
    $self->{pid} = $$;
    return $self;
}

=head2 $pid = Proc::PID::File::Fcntl::getlocker( { opt => val, ... } )

Returns the PID of the process holding the lock on a I<pidfile> or
C<0> if there is no such process.

Must not be called when the calling process already has a lock on the
I<pidfile>, otherwise that lock will be released.

The options available include the following:

=over

=item I<path>

Specifies the path name of the I<pidfile>.  Defaults to I<$0>.  If the
value does not start with F</> then F</var/run/> is prepended.  If the
value does not end with F<.pid> then F<.pid> is appended.

=back

=cut

sub getlocker {
    my ($class, $path) = @_;
    die "Must be called as class method" if ref($class);

    $path = $0 unless defined($path);
    $path = "/var/run/".$path unless $path =~ m|^/|;
    $path .= '.pid' unless $path =~ /\.pid$/;
    
    sysopen(my $fd, $path, O_RDWR) || return 0;

    my $flock = $_flock_init;
    fcntl($fd, F_GETLK, $flock);
    return unpack $_flock_pid_template, $flock;
}

sub DESTROY {
    my $self = shift;
    if ($self->{fd} && ($$ == $self->{pid})) {
	# Must unlink BEFORE releasing lock, otherwise we might unlink
	# some other process's file
	unlink $self->{path};
	delete $self->{fd};
    }
}

=head1 AUTHOR

John Gardiner Myers <jgmyers@proofpoint.com>

=head1 SUPPORT

For help and thank you notes, e-mail the author directly.  To report a
bug, submit a patch, or add to the wishlist please visit the CPAN bug
manager at: F<http://rt.cpan.org>

=cut

1;
