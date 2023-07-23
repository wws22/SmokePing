package Smokeping::probes::Asterisk;

=head1 301 Moved Permanently

This is a Smokeping probe module. Please use the command 

C<smokeping -man Smokeping::probes::Asterisk>

to view the documentation or the command

C<smokeping -makepod Smokeping::probes::Asterisk>

to generate the POD document.

=cut

use strict;
use base qw(Smokeping::probes::basefork);
use Carp;

my $DEFAULTBIN = "/usr/bin/ping";

sub pod_hash {
    return {
	name => "Smokeping::probes::Asterisk - an universal probe for SmokePing",
	overview => "Fetches something using external command ex: /usr/bin/ping",
	description => "(There is an universal probe for SmokePing. See man(1) for details of the options below)",
	authors => <<'DOC',
    Victor Selyukov <victor.selukov at gmail.com>
    Gerald Combs <gerald [AT] ethereal.com>
    Niko Tyni <ntyni@iki.fi>
DOC
	notes => <<'DOC',
    You should consider setting a lower value for the C<pings> variable than the
    default 20, as repetitive result fetching may be quite heavy on the server.

    The destination to be tested used to be specified by the variable 'destination',
    and the 'host' setting did not influence it in any way.
    The variable name has now been named 'destination', and it can
    (and in most cases should) contain a placeholder for the 'host' variable.
DOC
    }
}

sub probevars {
	my $class = shift;
	my $h = $class->SUPER::probevars;
	delete $h->{timeout};
	return $class->_makevars($h, {
		binary => {
			_doc => "The location of your binary.",
			_default => $DEFAULTBIN,
			_sub => sub {
				my $val = shift;
				return "ERROR: 'binary' $val does not point to an executable"
					unless -f $val and -x _;
				return undef;
			},
		},
	});
}

sub targetvars {
	my $class = shift;
	return $class->_makevars($class->SUPER::targetvars, {
		_mandatory => [ ], # [ 'args' ]
		destination => {
			_doc => <<'DOC',
    The template of the destination to fetch.  Can be any one that your binary
    supports. Any occurrence of the string '%host%' will be replaced with the
    host to be probed. Using curl you should use 'https://%host%/' or something
    like that.
DOC
			_default => '%host%',
			_example => '%host%',
		},
		args => {
			_doc => <<'DOC',
    Any arguments you might want to hand to your binary. The arguments
    should be separated by the regexp specified in "extrare", which
    contains just the space character (" ") by default.

    Note that program will be called with the resulting list of arguments
    without any shell expansion. If you need to specify any arguments
    containing spaces, you should set "extrare" to something else.

    As a complicated example, to explicitly set the "Host:" header in Curl
    requests, you need to set "extrare" to something else, eg. "/;/",
    and then specify C<args = --header;Host: www.example.com>.
DOC
			_default => '-i 1 -c 1',
			_example => '-i 1 -c 1',
		},
		extrare=> {
			_doc => <<'DOC',
    The regexp used to split the args string into an argument list,
    in the "/regexp/" notation.  This contains just the space character
    (" ") by default, but if you need to specify any arguments containing spaces,
    you can set this variable to a different value.
DOC
			_default => "/ /",
			_example => "/ /",
			_sub => sub {
				my $val = shift;
				return 'extrare should be specified in the /regexp/ notation'
					unless $val =~ m,^/.*/$,;
				return undef;
			},
		},
		expect => {
            _doc => <<'DOC',
    Require the given text to appear somewhere in the response, otherwise
    probe is treated as a failure
DOC
			_default => '',
        },
		filter => {
			_doc => <<'DOC',
    Perl 's/regexp/replace/ms[ie]' expression used to get the result from STDOUT
    As an example: s/.*time=(.*)\s+ms.*/int($1)/mse for a given line:
        64 bytes from 192.168.0.1: icmp_seq=1 ttl=63 time=6.52 ms
    means:
	    1. Find 'time=6.52 ms' and keep '6.52'
	    2. Execute perl code 'int(6.52)' to get '6'

    You can use %host% patern in the regexp part.
    Ex:
        host = some.host
        filter = s/.*%host%.*\s+OK\s+\((\d+).*/$1/ms
    the result:
        filter = s/some\.host/replace/ms

    NB!!! Please be careful using 'e' at the end of the expression!
          's/.../qx{echo $1}/msxe' will execute
          the command 'echo $1' as a privileged user !!!
          Use 's///msx' for most cases to prevent the leaks.
DOC
			_default => 's/.*time=(.*)\s+ms.*/$1/ms',
			_example => 's/.*time=(.*)\s+ms.*/int($1)/mse',
			_sub => sub {
				my $val = shift;
				return q{filter should be specified in the 's/.*regexp.*/$1/ms' notation}
					unless $val =~ m,^s/.*/.*/ms[ie]*$,;
				return undef;
			},
		},
	});
}

# derived class will mess with this through the 'features' method below
my $featurehash = {
	#agent => "-A",
	#timeout => "-m",
	#interface => "--interface",
};

sub features {
	my $self = shift;
	my $newval = shift;
	$featurehash = $newval if defined $newval;
	return $featurehash;
}

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $self = $class->SUPER::new(@_);

	$self->_init if $self->can('_init');

	return $self;
}

