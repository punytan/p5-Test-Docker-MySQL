package Test::Docker::MySQL;
use strict;
use constant DEBUG => $ENV{DEBUG_TEST_DOCKER_MYSQL};
our $VERSION = '0.01';
use DBI;
use IPC::Run ();
use Time::HiRes 'sleep';

sub WARN {
    my $msg = join " ",  @_;
    chomp $msg;
    warn sprintf "[%s %.5f] %s\n", __PACKAGE__, Time::HiRes::time, $msg;
}

sub new {
    my ($class, %args) = @_;

    bless {
        tag           => $args{tag}   // 'punytan/p5-test-docker-mysql',
        ports         => $args{ports} // [ 55500 .. 55555 ],
        container_ids => [],
    }, $class;
}

sub get_port {
    my $self = shift;
    $self->docker('ps'); # guarantee docker connection
    my $port = $self->find_port;
    return $port;
}

sub find_port {
    my $self = shift;

    while (1) {
        my $port = $self->{ports}[ int rand(scalar @{$self->{ports}}) ];
        DEBUG && WARN "trying port $port";
        my $container = eval { $self->docker(run => -p => "$port:3306", -d => $self->{tag}) };
        if (my $e = $@) {
            DEBUG && WARN "Failed to launch container: $e";
            next;
        } else {
            push @{$self->{container_ids}}, $container;
            eval { $self->_dbh($port) };
            if (my $e = $@) {
                DEBUG && WARN "Failed to get dbh: $e";
                next;
            } else {
                return $port;
            }
        }
    }

    die "Failed to allocate new container";
}

sub _dbh {
    my ($self, $port) = @_;

    my $dbh;

    while (not defined $dbh) {
        my $dsn = "dbi:mysql:database=mysql;host=127.0.0.1;port=$port";

        DEBUG && WARN "Connecting dsn: $dsn";

        $dbh = eval { DBI->connect($dsn, 'root', '', { RaiseError => 1 }) };
        if (my $e = $@) {
            DEBUG && WARN "Failed to connect mysql server: $e";
            sleep 0.2;
        }
    };

    DEBUG && WARN "Creating database: docker_mysql";
    eval { $dbh->do("CREATE DATABASE docker_mysql") };
    if (my $e = $@) {
        DEBUG && WARN "Failed to get lock (create database): $e";
        # Skip this container
    }

    DEBUG && WARN "Created database: docker_mysql";
}

sub docker {
    my ($self, $cmd, @args) = @_;
    $self->cmd(docker => $cmd, @args);
}

sub cmd {
    my ($self, @args) = @_;

    DEBUG && WARN sprintf "Run [ %s ]", join ' ', @args;
    my $is_success = IPC::Run::run [ @args ], \my $stdin, \my $stdout, \my $stderr;
    if ($is_success) {
        chomp $stdout;
        return $stdout;
    } else {
        die $stderr;
    }
}

sub DESTROY {
    my $self = shift;
    for my $container_id (@{$self->{container_ids}}) {
        DEBUG && WARN "Destroying container: $container_id";
        $self->docker(kill => $container_id);
    }
}

1;
__END__

=encoding utf-8

=head1 NAME

Test::Docker::MySQL is a module to launch MySQL in docker containers.

=head1 SYNOPSIS

    # You have to setup docker manually before you use this (see SETUP section)

    $ENV{DOCKER_HOST} ||= 'tcp://192.168.59.103:2375'; # optional

    use Test::Docker::MySQL;
    my $dm_guard = Test::Docker::MySQL->new;

    my $port_1 = $guard->get_port; # get a mysql container port
    my $port_2 = $guard->get_port; # get another mysql container port

    my $dsn_1 = "dbi:mysql:database=mysql;host=127.0.0.1;port=$port_1";
    my $dbh_1 = DBI->connect($dsn , 'root', '', { RaiseError => 1 });

    my $dsn_2 = "dbi:mysql:database=mysql;host=127.0.0.1;port=$port_2";
    my $dbh_2 = DBI->connect($dsn , 'root', '', { RaiseError => 1 });

    undef $dm_guard; # dispatch `docker kill $container` command

=head1 DESCRIPTION

Test::Docker::MySQL is a module to launch MySQL in docker containers.

=head1 METHODS

=head2 C<new>

All parameters are optional.

=over 4

=item C<tag>

The tag to launch via Docker. Default value is C<punytan/p5-test-docker-mysql>.

=item C<ports>

Specify port range by C<ports>>. Default value is C<[ 55500 .. 55555 ]>,

=back

=head2 C<get_port>

Returns allocated port.

=head1 SETUP

=head2 OSX

=over 4

=item Install boot2docker and docker

You can find the binary at L<https://github.com/boot2docker/osx-installer/releases>.

=item Initialize boot2docker

    $ boot2docker download && boot2docker init && boot2docker up

=item Configure port forwarding

    $ boot2docker down
    $ for i in {55500..55555}; do
        VBoxManage modifyvm "boot2docker-vm" --natpf1 "tcp-port$i,tcp,,$i,,$i";
        VBoxManage modifyvm "boot2docker-vm" --natpf1 "udp-port$i,udp,,$i,,$i";
    done
    $ boot2docker up

=item Pull docker images for this module

    $ docker pull punytan/p5-test-docker-mysql

=back

=head1 CHEATSHEET

=head2 Clean up containers

    $ docker kill $(docker ps -a -q)
    $ docker rm   $(docker ps -a -q)

=head1 DEBUGGING

Set C<DEBUG_TEST_DOCKER_MYSQL> as true to get verbose log generated by this module.

=head1 AUTHOR

punytan E<lt>punytan@gmail.comE<gt>

=head1 COPYRIGHT

Copyright 2014- punytan

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Test::mysqld>

=cut