sub ProbeDesc($) {
	return "Test something using external program";
}

# other than host, count and protocol-specific args come from here
sub make_args {
	my $self = shift;
	my $target = shift;
	my @args;
	my %arghash = %{$self->features};

	for (keys %arghash) {
		my $val = $target->{vars}{$_};
		push @args, ($arghash{$_}, $val) if defined $val;
	}
	return @args;
}

sub p_args {
	my $self = shift;
	my $target = shift;
	my $args = $target->{vars}{args};
	return () unless defined $args;
	my $re = $target->{vars}{extrare};
	($re =~ m,^/(.*)/$,) and $re = qr{$1};
	return split($re, $args);
}

sub make_commandline {
	my $self = shift;
	my $target = shift;
	my $count = shift;

	my @args = $self->make_args($target);
	my $dests = $target->{vars}{destination};
	my $host = $target->{addr};
	$dests =~ s/%host%/$host/g;
	my $quoted_host = $host;
	$quoted_host =~ s/\./\\./gms;
	$target->{vars}{filter} =~ s/%host%/$quoted_host/ms;
	my @dsts = split(/\s+/, $dests);
	push @args, $self->p_args($target);

	return ($self->{properties}{binary}, @args, @dsts);
}

sub pingone {
	my $self = shift;
	my $t = shift;

	my @cmd = $self->make_commandline($t);

	$self->do_debug("executing command list " . join(",", map { qq('$_') } @cmd));

	my @times;
	my $count = $self->pings($t);

	for (my $i = 0 ; $i < $count; $i++) {
		open(P, "-|") or exec @cmd;

		my $val;
		my $expectOK = 1;
		$expectOK = 0 if ($t->{vars}{expect} ne "");
		while (<P>) {
			chomp;
			if (!$expectOK and index($_, $t->{vars}{expect}) != -1) {
			    $expectOK = 1;
			}
			my $response = $_;
			eval( $t->{vars}{filter} ) and do {
				$val += $_;
				$self->do_debug( $t->{vars}{binary} . " >>> '$response', result: $val");
			};
		}
		close P;
		if ($?) {
			my $status = $? >> 8;
			my $signal = $? & 127;
			my $why = "with status $status";
			$why .= " [signal $signal]" if $signal;

			# only log warnings on the first ping of the first ping round
			my $function = ($self->rounds_count == 1 and $i == 0) ? 
				"do_log" : "do_debug";

			$self->$function(qq(WARNING: program exited $why on $t->{addr}));
		}
		push @times, $val if (defined $val and $expectOK);
	}

	# carp("Got @times") if $self->debug;
	return sort { $a <=> $b } @times;
}

1;
